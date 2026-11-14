{ self, ... }:
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.homelab.cluster;
  container-utils = self.packages.${pkgs.stdenv.hostPlatform.system}.container-utils;
in
{
  # https://github.com/hercules-ci/flake-parts/pull/251
  key = "${toString __curPos.file}#modules.nixos.cluster";
  # The facts of the cluster that modules read and write, whichever runner runs it. A runner module (`k3s`) imports
  # this one, takes the images and manifests from here and sets the facts only it knows
  options.homelab.cluster = {
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
      default = "10.42.0.0/16";
    };
    podCidr6 = lib.mkOption {
      description = "IPv6 CIDR for the pods";
      type = lib.types.str;
    };
    svcCidr4 = lib.mkOption {
      description = "IPv4 CIDR for the services";
      type = lib.types.str;
      default = "10.43.0.0/16";
    };
    svcCidr6 = lib.mkOption {
      description = "IPv6 CIDR for the services";
      type = lib.types.str;
    };
    images = lib.mkOption {
      description = "Container images to preload on the node, so that nothing is pulled at runtime";
      type = lib.types.listOf lib.types.package;
      default = [ ];
    };
    manifests = lib.mkOption {
      description = "Manifests for the runner to apply, by name. The runner deletes what a manifest stops holding, so an object stays in the manifest it was in.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkOption {
              description = "Whether the runner applies this manifest";
              type = lib.types.bool;
              default = true;
            };
            content = lib.mkOption {
              description = "Objects of the manifest: one, or a list of them";
              type = lib.types.nullOr (lib.types.either lib.types.attrs (lib.types.listOf lib.types.attrs));
              default = null;
            };
            source = lib.mkOption {
              description = "A YAML file of the manifest, in place of `content`";
              type = lib.types.path;
            };
          };
        }
      );
      default = { };
    };
    providedComponents = lib.mkOption {
      description = "Cluster components a module deploys itself, so the runner leaves out the one it may bundle";
      type = lib.types.listOf (
        lib.types.enum [
          "ingress"
          "load-balancer"
          "metrics-server"
        ]
      );
      default = [ ];
    };
    kubeconfig = lib.mkOption {
      description = "Path of a kubeconfig with admin rights on the node, as the runner writes it. Set by the runner.";
      type = lib.types.str;
    };
    unit = lib.mkOption {
      description = "The systemd unit that runs the cluster, for units that need the API to order after. Set by the runner.";
      type = lib.types.str;
      example = "k3s.service";
    };
    kubernetesVersion = lib.mkOption {
      description = "The Kubernetes version the cluster runs (`1.35.8`). Set by the runner.";
      type = lib.types.str;
    };
    payload = lib.mkOption {
      description = "A directory of the manifests as the runner applies them; build `nixosConfigurations.<host>.config.homelab.cluster.payload` to look at them. Set by the runner.";
      type = lib.types.package;
    };
    imageLocks = lib.mkOption {
      description = "The image refs each lock file of `lib.images.locked` and `lib.images.chart` pins, by its path, for `lock-images` to re-lock them when what names them changes";
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
    };
    runtimeCRDs = lib.mkOption {
      description = "CustomResourceDefinition files of resources whose CRDs no manifest carries, as an operator creates them at runtime (a CNI's), for the manifests check to validate those resources against";
      type = lib.types.listOf lib.types.path;
      default = [ ];
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
  imports = [ self.nixosModules.workloads ];
  config = {
    homelab.kubernetes.kubernetes.version = lib.versions.majorMinor cfg.kubernetesVersion;
    homelab.cluster.manifests = lib.mapAttrs (_: content: { inherit content; }) config.homelab.workloads.manifests;
    # Last, where the runner module once put it, so the images keep their order
    homelab.cluster.images = lib.mkAfter [ container-utils ];
  };
}
