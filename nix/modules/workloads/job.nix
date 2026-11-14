# A Job named after the instance, running the pod of `pod-spec.nix` once; the pod is not restarted unless the
# instance sets `restartPolicy`.
{
  config,
  lib,
  name,
  ...
}:
{
  imports = [ ./controller.nix ];
  config = {
    submodule.name = "job";
    kubernetes.resources.jobs.${name} = {
      metadata = { inherit (config) labels; };
      spec.template = lib.mkMerge [
        config.podTemplate
        { spec.restartPolicy = lib.mkDefault "Never"; }
      ];
    };
  };
}
