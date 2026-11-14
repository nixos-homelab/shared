# The frame of the submodules that run the pod of `pod-spec.nix` in one controller named after the instance:
# `deployment`, `daemonset`, `job` and `cronjob`. Each of them sets `submodule.name` and puts its resource under
# `kubernetes.resources`, labeled with `labels`. They stay files of their own: a submodule written inline in
# `submodules.imports` recurses on its `kubenix` argument.
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
  options.labels = lib.mkOption {
    description = "The name label of the controller, for its metadata and selector.";
    type = lib.types.attrsOf lib.types.str;
    readOnly = true;
    internal = true;
  };
  config = {
    labels."app.kubernetes.io/name" = name;
    submodule.passthru.kubernetes.objects = config.kubernetes.objects;
  };
}
