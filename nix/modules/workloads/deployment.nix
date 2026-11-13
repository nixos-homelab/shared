# A Deployment named after the instance, running the pod of `pod-spec.nix`. It is recreated on change, never two
# pods at once, as the workloads keep their data on volumes one pod may hold.
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
    submodule.name = "deployment";
    submodule.passthru.kubernetes.objects = config.kubernetes.objects;
    kubernetes.resources.deployments.${name} = {
      metadata = { inherit labels; };
      spec = {
        strategy.type = "Recreate";
        selector.matchLabels = labels;
        template = config.podTemplate;
      };
    };
  };
}
