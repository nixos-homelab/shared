{ self, inputs, ... }:
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.homelab.k3s;
  ccfg = config.homelab.cluster;
  kubeconfig = "/etc/rancher/k3s/k3s.yaml";
  provided = component: lib.elem component ccfg.providedComponents;
  ipv4 = self.lib.ipv4;
  kubelib = inputs.kube-generators.lib { inherit pkgs; };
  node = config.networking.hostName;
  drainedAnnotation = "cluster.local/drained-for-shutdown";
  kubectl = "${lib.getExe config.services.k3s.package} kubectl --request-timeout=10s";
  drain = pkgs.writeShellApplication {
    name = "k3s-drain";
    runtimeInputs = [
      config.systemd.package
      pkgs.coreutils
    ];
    text = ''
      # Only logind's own signal: any client on the bus may emit one
      while :; do
        signal=$(busctl wait org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager PrepareForShutdown)
        [[ $signal = "b true" ]] && break
      done
      # A node cordoned by hand stays cordoned after the boot
      if [[ $(${kubectl} get node ${node} -o jsonpath='{.spec.unschedulable}') != true ]]; then
        ${kubectl} annotate node ${node} ${drainedAnnotation}=true --overwrite
      fi
      timeout 40 ${kubectl} drain ${node} --ignore-daemonsets --delete-emptydir-data --force --timeout=35s || true
    '';
  };
  uncordon = pkgs.writeShellApplication {
    name = "k3s-uncordon";
    text = ''
      drained=$(${kubectl} get node ${node} -o jsonpath='{.metadata.annotations.${
        lib.replaceStrings [ "." ] [ "\\." ] drainedAnnotation
      }}')
      if [[ $drained = true ]]; then
        ${kubectl} uncordon ${node}
        ${kubectl} annotate node ${node} ${drainedAnnotation}-
      fi
    '';
  };
  k3sConfig = kubelib.toYAMLFile ({
    data-dir = cfg.dataDir;
    flannel-backend = "none";
    egress-selector-mode = "disabled";
    disable-network-policy = true;
    disable-kube-proxy = true;
    disable-helm-controller = true;
    embedded-registry = true;
    kube-apiserver-arg = [ "service-node-port-range=1024-32767" ];
    # k3s imports the preloaded images without unpacking them, so the first container of an image unpacks it. A big
    # image on a slow disk outlasts k3s' 2 minutes, and each retry starts over
    kubelet-arg = [ "runtime-request-timeout=10m" ];
    cluster-cidr =
      lib.optional ccfg.enableIPv4 ccfg.podCidr4 ++ lib.optional ccfg.enableIPv6 ccfg.podCidr6;
    service-cidr =
      lib.optional ccfg.enableIPv4 ccfg.svcCidr4 ++ lib.optional ccfg.enableIPv6 ccfg.svcCidr6;
    tls-san = "external.${config.homelab.workloads.domain}";
    kube-controller-manager-arg = [
      "allocate-node-cidrs"
    ]
    ++ lib.optional ccfg.enableIPv4 "node-cidr-mask-size-ipv4=${builtins.toString (ipv4.fromString ccfg.podCidr4).prefixLength}"
    ++ lib.optional ccfg.enableIPv6 "node-cidr-mask-size-ipv6=96";
  });
