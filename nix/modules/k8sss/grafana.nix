# step-ca's rows of the Workload dashboard, shown for its namespace
# Its namespace counts toward the `platform` area of the Home dashboard, whose CPU, memory and traffic graphs sum the
# containers by area
{ inputs, ... }:
{ config, lib, ... }:
let
  g = inputs.homelab-monitoring.lib.grafana;
  cfg = config.homelab.k8sss;
  j = ''namespace="k8sss"'';
in
{
  imports = [ inputs.homelab-monitoring.nixosModules.grafana ];
  options.homelab.k8sss.grafana.enable = lib.mkOption {
    description = "Whether the Workload dashboard has step-ca's rows.";
    type = lib.types.bool;
    default =
      cfg.enable && cfg.metrics.enable && config.homelab.alloy.enable && config.homelab.grafana.enable;
    defaultText = lib.literalExpression ''
      config.homelab.k8sss.enable && config.homelab.k8sss.metrics.enable && config.homelab.alloy.enable
      && config.homelab.grafana.enable
    '';
  };
  config = lib.mkMerge [
    {
      homelab.grafana.home.areas.platform = {
        color = "#c4a483";
        namespaces = lib.mkIf config.homelab.k8sss.enable [ "k8sss" ];
      };
    }
    (lib.mkIf cfg.grafana.enable {
      homelab.grafana.drilldown.rows.k8sss = {
        workload = "k8sss";
        row = g.row { title = "step-ca"; } (
          g.autoGrid { columns = 3; } [
            (g.stat {
              title = "Up for";
              unit = "s";
              queries = [ (g.prom "step_ca_uptime_seconds{${j}}" { instant = true; }) ];
            })
            (g.stat {
              title = "Certificates signed";
              description = "Since step-ca started, by outcome";
              decimals = 0;
              queries = [
                (g.prom "sum by (success) (step_ca_x509_signed_total{${j}})" {
                  instant = true;
                  legend = "success={{success}}";
                })
              ];
            })
            (g.timeseries {
              title = "Signed over time";
              decimals = 0;
              queries = [
                (g.prom "sum by (success) (increase(step_ca_x509_signed_total{${j}}[$__rate_interval]))" {
                  legend = "success={{success}}";
                })
                (g.prom "sum(increase(step_ca_kms_signed{${j}}[$__rate_interval]))" { legend = "KMS signatures"; })
                (g.prom "sum(increase(step_ca_kms_errors{${j}}[$__rate_interval]))" { legend = "KMS errors"; })
              ];
            })
          ]
        );
      };
    })
  ];
}
