{ inputs, self, ... }:
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.homelab.nfs-provisioner;
  kubelib = inputs.kube-generators.lib { inherit pkgs; };
  # The chart and the provisioner from the same commit of main: 4.0.18 has a broken helm chart, and the only published
  # image, v4.0.2, ignores the chart's NFS_DEFAULT_MODE, _UID and _GID (it creates every volume 0777)
  src = pkgs.fetchFromGitHub {
    repo = "nfs-subdir-external-provisioner";
    owner = "kubernetes-sigs";
    rev = "f4d56f8285ebab2a8f245a3983271e418c9f84e4";
    hash = "sha256-ATu6cw+Bckn585OMbE7HM6KoZah2MNU2J0g4xDxlbRw=";
  };
  provisioner = pkgs.buildGo126Module {
    pname = "nfs-subdir-external-provisioner";
    version = "4.0.18-unstable-${builtins.substring 0 7 src.rev}";
    inherit src;
    # Its vendor/ is stale against go.mod (upstream builds with -mod=mod)
    deleteVendor = true;
    vendorHash = "sha256-REoG9isT4P8RoPLcg59Z0t56m6PbOrb6cdo15SRgBCg=";
    subPackages = [ "cmd/nfs-subdir-external-provisioner" ];
    env.CGO_ENABLED = 0;
    meta.mainProgram = "nfs-subdir-external-provisioner";
  };
  image = pkgs.dockerTools.buildImage {
    name = "cluster.local/nfs-subdir-external-provisioner";
    copyToRoot = [ provisioner ];
    config.Entrypoint = [ (lib.getExe provisioner) ];
  };
in
{
  options.homelab.nfs-provisioner = {
    enable = lib.mkEnableOption "the NFS volume provisioner";
    server = lib.mkOption {
      description = "NFS server to use as persistent data store";
      type = lib.types.str;
      defaultText = "\${config.networking.hostName}.\${config.homelab.cluster.domain}";
      default = "${config.networking.hostName}.${config.homelab.cluster.domain}";
    };
    path = lib.mkOption {
      description = "Export on the NFS server to use as the root";
      type = lib.types.str;
    };
    pathPattern = lib.mkOption {
      description = "Naming scheme for volumes on the NFS server";
      type = lib.types.str;
      default = "\${.PVC.namespace}-\${.PVC.name}";
    };
    mountpointOwnership = {
      mode = lib.mkOption {
        description = "Filesystem mode to create the mountpoint with";
        type = lib.types.str;
        default = "750";
      };
      uid = lib.mkOption {
        description = "UID ownership of the mountpoint";
        type = lib.types.int;
        default = 0;
      };
      gid = lib.mkOption {
        description = "GID ownership of the mountpoint";
        type = lib.types.int;
        default = 0;
      };
    };
    backupPaths = lib.mkOption {
      description = ''
        List of paths that should be backed up according to `config.homelab.cluster.backup.volumes`.
        The paths are constructed using `cfg.path` and `cfg.pathPattern`.
        Only `.PVC.namespace` and `.PVC.name` placeholders are replaced in the pattern.
      '';
      type = lib.types.listOf lib.types.path;
      default = lib.flatten (
        lib.mapAttrsToList (
          namespace: spec:
          lib.flatten (
            lib.mapAttrsToList (
              pvName: paths:
              map (
                path:
                lib.removeSuffix "/" "${cfg.path}/${
                  builtins.replaceStrings [ "\${.PVC.namespace}" "\${.PVC.name}" ] [ namespace pvName ]
                    cfg.pathPattern
                }/${lib.removePrefix "/" path}"
              ) paths
            ) spec
          )
        ) (config.homelab.cluster.backup.volumes)
      );
      defaultText = "";
    };
  };
  config = lib.mkIf cfg.enable {
    kubetree.resources.nfs-provisioner.namespace = self.lib.k8s.createNamespace {
      namespace = "nfs-provisioner";
    };
    services.k3s.images = [ image ];
    services.k3s.manifests = {
      nfs-provisioner-helm.source =
        self.lib.k8s.patchManifest { inherit pkgs; }
          (kubelib.buildHelmChart {
            name = "nfs-subdir-external-provisioner";
            namespace = "nfs-provisioner";
            chart = "${src}/charts/nfs-subdir-external-provisioner";
            values = {
              image = {
                repository = image.buildArgs.name;
                tag = image.imageTag;
              };
              # Main's go.mod has a client-go without the endpoints lock its provisioner library elects a leader with
              # ("endpoints lock is removed, migrate to leases"). One replica, recreated, needs no leader
              leaderElection.enabled = false;
              nfs = {
                server = cfg.server;
                path = cfg.path;
                defaultMode = ''"${cfg.mountpointOwnership.mode}"'';
                defaultUid = ''"${builtins.toString cfg.mountpointOwnership.uid}"'';
                defaultGid = ''"${builtins.toString cfg.mountpointOwnership.gid}"'';
              };
              storageClass = {
                defaultClass = true;
                reclaimPolicy = "Retain";
                pathPattern = cfg.pathPattern;
              };
            };
          })
          (
            kubelib.toYAMLStreamFile [
              {
                apiVersion = "apps/v1";
                kind = "Deployment";
                metadata.namespace = "nfs-provisioner";
                metadata.name = "nfs-subdir-external-provisioner";
                spec.template.metadata.labels."cluster.local/apiserver-egress" = "allow";
              }
            ]
          );
    };
  };
}
