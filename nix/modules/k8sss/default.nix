{ inputs, self, ... }:
{
  config,
  options,
  lib,
  pkgs,
  ...
}:
let
  # k8sss' own image refs, preloaded from the lock k8sss ships with them: kept here, it went stale whenever a consumer's
  # k8sss input (which follows its own) moved a default
  refs = map (image: image.default) (lib.attrValues options.k8sss.images);
  images = self.lib.images.locked pkgs (inputs.k8sss.lib.imageLock
    or (throw "This k8sss predates its lib.imageLock, update the k8sss input")
  ) refs;
in
{
  options.homelab.k8sss = {
    enable = lib.mkEnableOption "k8sss";
  };
  imports = [
    inputs.k8sss.nixosModules.default
  ]
  ++ self.lib.importsApply [
    ./grafana.nix
    ./logs.nix
    ./metrics.nix
  ];
  config = lib.mkIf config.homelab.k8sss.enable {
    k8sss.enable = true;
    k8sss.images = lib.mapAttrs (
      _: image: lib.mkDefault (images.refFor image.default)
    ) options.k8sss.images;
    homelab.cluster.images = images.images;
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
