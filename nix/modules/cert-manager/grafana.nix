# cert-manager's rows of the Services and Cluster dashboards: every certificate's days left and ready state, and on
# Cluster the issuers' ready state
{ inputs, ... }:
{ config, lib, ... }:
let
  g = inputs.homelab-monitoring.lib.grafana;
  ready = {
    type = "value";
    options = {
      "0" = {
        text = "Not ready";
        color = "red";
      };
      "1" = {
        text = "Ready";
        color = "green";
      };
    };
  };
  daysLeft = g.bargauge {
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
  };
  certificatesReady = g.stat {
    title = "Ready";
    queries = [
      (g.prom ''certmanager_certificate_ready_status{condition="True"}'' {
        instant = true;
        legend = "{{exported_namespace}}/{{name}}";
      })
    ];
    mappings = [ ready ];
    options = {
      textMode = "value_and_name";
      colorMode = "background";
    };
  };
in
{
  imports = [ inputs.homelab-monitoring.nixosModules.grafana ];
  options.homelab.cert-manager.grafana.enable = lib.mkOption {
    description = "Whether the Services and Cluster dashboards have cert-manager's rows.";
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
            daysLeft
            certificatesReady
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
            daysLeft
            certificatesReady
            (g.stat {
              title = "Issuers";
              queries = [
                (g.prom
                  ''certmanager_clusterissuer_ready_status{condition="True"} or certmanager_issuer_ready_status{condition="True"}''
                  {
                    instant = true;
                    legend = "{{name}}";
                  }
                )
              ];
              mappings = [ ready ];
              options = {
                textMode = "value_and_name";
                colorMode = "background";
              };
            })
          ]
        );
      };
    };
  };
}
