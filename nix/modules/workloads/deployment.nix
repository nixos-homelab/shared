# A Deployment named after the instance, running the pod of `pod-spec.nix`. It is recreated on change, never two
# pods at once, as the workloads keep their data on volumes one pod may hold.
{ config, name, ... }:
{
  imports = [ ./controller.nix ];
  config = {
    submodule.name = "deployment";
    kubernetes.resources.deployments.${name} = {
      metadata = { inherit (config) labels; };
      spec = {
        strategy.type = "Recreate";
        selector.matchLabels = config.labels;
        template = config.podTemplate;
      };
    };
  };
}
