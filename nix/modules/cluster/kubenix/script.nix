# A Job running a bash script once, from a ConfigMap, both named after the instance. The script is mounted at a path
# hashed from it, so the pod template of the Job, which k8s keeps immutable, differs when the script does: k3s
# replaces the Job, and it runs again.
{
  config,
  lib,
  kubenix,
  name,
  args,
  ...
}:
let
  labels."app.kubernetes.io/name" = name;
  scriptPath = "/scripts/${builtins.substring 0 8 (builtins.hashString "sha256" args.script)}.sh";
in
{
  imports = [
    kubenix.modules.submodule
    kubenix.modules.k8s
    ./namespace.nix
    ./pod-spec.nix
  ];
  options.submodule.args = {
    script = lib.mkOption {
      description = "The bash script to run.";
      type = lib.types.lines;
    };
    image = lib.mkOption {
      description = "Image the script runs in, preloaded. Defaults to the container-utils of the cluster.";
      type = lib.types.str;
    };
  };
  config = {
    submodule.name = "script";
    submodule.passthru.kubernetes.objects = config.kubernetes.objects;
    submodule.args.container = {
      inherit (args) image;
      imagePullPolicy = "Never";
      command = [ "bash" ];
      args = [ scriptPath ];
      volumeMounts.${scriptPath} = {
        name = "script";
        subPath = "${name}.sh";
        readOnly = true;
      };
    };
    kubernetes.resources = {
      configMaps.${name} = {
        metadata = { inherit labels; };
        data."${name}.sh" = args.script;
      };
      jobs.${name} = {
        metadata = { inherit labels; };
        spec.template = lib.mkMerge [
          config.podTemplate
          {
            spec.restartPolicy = lib.mkDefault "Never";
            spec.volumes.script.configMap.name = name;
          }
        ];
      };
    };
  };
}