in
{
  # https://github.com/hercules-ci/flake-parts/pull/251
  key = "${toString __curPos.file}#modules.nixos.k3s";
  options.homelab.k3s = {
    enable = lib.mkEnableOption "k3s as the runner of the homelab cluster";
    dataDir = lib.mkOption {
      description = "Location of the k3s data directory";
      type = lib.types.str;
    };
  };
  imports = [
    self.nixosModules.cluster
    inputs.setup-secrets.nixosModules.default
  ];
  config = lib.mkIf cfg.enable {
    homelab.cluster = {
      inherit kubeconfig;
      unit = "k3s.service";
      kubernetesVersion = lib.head (lib.splitString "+" config.services.k3s.package.version);
      # The manifests as k3s finds them in its manifests directory
      payload = pkgs.runCommand "k3s-payload" { } ''
        mkdir "$out"
        ${lib.concatStrings (
          lib.mapAttrsToList (path: rule: ''
            ln -s "${rule."L+".argument}" "$out/${baseNameOf path}"
          '') (lib.filterAttrs (path: _: baseNameOf (dirOf path) == "manifests") config.systemd.tmpfiles.settings."10-k3s")
        )}
      '';
      backup.hostPaths = [
        "${cfg.dataDir}/server/token"
        "${cfg.dataDir}/server/db"
      ];
    };
    systemd.services."setup-secrets".after = [ "k3s.service" ];
    services.k3s.manifests = lib.mapAttrs (
      _: manifest:
      { inherit (manifest) enable; }
      // (if manifest.content != null then { inherit (manifest) content; } else { inherit (manifest) source; })
    ) ccfg.manifests;
    services.k3s.enable = true;
    # The neutral path `lib.setup-secrets.mkScript` reads
    environment.etc."kubernetes/kubeconfig".source = kubeconfig;

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "k9s" ''KUBECONFIG=${kubeconfig} exec ${lib.getExe pkgs.k9s} "$@"'')
    ];
    systemd.tmpfiles.settings."50-k3s-data"."/var/lib/rancher/k3s"."L+" = {
      user = "root";
      group = "root";
      mode = "0755";
      argument = cfg.dataDir;
    };
    systemd.globalEnvironment.KUBECONFIG = kubeconfig;
    networking.firewall.allowedTCPPorts = [ 6443 ];
    systemd.services.k3s.unitConfig.RequiresMountsFor = [ cfg.dataDir ];
    systemd.services.k3s.restartTriggers = [
      config.services.k3s.images
      k3sConfig
    ];
    # k3s exits without a default route or with only some of the cluster's IP families, and network-online.target can
    # be reached before either (wait-online --any settles for a link that isn't routable yet)
    systemd.services.k3s.serviceConfig.ExecStartPre = lib.mkIf config.networking.useNetworkd [
      (lib.join " " (
        [
          "${config.systemd.package}/lib/systemd/systemd-networkd-wait-online"
          "--any"
          "--operational-state=routable"
          "--timeout=120"
        ]
        ++ lib.optional ccfg.enableIPv4 "--ipv4"
        ++ lib.optional ccfg.enableIPv6 "--ipv6"
      ))
    ];
    # Container scopes have no shutdown dependencies, so systemd only kills them at the very end, after services
    # they use (the NFS server) are gone. The kubelet stops the pods first when it gets logind's shutdown signal, and
    # logind only waits InhibitDelayMaxSec for it (5 s by default) of the 30 s shutdownGracePeriod
    services.logind.settings.Login.InhibitDelayMaxSec = 45;
    # The kubelet's shutdown marks the pods it stops as Failed, rejects (as Failed) the replacements that tolerate a
    # NotReady node, and leaves them all behind (https://github.com/kubernetes/kubernetes/issues/139246). Draining
    # first deletes them and keeps the replacements Pending, cordoned, until the node is back. It holds its own delay
    # lock from logind's PrepareForShutdown on; the kubelet's shutdown stays as the backstop for DaemonSet pods
    systemd.services.k3s-drain = {
      description = "Drain the node when it shuts down";
      after = [ "k3s.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = lib.join " " [
        "${config.systemd.package}/bin/systemd-inhibit"
        "--what=shutdown"
        "--mode=delay"
        "--who=k3s-drain"
        "--why='Drain the node'"
        (lib.getExe drain)
      ];
    };
    # Lifts the drain's cordon once the API is up, not one set by hand
    systemd.services.k3s-uncordon = {
      description = "Uncordon the node after a drain at shutdown";
      after = [ "k3s.service" ];
      wantedBy = [ "multi-user.target" ];
      startLimitIntervalSec = 0;
      serviceConfig = {
        Type = "oneshot";
        Restart = "on-failure";
        RestartSec = 10;
        ExecStart = lib.getExe uncordon;
      };
    };
    services.k3s = {
      gracefulNodeShutdown.enable = true;
      images = ccfg.images ++ [
        # pause, coredns, metrics-server and the other images k3s runs itself, so nothing is pulled at runtime
        config.services.k3s.package.airgap-images
      ];
      configPath = k3sConfig;
      # What the modules deploy themselves, in the order that the modules once wrote them in, so the unit stays the same
      disable =
        lib.optional (provided "metrics-server") "metrics-server"
        ++ lib.optional (provided "ingress") "traefik"
        ++ lib.optional (provided "load-balancer") "servicelb"
        ++ [
          "runtimes"
          "local-storage"
        ];
    };
  };
}
