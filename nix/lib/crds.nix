{
  self,
  inputs,
  lib,
}:
{
  /**
    The CRDs pinned in `.github/workflows/pins.yaml` that no manifest of
    ours carries: Gateway API's experimental channel, which a CNI module
    installs (networking's cilium does) and the `workload` submodule writes
    resources of. Each is the `src`, `key` and `unlocked` of
    `lib.pins.locked`, and `crds`, the CustomResourceDefinitions read at
    evaluation.

    # Arguments

    `pkgs`: nixpkgs
  */
  pinned =
    pkgs:
    let
      pins = self.lib.pins.refs ../../.github/workflows/pins.yaml;
      pinned = self.lib.pins.locked ../../.github/pins.lock;
      kubelib = inputs.kube-generators.lib { inherit pkgs; };
      read =
        pin: files:
        pin
        // {
          crds = lib.filter (d: d.kind or null == "CustomResourceDefinition") (
            kubelib.fromYAML (lib.concatMapStringsSep "\n---\n" builtins.readFile files)
          );
        };
      gatewayAPI = pinned "gateway-api-experimental-install" pins."kubernetes-sigs/gateway-api" (
        hash:
        pkgs.fetchurl {
          url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/${
            pins."kubernetes-sigs/gateway-api"
          }/experimental-install.yaml";
          inherit hash;
        }
      );
    in
    {
      gatewayAPI = read gatewayAPI [ gatewayAPI.src ];
    };
}
