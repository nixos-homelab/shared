# cert-manager's alert rules: a certificate close to expiring, which means its renewal is failing (cert-manager
# renews at a third of the lifetime left, 30 days for Let's Encrypt's 90), and a certificate or issuer not ready
{ inputs, ... }:
{ config, lib, ... }:
let
  g = inputs.homelab-monitoring.lib.grafana;
  cfg = config.homelab.cert-manager;
  left = "min by (exported_namespace, name) (certmanager_certificate_expiration_timestamp_seconds - time())";
  expiring =
    days: severity:
    g.alert {
      title = "Certificate expires within ${toString days} days";
      query = left;
      below = days * 86400;
      for = "1h";
      inherit severity;
      summary = "{{ $labels.exported_namespace }}/{{ $labels.name }} expires in {{ humanizeDuration $values.B.Value }}: its renewal is failing";
      description = "kubectl describe certificate -n {{ $labels.exported_namespace }} {{ $labels.name }}, and its CertificateRequest and Order";
      dashboardUid = "services";
    };
in
{
  imports = [ inputs.homelab-monitoring.nixosModules.grafana ];
  options.homelab.cert-manager.alerts.enable = lib.mkOption {
    description = "Whether Grafana alerts on certificates close to expiring and certificates or issuers not ready.";
    type = lib.types.bool;
    default =
      cfg.metrics.enable && config.homelab.alloy.enable && config.homelab.grafana.alerting.enable;
    defaultText = lib.literalExpression ''
      config.homelab.cert-manager.metrics.enable && config.homelab.alloy.enable
      && config.homelab.grafana.alerting.enable
    '';
  };
  config = lib.mkIf cfg.alerts.enable {
    homelab.grafana.alerting.groups.cert-manager.rules = {
      expiring-warning = expiring 14 "warning";
      expiring-critical = expiring 7 "critical";
      certificate-not-ready = g.alert {
        title = "Certificate not ready";
        query = ''min by (exported_namespace, name) (certmanager_certificate_ready_status{condition="True"})'';
        below = 1;
        for = "1h";
        severity = "warning";
        summary = "{{ $labels.exported_namespace }}/{{ $labels.name }} has not been Ready for an hour";
        dashboardUid = "services";
      };
      issuer-not-ready = g.alert {
        title = "Issuer not ready";
        query = ''min by (exported_namespace, name) (label_replace(certmanager_clusterissuer_ready_status{condition="True"}, "exported_namespace", "cluster", "", "") or certmanager_issuer_ready_status{condition="True"})'';
        below = 1;
        for = "15m";
        severity = "warning";
        summary = "Issuer {{ $labels.exported_namespace }}/{{ $labels.name }} is not Ready: certificates from it can't renew";
        dashboardUid = "cluster";
      };
    };
  };
}
