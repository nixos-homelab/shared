# A CronJob named after the instance, running the pod of `pod-spec.nix` on `schedule`; the pod is not restarted
# unless the instance sets `restartPolicy`.
{
  config,
  lib,
  name,
  args,
  ...
}:
{
  imports = [ ./controller.nix ];
  options.submodule.args.schedule = lib.mkOption {
    description = "When the job runs, in cron notation.";
    type = lib.types.str;
    example = "10 3 * * *";
  };
  config = {
    submodule.name = "cronjob";
    kubernetes.resources.cronJobs.${name} = {
      metadata = { inherit (config) labels; };
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
