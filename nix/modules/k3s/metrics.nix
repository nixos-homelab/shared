# The metrics of the CoreDNS k3s runs, on the port `metrics` of its Service kube-dns, for Alloy
{ inputs, ... }:
{ config, lib, ... }:
{
  imports = [ inputs.homelab-monitoring.nixosModules.alloy ];
  config = lib.mkIf config.homelab.k3s.enable {
    homelab.alloy.monitors.coredns = {
      namespace = "kube-system";
      selector.k8s-app = "kube-dns";
      podPort = 9153;
    };
  };
}
