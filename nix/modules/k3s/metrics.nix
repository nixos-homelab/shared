# The metrics of the CoreDNS k3s runs, on the port `metrics` of its Service kube-dns, for Alloy
{ inputs, ... }:
{ config, lib, ... }:
let
  cfg = config.homelab.k3s;
in
{
  imports = [ inputs.homelab-monitoring.nixosModules.alloy ];
  options.homelab.k3s.metrics.enable = lib.mkOption {
    description = "Whether Alloy scrapes the metrics of the CoreDNS k3s runs.";
    type = lib.types.bool;
    default = config.homelab.alloy.enable;
    defaultText = lib.literalExpression "config.homelab.alloy.enable";
  };
  config = lib.mkIf (cfg.enable && cfg.metrics.enable) {
    homelab.alloy.monitors.coredns = {
      namespace = "kube-system";
      selector.k8s-app = "kube-dns";
      podPort = 9153;
      # k3s writes CoreDNS itself: no instance to put the policy in
      manifest = null;
    };
  };
}
