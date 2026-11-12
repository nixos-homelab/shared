{ self, inputs, ... }:
{
  lib,
  pkgs,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  flakePkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
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
    data-dir = ccfg.dataDir;
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
    tls-san = "external.${ccfg.domain}";
    kube-controller-manager-arg = [
      "allocate-node-cidrs"
    ]
    ++ lib.optional ccfg.enableIPv4 "node-cidr-mask-size-ipv4=${builtins.toString (ipv4.fromString ccfg.podCidr4).prefixLength}"
    ++ lib.optional ccfg.enableIPv6 "node-cidr-mask-size-ipv6=96";
  });
in
{
  # https://github.com/hercules-ci/flake-parts/pull/251
  key = "${toString __curPos.file}#modules.nixos.cluster";
  options.homelab.cluster = {
    enable = lib.mkEnableOption "the homelab cluster";
    enableIPv4 = lib.mkOption {
      description = "IPv4 support";
      type = lib.types.bool;
      default = true;
    };
    enableIPv6 = lib.mkEnableOption "IPv6 support";
    debugTools = lib.mkOption {
      description = "Tools to embed in container images when debugging is enabled";
      type = lib.types.listOf lib.types.package;
      defaultText = "bash, coreutils, netcat, curl, jq, dig, ping, ip, tcpdump";
      default = [
        pkgs.bash
        pkgs.coreutils
        pkgs.netcat-gnu
        pkgs.curl
        pkgs.jq
        pkgs.dig
        pkgs.unixtools.ping
        pkgs.iproute2
        pkgs.tcpdump
      ];
    };
    podCidr4 = lib.mkOption {
      description = "IPv4 CIDR for the pods";
      type = lib.types.str;
      default = "10.42.0.0/16"; # k3s default: https://docs.k3s.io/cli/server?_highlight=cidr#networking
    };
    podCidr6 = lib.mkOption {
      description = "IPv6 CIDR for the pods";
      type = lib.types.str;
    };
    svcCidr4 = lib.mkOption {
      description = "IPv4 CIDR for the services";
      type = lib.types.str;
      default = "10.43.0.0/16"; # k3s default: https://docs.k3s.io/cli/server?_highlight=cidr#networking
    };
    svcCidr6 = lib.mkOption {
      description = "IPv6 CIDR for the services";
      type = lib.types.str;
    };
    domain = lib.mkOption {
      description = "Domain name of the cluster";
      type = lib.types.str;
    };
    acmeProvider = lib.mkOption {
      description = "The ACME provider that Ingresses should use for obtaining TLS certs";
      type = lib.types.str;
    };
    dataDir = lib.mkOption {
      description = "Location of the k3s data directory";
      type = lib.types.str;
    };
    imageLocks = lib.mkOption {
      description = "The image refs each lock file of `lib.images.locked` and `lib.images.chart` pins, by its path, for `lock-images` to re-lock them when what names them changes";
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
    };
    sourceLocks = lib.mkOption {
      description = "The fetches each lock file of `lib.pins.locked` pins, by its path and their key, without their hash, for `lock-images` to lock them when a pin changes";
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.package);
      default = { };
    };
    backup.hostPaths = lib.mkOption {
      description = "List of paths on the host that *should* be backed up, this option does not configure a backup, it is only meant for aggregation";
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
    backup.volumes = lib.mkOption {
      description = "A map of namespace -> PV claim name -> paths that *should* be backed up, this option does not configure a backup, it is only meant for aggregation";
      type = lib.types.attrsOf (lib.types.attrsOf (lib.types.listOf lib.types.str));
      default = { };
    };
  };
  imports = [
    inputs.kubetree.nixosModules.default
    (import ./kubenix { inherit self inputs; })
    self.nixosModules.workload-macros
    inputs.setup-secrets.nixosModules.default
  ];
  config = lib.mkIf ccfg.enable {
    systemd.services."setup-secrets".after = [ "k3s.service" ];
    services.k3s.enable = true;
    kubetree = {
      kubernetes.enable = true;
      workload-macros = {
        enable = true;
        domain = ccfg.domain;
      };
      k3s.enable = true;
    };

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "k9s" ''KUBECONFIG=/etc/rancher/k3s/k3s.yaml exec ${lib.getExe pkgs.k9s} "$@"'')
      (pkgs.writeShellScriptBin "cilium" ''KUBECONFIG=/etc/rancher/k3s/k3s.yaml exec ${lib.getExe pkgs.cilium-cli} "$@"'')
    ];
    homelab.cluster.backup.hostPaths = [
      "${ccfg.dataDir}/server/token"
      "${ccfg.dataDir}/server/db"
    ];
    systemd.tmpfiles.settings."50-k3s-data"."/var/lib/rancher/k3s"."L+" = {
      user = "root";
      group = "root";
      mode = "0755";
      argument = ccfg.dataDir;
    };
    systemd.globalEnvironment.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
    # https://github.com/cilium/cilium/issues/31565#issuecomment-3419710315
    networking.firewall.checkReversePath = false;
    networking.firewall.allowedTCPPorts = [ 6443 ];
    systemd.services.k3s.unitConfig.RequiresMountsFor = [ ccfg.dataDir ];
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
      images = [
        flakePkgs.container-utils
        # pause, coredns, metrics-server and the other images k3s runs itself, so nothing is pulled at runtime
        config.services.k3s.package.airgap-images
      ];
      configPath = k3sConfig;
      disable = [
        "runtimes"
        "local-storage"
      ];
    };
  };
}
