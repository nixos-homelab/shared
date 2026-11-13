{ inputs, ... }:
{
  lib,
  config,
  ...
}:
let
  cfg = config.kubetree.workload-macros;
  transform = inputs.kubetree.lib.transform;
  sm = import ./lib.nix {
    inherit lib transform;
    workloads = config.homelab.workloads;
  };
in
{
  key = "${toString __curPos.file}#modules.nixos.workload-macros";
  options.kubetree.workload-macros = {
    enable = lib.mkEnableOption "service macro transformers";
  };
  config = {
    kubetree.transformers = lib.mkIf cfg.enable {
      v1.Pod._transformers = [ sm.transformPodSpecMacro ];
      "cluster.local" = {
        WorkloadMacro._transformers = [
          sm.transformWorkloadMacro
          transform.transformResource
          transform.flattenResourceList
        ];
        DeploymentMacro._transformers = [
          sm.transformDeploymentMacro
          transform.transformResource
        ];
        DaemonSetMacro._transformers = [
          sm.transformDaemonSetMacro
          transform.transformResource
        ];
        CronJobMacro._transformers = [
          sm.transformCronJobMacro
          transform.transformResource
        ];
        JobMacro._transformers = [
          sm.transformJobMacro
          transform.transformResource
        ];
        ServiceMacro._transformers = [
          sm.transformServiceMacro
          transform.transformResource
        ];
        GatewayMacro._transformers = [
          sm.transformGatewayMacro
          transform.transformResource
          transform.flattenResourceList
        ];
        ScriptMacro._transformers = [
          sm.transformScriptMacro
          transform.transformResource
        ];
      };
    };
  };
}
