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
    services.k3s.images = images.images;
    homelab.cluster.imageLocks.${toString ./images.lock} = refs;
    k8sss.dnsNames = [ "${config.networking.hostName}.${config.homelab.workloads.domain}" ];
    # Next to the objects k8sss puts in the manifest k8sss: who may reach the NodePort of k8sss, the pods labeled
    # `cluster.local/k8sss-egress: allow` and the world
    homelab.kubernetes.submodules.instances.k8sss = lib.mkIf config.k8sss.enable {
      submodule = "manifest";
      config.kubernetes.resources =
        let
          labels."app.kubernetes.io/name" = "k8sss";
          egressLabel = "cluster.local/k8sss-egress";
          toPorts = [ { ports = [ { port = toString config.k8sss.nodePort; } ]; } ];
        in
        {
          ciliumClusterwideNetworkPolicies.pod-to-k8sss = {
            metadata = {
              inherit labels;
              namespace = null;
            };
            spec = {
              endpointSelector.matchLabels.${egressLabel} = "allow";
              egress = [
                {
                  toEndpoints = [ { matchLabels = labels // { "k8s:io.kubernetes.pod.namespace" = "k8sss"; }; } ];
                  inherit toPorts;
                }
              ];
            };
          };
          ciliumNetworkPolicies = {
            k8sss-from-pod = {
              metadata = { inherit labels; };
              spec = {
                endpointSelector.matchLabels = labels;
                ingress = [
                  {
                    fromEndpoints = [
                      {
                        matchExpressions = [
                          {
                            key = "k8s:io.kubernetes.pod.namespace";
                            operator = "Exists";
                          }
                          {
                            key = egressLabel;
                            operator = "In";
                            values = [ "allow" ];
                          }
                        ];
                      }
                    ];
                    inherit toPorts;
                  }
                ];
              };
            };
            k8sss = {
              metadata = { inherit labels; };
              spec = {
                endpointSelector.matchLabels = labels;
                ingress = [
                  {
                    fromEntities = [ "world" ];
                    inherit toPorts;
                  }
                ];
              };
            };
          };
        };
    };
  };
}
