# The DNS row of the Cluster dashboard, from the CoreDNS k3s runs: requests, answers by code, latency, cache
{ inputs, ... }:
{ config, lib, ... }:
let
  g = inputs.homelab-monitoring.lib.grafana;
  dns = ''job="kube-dns"'';
in
{
  imports = [ inputs.homelab-monitoring.nixosModules.grafana ];
  options.homelab.k3s.grafana.enable = lib.mkOption {
    description = "Whether the Cluster dashboard has CoreDNS's row.";
    type = lib.types.bool;
    default =
      config.homelab.k3s.enable
      && config.homelab.k3s.metrics.enable
      && config.homelab.alloy.enable
      && config.homelab.grafana.enable;
    defaultText = lib.literalExpression ''
      config.homelab.k3s.enable && config.homelab.k3s.metrics.enable && config.homelab.alloy.enable
      && config.homelab.grafana.enable
    '';
  };
  config = lib.mkIf config.homelab.k3s.grafana.enable {
    homelab.grafana.overviews.cluster = {
      title = "Cluster";
      rows.dns = {
        order = 400;
        row = g.row { title = "DNS"; } (
          g.autoGrid { columns = 3; } [
            (g.timeseries {
              title = "Answers by code";
              unit = "reqps";
              custom.stacking.mode = "normal";
              queries = [
                (g.prom "sum by (rcode) (rate(coredns_dns_responses_total{${dns}}[$__rate_interval]))" {
                  legend = "{{rcode}}";
                })
              ];
            })
            (g.timeseries {
              title = "Latency";
              unit = "s";
              queries = [
                (g.prom
                  "histogram_quantile(0.5, sum by (le) (rate(coredns_dns_request_duration_seconds_bucket{${dns}}[$__rate_interval])))"
                  {
                    legend = "median";
                  }
                )
                (g.prom
                  "histogram_quantile(0.99, sum by (le) (rate(coredns_dns_request_duration_seconds_bucket{${dns}}[$__rate_interval])))"
                  {
                    legend = "99th percentile";
                  }
                )
              ];
            })
            (g.stat {
              title = "Cache hits";
              unit = "percentunit";
              queries = [
                (g.prom
                  "sum(rate(coredns_cache_hits_total{${dns}}[$__range])) / sum(rate(coredns_cache_requests_total{${dns}}[$__range]))"
                  {
                    instant = true;
                  }
                )
              ];
            })
          ]
        );
      };
    };
  };
}
