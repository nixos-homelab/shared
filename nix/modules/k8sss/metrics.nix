# step-ca's metrics, plain HTTP at /metrics on the port `metrics` of the Service k8sss, for Alloy. step-ca serves them
# only while Alloy is on
{ inputs, ... }:
{ config, lib, ... }:
{
  imports = [ inputs.homelab-monitoring.nixosModules.alloy ];
  config = lib.mkIf config.homelab.k8sss.enable {
    k8sss.metricsPort = lib.mkIf config.homelab.alloy.enable 9001;
    homelab.alloy.monitors.k8sss.podPort = 9001;
  };
}
