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
          { kubenix, ... }:
          {
            imports = [ kubenix.modules.k8s ];
            kubernetes.version = lib.versions.majorMinor config.services.k3s.package.version;
            # Typed from the pinned CRDs; a module adds the types of the CRDs it installs here
            kubernetes.customTypes = lib.concatMap self.lib.crd2types.customTypes (
              crds.gatewayAPI.crds ++ crds.cilium.crds ++ crds.clusterNetworkPolicy.crds
            );
            kubernetes.customTypesModuleDefinesCRDSpec = false;
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
  config.services.k3s.manifests = lib.mkIf config.homelab.cluster.enable (
    lib.mapAttrs (_: instance: { content = instance.config.kubernetes.objects; }) instances
    // lib.optionalAttrs (own != [ ]) { kubenix.content = own; }
  );
}
