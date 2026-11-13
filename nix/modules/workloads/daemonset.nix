# A DaemonSet named after the instance, running the pod of `pod-spec.nix` on every node.
{
  config,
  kubenix,
  name,
  ...
}:
let
  labels."app.kubernetes.io/name" = name;
in
{
  imports = [
    kubenix.modules.submodule
    kubenix.modules.k8s
    ./namespace.nix
    ./pod-spec.nix
  ];
  config = {
    submodule.name = "daemonset";
    submodule.passthru.kubernetes.objects = config.kubernetes.objects;
    kubernetes.resources.daemonSets.${name} = {
      metadata = { inherit labels; };
      spec = {
        selector.matchLabels = labels;
        template = config.podTemplate;
      };
    };
  };
}
