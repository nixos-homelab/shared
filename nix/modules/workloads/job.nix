# A Job named after the instance, running the pod of `pod-spec.nix` once; the pod is not restarted unless the
# instance sets `restartPolicy`.
{
  config,
  lib,
  kubenix,
  name,
  ...
}:
{
  imports = [
    kubenix.modules.submodule
    kubenix.modules.k8s
    ./namespace.nix
    ./pod-spec.nix
  ];
  config = {
    submodule.name = "job";
    submodule.passthru.kubernetes.objects = config.kubernetes.objects;
    kubernetes.resources.jobs.${name} = {
      metadata.labels."app.kubernetes.io/name" = name;
      spec.template = lib.mkMerge [
        config.podTemplate
        { spec.restartPolicy = lib.mkDefault "Never"; }
      ];
    };
  };
}
