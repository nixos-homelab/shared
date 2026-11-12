{ self, inputs }:
{
  lib,
  pkgs,
  config,
  ...
}:
let
  # kubenix on this nixpkgs, through its overlay
  inherit (inputs.kubenix.overlays.default pkgs pkgs) kubenix;
  crds = self.lib.crds.pinned pkgs;
  evaluated =
    (kubenix.evalModules {
      modules = [
        (
          { kubenix, ... }@cluster:
          {
            imports = [
              kubenix.modules.k8s
              kubenix.modules.submodules
            ];
            kubernetes.version = lib.versions.majorMinor config.services.k3s.package.version;
            # Typed from the pinned CRDs; a module adds the types of the CRDs it installs here
            kubernetes.customTypes = lib.concatMap self.lib.crd2types.customTypes (
              crds.gatewayAPI.crds ++ crds.cilium.crds ++ crds.clusterNetworkPolicy.crds
            );
            kubernetes.customTypesModuleDefinesCRDSpec = false;
            submodules.imports = [
              ./cronjob.nix
              ./daemonset.nix
              ./deployment.nix
              ./job.nix
              ./manifest.nix
              ./script.nix
              ./service.nix
              ./workload.nix
            ];
            # The cluster-wide settings still come from kubetree.workload-macros until the hosts set them in kubenix
            submodules.defaults =
              let
                wm = config.kubetree.workload-macros;
              in
              [
                # The cluster's custom types reach every submodule
                {
                  features = [ "k8s" ];
                  default.kubernetes = {
                    inherit (cluster.config.kubernetes) customTypes;
                    customTypesModuleDefinesCRDSpec = false;
                  };
                }
                {
                  features = [ "pod-spec" ];
                  default.submodule.args.securityContext = lib.mapAttrs (_: lib.mkDefault) wm.securityContext;
                }
                {
                  name = "workload";
                  default.submodule.args.gateway = {
                    domain = lib.mkDefault wm.domain;
                    className = lib.mkDefault wm.gatewayClassName;
                    issuer = lib.mkDefault wm.acmeProvider;
                  };
                }
                {
                  name = "script";
                  default.submodule.args.image = lib.mkDefault wm.containerUtils;
                }
              ];
          }
        )
        config.homelab.kubernetes
      ];
    }).config;
  instances = evaluated.submodules.instances;
  id =
    object:
    "${object.apiVersion}/${object.kind}/${object.metadata.namespace or ""}/${object.metadata.name}";
  # Instances pass their objects on to the cluster's own; those go in the instance's manifest only
  ofInstances = lib.concatMap (instance: map id instance.config.kubernetes.objects) (
    lib.attrValues instances
  );
  own = lib.filter (object: !lib.elem (id object) ofInstances) evaluated.kubernetes.objects;
in
{
  # https://github.com/hercules-ci/flake-parts/pull/251
  key = "${toString __curPos.file}#modules.nixos.cluster-kubenix";
  options.homelab.kubernetes = lib.mkOption {
    description = "kubenix configuration of the cluster. Each submodule instance goes to k3s as a manifest of its own, the other objects as the manifest kubenix.";
    type = lib.types.deferredModule;
    default = { };
  };
  config.services.k3s.manifests = lib.mkIf config.homelab.cluster.enable (
    lib.mapAttrs (_: instance: { content = instance.config.kubernetes.objects; }) instances
    // lib.optionalAttrs (own != [ ]) { kubenix.content = own; }
  );
}
