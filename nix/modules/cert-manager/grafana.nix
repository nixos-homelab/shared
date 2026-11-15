# cert-manager's row of the Cluster dashboard: certificates by days left, those not ready, issuers not ready
{ inputs, ... }:
{ config, lib, ... }:
let
  g = inputs.homelab-monitoring.lib.grafana;
in
{
  imports = [ inputs.homelab-monitoring.nixosModules.grafana ];
  options.homelab.cert-manager.grafana.enable = lib.mkOption {
    description = "Whether the Cluster dashboard has cert-manager's row.";
    type = lib.types.bool;
    default =
      config.homelab.cert-manager.metrics.enable
      && config.homelab.alloy.enable
      && config.homelab.grafana.enable;
    defaultText = lib.literalExpression ''
      config.homelab.cert-manager.metrics.enable && config.homelab.alloy.enable && config.homelab.grafana.enable
    '';
  };
  config = lib.mkIf config.homelab.cert-manager.grafana.enable {
    homelab.grafana.overviews.services = {
      title = "Services";
      rows.certificates = {
        order = 300;
        row = g.row { title = "Certificates"; } (
          g.autoGrid { columns = 2; } [
            (g.bargauge {
              title = "Expiring within 30 days";
              description = "cert-manager renews at two thirds of a certificate's life, so one here is overdue or about to be renewed";
              unit = "d";
              queries = [
                (g.prom "sort((certmanager_certificate_expiration_timestamp_seconds - time()) / 86400 < 30)" {
                  instant = true;
                  legend = "{{exported_namespace}}/{{name}}";
                })
              ];
              thresholds = [
                {
                  value = null;
                  color = "red";
                }
                {
                  value = 7;
                  color = "orange";
                }
                {
                  value = 21;
                  color = "green";
                }
              ];
              noValue = "None";
            })
            (g.table {
              title = "Not ready";
              queries = [
                (g.prom ''certmanager_certificate_ready_status{condition="True"} == 0'' { instant = true; })
              ];
              noValue = "None";
            })
          ]
        );
      };
    };
    homelab.grafana.overviews.cluster = {
      title = "Cluster";
      rows.certificates = {
        order = 300;
        row = g.row { title = "Certificates"; } (
          g.autoGrid { columns = 3; } [
            (g.bargauge {
              title = "Days left";
              description = "Each certificate's time to expiry; cert-manager renews at two thirds of its life";
              unit = "d";
              queries = [
                (g.prom "sort((certmanager_certificate_expiration_timestamp_seconds - time()) / 86400)" {
                  instant = true;
                  legend = "{{exported_namespace}}/{{name}}";
                })
              ];
              thresholds = [
                {
                  value = null;
                  color = "red";
                }
                {
                  value = 7;
                  color = "orange";
                }
                {
                  value = 21;
                  color = "green";
                }
              ];
            })
            (g.table {
              title = "Not ready";
              queries = [
                (g.prom ''certmanager_certificate_ready_status{condition="True"} == 0'' { instant = true; })
              ];
              noValue = "None";
            })
            (g.table {
              title = "Issuers not ready";
              queries = [
                (g.prom
                  ''certmanager_clusterissuer_ready_status{condition="True"} == 0 or certmanager_issuer_ready_status{condition="True"} == 0''
                  {
                    instant = true;
                  }
                )
              ];
              noValue = "None";
            })
          ]
        );
      };
    };
  };
}
