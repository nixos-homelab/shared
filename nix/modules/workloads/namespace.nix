# The namespace of a submodule instance: that of the parent, so the instances nested in a `manifest` share the
# namespace of the manifest, or the instance name at the top, where the cluster has none. kubenix hands the namespace
# of the parent down at `mkDefault`; this beats that, and a plain definition on the instance `config` beats this.
{
  lib,
  name,
  parentConfig,
  ...
}:
{
  kubernetes.namespace = lib.mkOverride 900 (
    if parentConfig.kubernetes.namespace or null != null then parentConfig.kubernetes.namespace else name
  );
}
