# The release's metrics, http-metrics:9402 on the controller, cainjector and webhook, for Alloy. The chart's Services
# name the port `http-metrics` for the controller and cainjector, `metrics` for the webhook: two monitors
{ inputs, ... }:
{ config, lib, ... }:
{
  imports = [ inputs.homelab-monitoring.nixosModules.alloy ];
  options.homelab.cert-manager.metrics.enable = lib.mkOption {
    description = "Whether Alloy scrapes cert-manager's metrics.";
    type = lib.types.bool;
    default = config.homelab.alloy.enable;
    defaultText = lib.literalExpression "config.homelab.alloy.enable";
  };
  config = lib.mkIf config.homelab.cert-manager.metrics.enable {
    homelab.alloy.monitors = {
      # The controller and cainjector. The webhook's Service matches too, but has no port `http-metrics`
      cert-manager = {
        selector."app.kubernetes.io/instance" = "cert-manager";
        port = "http-metrics";
        podPort = 9402;
      };
      cert-manager-webhook = {
        namespace = "cert-manager";
        selector = {
          "app.kubernetes.io/instance" = "cert-manager";
          "app.kubernetes.io/name" = "webhook";
        };
        podPort = 9402;
      };
    };
  };
}
