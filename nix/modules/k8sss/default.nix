{ inputs, self, ... }:
{
  config,
  options,
  lib,
  pkgs,
  ...
}:
let
  # k8sss' own image refs, preloaded from images.lock
  refs = map (image: image.default) (lib.attrValues options.k8sss.images);
  images = self.lib.images.locked pkgs ./images.lock refs;
in
{
  options.homelab.k8sss = {
    enable = lib.mkEnableOption "k8sss";
  };
  imports = [ inputs.k8sss.nixosModules.default ];
  config = lib.mkIf config.homelab.k8sss.enable {
    k8sss.enable = true;
    k8sss.images = lib.mapAttrs (_: image: lib.mkDefault (images.refFor image.default)) options.k8sss.images;
    homelab.cluster.images = images.images;
    homelab.cluster.imageLocks.${toString ./images.lock} = refs;
    k8sss.dnsNames = [ "${config.networking.hostName}.${config.homelab.workloads.domain}" ];
    # Next to the objects k8sss puts in the manifest k8sss: who may reach step-ca, the pods labeled
    # `cluster.local/k8sss-egress: allow` and, through the NodePort, the world. Policies match the port of the pod
    # (`api`, 9000 in the k8sss module), not the NodePort.
    homelab.kubernetes.submodules.instances.k8sss = lib.mkIf config.k8sss.enable {
      submodule = "manifest";
      config.submodules.instances.k8sss = {
        submodule = "pods";
        args = {
          ports.api = 9000;
          worldPorts = lib.optional (config.k8sss.nodePort != null) "api";
        };
      };
    };
  };
}
