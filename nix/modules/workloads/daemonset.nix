# A DaemonSet named after the instance, running the pod of `pod-spec.nix` on every node.
{ config, name, ... }:
{
  imports = [ ./controller.nix ];
  config = {
    submodule.name = "daemonset";
    kubernetes.resources.daemonSets.${name} = {
      metadata = { inherit (config) labels; };
      spec = {
        selector.matchLabels = config.labels;
        template = config.podTemplate;
      };
    };
  };
}
