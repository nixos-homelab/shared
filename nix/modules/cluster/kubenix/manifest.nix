# One k3s manifest of objects that belong together: the resources set on the instance `config` and those of the
# instances nested in it, which inherit the namespace of the manifest. Objects stay in the manifest they were in, since k3s deletes
# what a manifest no longer holds.
{
  config,
  kubenix,
  ...
}:
{
  imports = [
    kubenix.modules.submodule
    kubenix.modules.k8s
    kubenix.modules.submodules
    ./namespace.nix
  ];
  config = {
    submodule.name = "manifest";
    submodule.passthru.kubernetes.objects = config.kubernetes.objects;
  };
}
