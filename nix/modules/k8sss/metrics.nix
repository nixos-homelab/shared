# step-ca's metrics, plain HTTP at /metrics on the port `metrics` of the Service k8sss, for Alloy. step-ca serves them
# only while Alloy is on
{ inputs, ... }:
{ config, lib, ... }:
let
  cfg = config.homelab.k8sss;
in
{
  imports = [ inputs.homelab-monitoring.nixosModules.alloy ];
  options.homelab.k8sss.metrics.enable = lib.mkOption {
    description = "Whether Alloy scrapes step-ca's metrics, and step-ca serves them.";
    type = lib.types.bool;
    default = config.homelab.alloy.enable;
    defaultText = lib.literalExpression "config.homelab.alloy.enable";
  };
  config = lib.mkIf (cfg.enable && cfg.metrics.enable) {
    k8sss.metricsPort = lib.mkIf config.homelab.alloy.enable 9001;
    homelab.alloy.monitors.k8sss = {
      podPort = 9001;
      # k8sss writes its objects straight to services.k3s.manifests: no instance to put the policy in
      manifest = null;
    };
  };
}
