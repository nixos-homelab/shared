{ inputs, self, ... }:
{
  config,
  options,
  lib,
  pkgs,
  ...
}:
let
  ccfg = config.homelab.cluster;
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
    services.k3s.images = images.images;
    homelab.cluster.imageLocks.${toString ./images.lock} = refs;
    k8sss.dnsNames = [ "${config.networking.hostName}.${ccfg.domain}" ];
    kubetree.resources.k8sss = lib.mkIf config.k8sss.enable {
      netpols = {
        apiVersion = "cluster.local";
        kind = "NetpolMacro";
        metadata.name = "k8sss";
        spec.ports = [ config.k8sss.nodePort ];
      };
      netpol-world = {
        apiVersion = "cilium.io/v2";
        kind = "CiliumNetworkPolicy";
        metadata = {
          namespace = "k8sss";
          name = "k8sss";
          labels."app.kubernetes.io/name" = "k8sss";
        };
        spec.endpointSelector.matchLabels."app.kubernetes.io/name" = "k8sss";
        spec.ingress = [
          {
            fromEntities = [ "world" ];
            toPortsFlattened = [ config.k8sss.nodePort ];
          }
        ];
      };
    };
  };
}
