# The policy intent of pods that something else runs (a release, a static manifest, another module), selected by
# their labels. It writes no objects; the module of the CNI turns the intent into policies, as for the pods of the
# other submodules.
{
  config,
  lib,
  kubenix,
  name,
  args,
  ...
}:
{
  imports = [
    kubenix.modules.submodule
    kubenix.modules.k8s
    ./namespace.nix
    ./policy.nix
  ];
  options.submodule.args.selector = lib.mkOption {
    description = "Labels of the pods, in the namespace of the instance";
    type = lib.types.attrsOf lib.types.str;
    default."app.kubernetes.io/name" = name;
    defaultText = lib.literalExpression ''{ "app.kubernetes.io/name" = name; }'';
  };
  config = {
    submodule.name = "pods";
    submodule.passthru.kubernetes.objects = config.kubernetes.objects;
    policySelector = args.selector;
  };
}
