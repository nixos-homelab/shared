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
  # Where k3s imports images from, through the link to the data directory
  imageDir = "/var/lib/rancher/k3s/agent/images";
  # A docker archive as an OCI archive with zstd-compressed layers, under the reference containerd gives the docker
  # archive's tag (`redis:8` is `docker.io/library/redis:8`). containerd keeps the layers compressed, which the docker
  # archives of `dockerTools` and `pullImage` don't have. The archive is self-contained, but its uncompressed JSON
  # names store paths (the store hash in a tag, those in the image config) that Nix would take for references
  zstdArchive =
    image:
    pkgs.runCommand "${lib.removeSuffix ".tar" (lib.removeSuffix ".gz" image.name)}-zstd.tar"
      {
        nativeBuildInputs = [
          pkgs.jq
          pkgs.skopeo
        ];
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
      }
      ''
        manifest=$(tar -xOf ${image} manifest.json)
        jq -e 'length == 1 and (.[0].RepoTags | length) == 1' <<<"$manifest" >/dev/null
        ref=$(jq -r '.[0].RepoTags[0]' <<<"$manifest")
        domain=''${ref%%/*}
        if [[ $ref != */* ]]; then
          ref=docker.io/library/$ref
        elif [[ $domain != *.* && $domain != *:* && $domain != localhost ]]; then
          ref=docker.io/$ref
        fi
        skopeo --tmpdir "$TMPDIR" --insecure-policy copy -q --dest-compress-format zstd \
          "docker-archive:${image}" "oci-archive:$out:$ref"
      '';
  images =
    map (
      image: if cfg.zstdImages && !lib.hasSuffix ".zst" image.name then zstdArchive image else image
    ) ccfg.images
    ++ [
      # pause, coredns, metrics-server and the other images k3s runs itself, so nothing is pulled at runtime
      config.services.k3s.package.airgap-images
    ];
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
    zstdImages = lib.mkEnableOption ''
      recompressing the images into OCI archives with zstd-compressed layers: about half the size in the store, and
      the first import (every image) about a third as long, as containerd keeps the layers compressed. It takes a few
      seconds of build per image. Meant for systems that are copied whole (installer and disk images), as later
      deploys import only the images that changed'';
  };
  imports = [
    self.nixosModules.cluster
    inputs.setup-secrets.nixosModules.default
    ./prune.nix
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
          lib.mapAttrsToList
            (path: rule: ''
              ln -s "${rule."L+".argument}" "$out/${baseNameOf path}"
            '')
            (
              lib.filterAttrs (
                path: _: baseNameOf (dirOf path) == "manifests"
              ) config.systemd.tmpfiles.settings."10-k3s"
            )
        )}
      '';
      backup.hostPaths = [
        "${cfg.dataDir}/server/token"
        "${cfg.dataDir}/server/db"
      ];
    };
    # The policy intent of the metrics-server k3s bundles, unless a module deploys one: the API server calls it as the
    # metrics API, pods labeled `cluster.local/metrics-server-egress: allow` may reach it. Its own egress, to the
    # kubelets and the API server, is up to the module of the CNI, as the policy intent has no egress
    homelab.kubernetes.submodules.instances.metrics-server-policy =
      lib.mkIf (!provided "metrics-server")
        {
          submodule = "manifest";
          config = {
            kubernetes.namespace = "kube-system";
            submodules.instances.metrics-server = {
              submodule = "pods";
              args = {
                selector.k8s-app = "metrics-server";
                ports.https = 10250;
                apiServerPorts = [ "https" ];
              };
            };
          };
        };
    systemd.services."setup-secrets".after = [ "k3s.service" ];
    services.k3s.manifests = lib.mapAttrs (
      _: manifest:
      {
        inherit (manifest) enable;
      }
      // (
        if manifest.content != null then { inherit (manifest) content; } else { inherit (manifest) source; }
      )
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
      images
      k3sConfig
    ];
    # k3s exits without a default route of each of the cluster's IP families, and network-online.target can be reached
    # before them. So can systemd-networkd-wait-online: a routable address isn't a default route, and with --any a link
    # without one (a WireGuard link with static addresses) counts. So this waits for the routes themselves
    systemd.services.k3s.serviceConfig.ExecStartPre = [
      (lib.getExe (
        pkgs.writeShellApplication {
          name = "k3s-wait-default-routes";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.iproute2
          ];
          text = ''
            for _ in $(seq 120); do
              if ${lib.optionalString ccfg.enableIPv4 "[[ -n $(ip -4 route show default) ]] &&"} \
                ${lib.optionalString ccfg.enableIPv6 "[[ -n $(ip -6 route show default) ]] &&"} true; then
                exit 0
              fi
              sleep 1
            done
            printf "No default route of each IP family of the cluster after 120 s, starting anyway\n" >&2
          '';
        }
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
    # The image links, in place of `services.k3s.images` of the nixpkgs module, which names each link after the image
    # alone. k3s skips a file whose size and mtime match its entry in `.cache.json`, and all store paths share one
    # mtime, so each link carries its store path in its name: a changed image gets a new link, which k3s imports, and
    # every start after the first skips the rest. k3s keeps the cache only in a file that exists, and drops the entries
    # of links that are gone. An entry for an image that containerd no longer has keeps it from being imported again:
    # delete the file, and k3s imports every link at its next start
    systemd.tmpfiles.settings."10-k3s" =
      lib.listToAttrs (
        map (
          image:
          lib.nameValuePair "${imageDir}/${builtins.unsafeDiscardStringContext (baseNameOf image)}" {
            "L+".argument = "${image}";
          }
        ) images
      )
      // {
        "${imageDir}/.cache.json".f.mode = "0644";
      };
    services.k3s = {
      gracefulNodeShutdown.enable = true;
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
