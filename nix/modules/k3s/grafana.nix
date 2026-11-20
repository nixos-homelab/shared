# The Cluster dashboard's DNS panels, from the CoreDNS k3s runs: answers by code, the latency's distribution, cache
# hits, and its errors and slowest answers as tiles. With Loki's views on, k3s' own lines from the journal too
# Its namespace counts toward the `platform` area of the Home dashboard, whose CPU, memory and traffic graphs sum the
# containers by area
{ inputs, ... }:
{ config, lib, ... }:
let
  g = inputs.homelab-monitoring.lib.grafana;
  dns = ''job="kube-dns"'';
  # Below info only with the board's debug switch on
  k3sJournal = ''{source="journal", unit="k3s.service", ${g.hideDebug}}'';
  toJournal = [
    (g.logsDrilldown {
      label = "unit";
      value = "k3s.service";
      filters.source = "journal";
    })
  ];
in
{
  imports = [ inputs.homelab-monitoring.nixosModules.grafana ];
  options.homelab.k3s.grafana.enable = lib.mkOption {
    description = "Whether the Cluster dashboard has CoreDNS's panels, and k3s' journal while `homelab.loki.grafana.enable` is on.";
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
  config = lib.mkMerge [
    {
      homelab.grafana.home.areas.platform = {
        color = "#c4a483";
        namespaces = lib.mkIf config.homelab.k3s.enable [ "kube-system" ];
      };
    }
    (lib.mkIf config.homelab.k3s.grafana.enable {
      homelab.grafana.overviews.cluster = {
        title = "Cluster";
        panels =
          lib.optionalAttrs config.homelab.loki.grafana.enable {
            k3s-levels = {
              order = 910;
              w = 8;
              h = 12;
              panel = g.logVolume {
                title = "k3s by level";
                description = "How many lines k3s wrote to the host's journal, by level: the API server, scheduler, controllers, kubelet and containerd in one process";
                selector = k3sJournal;
                links = toJournal;
              };
            };
            k3s-lines = {
              order = 911;
              w = 16;
              h = 12;
              panel = g.logs {
                title = "k3s lines";
                description = "k3s' lines in the host's journal, newest first";
                links = toJournal;
                queries = [
                  (g.loki k3sJournal {
                    maxLines = 1000;
                    direction = "backward";
                  })
                ];
              };
            };
          }
          // {
            dns-errors = {
              order = 22;
              w = 3;
              h = 4;
              panel = g.stat {
                title = "DNS failures";
                description = "The share of CoreDNS's answers that were SERVFAIL: it couldn't resolve a name upstream or in the cluster. Orange from 1 %, red from 5 %";
                unit = "percentunit";
                levels = g.levels {
                  warn = 0.01;
                  crit = 0.05;
                };
                queries = [
                  (g.prom
                    ''sum(rate(coredns_dns_responses_total{${dns}, rcode="SERVFAIL"}[$__rate_interval]) or vector(0)) / sum(rate(coredns_dns_responses_total{${dns}}[$__rate_interval]))''
                    { }
                  )
                ];
              };
            };
            dns-slowest = {
              order = 23;
              w = 3;
              h = 4;
              panel = g.stat {
                title = "DNS p99";
                description = "How long the slowest 1 % of CoreDNS's answers took; mostly names it had to ask upstream for. Orange from 100 ms, red from 500 ms";
                unit = "s";
                levels = g.levels {
                  warn = 0.1;
                  crit = 0.5;
                };
                queries = [
                  (g.prom
                    "histogram_quantile(0.99, sum by (le) (rate(coredns_dns_request_duration_seconds_bucket{${dns}}[$__rate_interval])))"
                    { }
                  )
                ];
              };
            };
            dns-answers = {
              order = 400;
              w = 8;
              h = 8;
              panel = g.timeseries {
                title = "DNS answers";
                description = "CoreDNS's answers by code, stacked: NOERROR found it, NXDOMAIN there's no such name (pods trying their search domains, mostly harmless), SERVFAIL it failed";
                unit = "reqps";
                custom = {
                  drawStyle = "bars";
                  stacking.mode = "normal";
                  fillOpacity = 70;
                  lineWidth = 0;
                };
                queryOptions.maxDataPoints = 120;
                queries = [
                  (g.prom "sum by (rcode) (rate(coredns_dns_responses_total{${dns}}[$__rate_interval]))" {
                    legend = "{{rcode}}";
                  })
                ];
                overrides =
                  lib.mapAttrsToList
                    (rcode: color: {
                      matcher = {
                        id = "byName";
                        options = rcode;
                      };
                      properties = [
                        {
                          id = "color";
                          value = {
                            mode = "fixed";
                            fixedColor = color;
                          };
                        }
                      ];
                    })
                    {
                      NOERROR = "blue";
                      NXDOMAIN = "#6e7079";
                      SERVFAIL = "red";
                      REFUSED = "orange";
                    };
              };
            };
            dns-latency = {
              order = 401;
              w = 8;
              h = 8;
              panel = g.heatmap {
                title = "DNS latency";
                description = "How long CoreDNS's answers took, as a distribution over time: the darker a cell, the more answers in that band. Answers from its cache sit at the bottom; names asked upstream higher";
                queryOptions.maxDataPoints = 60;
                queries = [
                  (g.prom
                    "sum by (le) (increase(coredns_dns_request_duration_seconds_bucket{${dns}}[$__rate_interval]))"
                    {
                      format = "heatmap";
                      legend = "{{le}}";
                    }
                  )
                ];
                options = {
                  calculate = false;
                  cellGap = 1;
                  color = {
                    mode = "scheme";
                    scheme = "Blues";
                    steps = 64;
                    exponent = 0.5;
                    fill = "dark-blue";
                    reverse = false;
                  };
                  yAxis = {
                    unit = "s";
                    axisPlacement = "left";
                  };
                  rowsFrame.layout = "auto";
                  tooltip = {
                    mode = "single";
                    yHistogram = true;
                    showColorScale = true;
                  };
                  legend.show = false;
                  filterValues.le = 1.0e-9;
                };
              };
            };
            dns-cache = {
              order = 402;
              w = 8;
              h = 8;
              panel = g.timeseries {
                title = "DNS cache";
                description = "The share of CoreDNS's lookups its cache answered, over time; the rest it had to ask the cluster or upstream for";
                unit = "percentunit";
                min = 0;
                max = 1;
                queries = [
                  (g.prom
                    "sum(rate(coredns_cache_hits_total{${dns}}[$__rate_interval])) / sum(rate(coredns_cache_requests_total{${dns}}[$__rate_interval]))"
                    {
                      legend = "cache hits";
                    }
                  )
                ];
              };
            };
          };
      };
    })
  ];
}
