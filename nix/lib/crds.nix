{
  self,
  inputs,
  lib,
}:
{
  /**
    The CRDs pinned in `.github/workflows/pins.yaml` that no manifest of
    ours carries: Gateway API's experimental channel, which a CNI module
    installs (networking's cilium does), Cilium's, which its operator
    creates at runtime, and ClusterNetworkPolicy, which the manifests check
    emits. Each is the `src`, `key` and `unlocked` of `lib.pins.locked`,
    and `crds`, the CustomResourceDefinitions read at evaluation.

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
      ciliumDir = "pkg/k8s/apis/cilium.io/client/crds/v2";
      cilium = pinned "cilium-crds" pins."cilium/cilium" (
        hash:
        pkgs.fetchFromGitHub {
          owner = "cilium";
          repo = "cilium";
          rev = pins."cilium/cilium";
          sparseCheckout = [ ciliumDir ];
          inherit hash;
        }
      );
      clusterNetworkPolicy = pinned "clusternetworkpolicy-crd" pins."kubernetes-sigs/network-policy-api" (
        hash:
        pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/kubernetes-sigs/network-policy-api/${
            pins."kubernetes-sigs/network-policy-api"
          }/config/crd/standard/policy.networking.k8s.io_clusternetworkpolicies.yaml";
          inherit hash;
        }
      );
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
      cilium = read cilium (
        lib.filter (lib.hasSuffix ".yaml") (lib.filesystem.listFilesRecursive "${cilium.src}/${ciliumDir}")
      );
      clusterNetworkPolicy = read clusterNetworkPolicy [ clusterNetworkPolicy.src ];
      gatewayAPI = read gatewayAPI [ gatewayAPI.src ];
    };
}
