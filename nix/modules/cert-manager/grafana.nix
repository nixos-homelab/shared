# cert-manager's panels: every certificate on the Services dashboard (its issuer, whether it's ready, how much of its
# life it has left, when it expires and renews), the issuers and certificates as tiles on Cluster and Home, and each
# renewal marked on the graphs. A certificate's life left is the share of its own lifetime, so a 90-day ACME
# certificate and a ten-year internal one read alike: cert-manager renews at a third
{ inputs, ... }:
{ config, lib, ... }:
let
  g = inputs.homelab-monitoring.lib.grafana;
  ready = [
    {
      type = "value";
      options = {
        "0" = {
          text = "not ready";
          color = "red";
        };
        "1" = {
          text = "ready";
          color = "green";
        };
      };
    }
  ];
  lifeLeft = "(certmanager_certificate_not_after_timestamp_seconds - time()) / (certmanager_certificate_not_after_timestamp_seconds - certmanager_certificate_not_before_timestamp_seconds)";
  # cert-manager renews at a third of the life left by default: under a quarter its renewal is late, under a tenth
  # the certificate is close to expiring
  life = g.levels {
    warn = 0.25;
    crit = 0.1;
    below = true;
  };
  certificatesReady = {
    good = ''sum(certmanager_certificate_ready_status{condition="True"})'';
    all = ''count(certmanager_certificate_ready_status{condition="True"})'';
    crit = 0.99;
  };
  lowestLife = {
    title = "Lowest life left";
    description = "The certificate with the least of its lifetime left: cert-manager renews at a third, so under a quarter (orange) its renewal is late, under a tenth (red) it's close to expiring. The table on Services has each";
    unit = "percentunit";
    levels = life;
    queries = [ (g.prom "min(${lifeLeft})" { }) ];
  };
  toServices = [
    {
      title = "Services";
      url = "/d/services/services?\${__url_time_range}";
    }
  ];
  renewals = g.annotation {
    name = "Certificate renewals";
    expr = "changes(certmanager_certificate_not_before_timestamp_seconds[5m]) > 0";
    color = "green";
    title = "{{exported_namespace}}/{{name}} renewed";
    text = "cert-manager issued a new certificate ({{issuer_name}})";
  };
  panel = order: w: h: panel: {
    inherit
      order
      w
      h
      panel
      ;
  };
in
{
  imports = [ inputs.homelab-monitoring.nixosModules.grafana ];
  options.homelab.cert-manager.grafana.enable = lib.mkOption {
    description = "Whether the Services and Cluster dashboards have cert-manager's panels.";
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
    homelab.grafana.home.tiles = {
      certificates = {
        group = "Certificates";
        order = 300;
        panel = g.ratio (
          {
            title = "Certificates ready";
            description = "Certificates cert-manager has ready, of all of them";
            links = toServices;
          }
          // certificatesReady
        );
      };
      certificate-life = {
        group = "Certificates";
        order = 301;
        panel = g.stat (lowestLife // { links = toServices; });
      };
    };
    homelab.grafana.overviews.services = {
      title = "Services";
      annotations.renewals = renewals;
      panels = {
        certificates-ready = panel 12 6 4 (
          g.ratio (
            {
              title = "Certificates ready";
              description = "Certificates cert-manager has ready, of all of them; any not ready is red";
            }
            // certificatesReady
          )
        );
        certificate-life = panel 13 6 4 (g.stat lowestLife);
        certificates = panel 300 24 17 (
          g.table {
            title = "Certificates";
            description = "Every certificate cert-manager manages, the one with the least life left first: its issuer, whether it's ready, the share of its lifetime left (orange under a quarter, when renewal is late; red under a tenth), when it expires, and when cert-manager renews it (a renewal in the past is overdue)";
            queries = [
              (g.prom
                ''max by (exported_namespace, name, issuer_name) (certmanager_certificate_ready_status{condition="True"})''
                {
                  instant = true;
                }
              )
              (g.prom "max by (exported_namespace, name) (${lifeLeft})" { instant = true; })
              (g.prom
                "max by (exported_namespace, name) (certmanager_certificate_expiration_timestamp_seconds) * 1000"
                {
                  instant = true;
                }
              )
              (g.prom
                "max by (exported_namespace, name) (certmanager_certificate_renewal_timestamp_seconds) * 1000"
                {
                  instant = true;
                }
              )
            ];
            transformations = [
              { id = "merge"; }
              {
                id = "organize";
                options = {
                  excludeByName.Time = true;
                  renameByName = {
                    exported_namespace = "namespace";
                    name = "certificate";
                    issuer_name = "issuer";
                    "Value #A" = "ready";
                    "Value #B" = "life left";
                    "Value #C" = "expires";
                    "Value #D" = "renews";
                  };
                  indexByName = {
                    exported_namespace = 0;
                    name = 1;
                    issuer_name = 2;
                    "Value #A" = 3;
                    "Value #B" = 4;
                    "Value #C" = 5;
                    "Value #D" = 6;
                  };
                };
              }
            ];
            overrides = [
              (g.column "ready" {
                mappings = ready;
                display = "color-text";
                width = 100;
              })
              (g.column "life left" {
                unit = "percentunit";
                levels = life;
                display = "gauge";
                description = "The share of the certificate's own lifetime left";
              })
              (g.column "expires" {
                unit = "dateTimeFromNow";
                width = 140;
              })
              (g.column "renews" {
                unit = "dateTimeFromNow";
                width = 140;
                description = "When cert-manager renews it; in the past, the renewal is overdue";
              })
            ];
            options.sortBy = [
              {
                displayName = "life left";
                desc = false;
              }
            ];
          }
        );
      };
    };
    homelab.grafana.overviews.cluster = {
      title = "Cluster";
      annotations.renewals = renewals;
      panels = {
        issuers = panel 20 3 4 (
          g.ratio {
            title = "Issuers";
            description = "cert-manager's Issuers and ClusterIssuers that are ready (an ACME account registered, a CA's key in place), of all of them";
            good = ''sum(certmanager_clusterissuer_ready_status{condition="True"}) + (sum(certmanager_issuer_ready_status{condition="True"}) or vector(0))'';
            all = ''count(certmanager_clusterissuer_ready_status{condition="True"}) + (count(certmanager_issuer_ready_status{condition="True"}) or vector(0))'';
            crit = 0.99;
          }
        );
        certificates = panel 21 3 4 (
          g.ratio (
            {
              title = "Certificates";
              description = "Certificates cert-manager has ready, of all of them; Services lists each";
            }
            // certificatesReady
          )
        );
      };
    };
  };
}
