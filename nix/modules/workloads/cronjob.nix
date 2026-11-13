# A CronJob named after the instance, running the pod of `pod-spec.nix` on `schedule`; the pod is not restarted
# unless the instance sets `restartPolicy`.
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
    ./pod-spec.nix
  ];
  options.submodule.args.schedule = lib.mkOption {
    description = "When the job runs, in cron notation.";
    type = lib.types.str;
    example = "10 3 * * *";
  };
  config = {
    submodule.name = "cronjob";
    submodule.passthru.kubernetes.objects = config.kubernetes.objects;
    kubernetes.resources.cronJobs.${name} = {
      metadata.labels."app.kubernetes.io/name" = name;
      spec = {
        inherit (args) schedule;
        jobTemplate.spec.template = lib.mkMerge [
          config.podTemplate
          { spec.restartPolicy = lib.mkDefault "Never"; }
        ];
      };
    };
  };
}
