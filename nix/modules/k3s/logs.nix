# How the logs of k3s and its bundled pods are parsed: k3s in the journal (logrus logfmt and klog), CoreDNS,
# metrics-server
{ inputs, ... }:
{
  lib,
  config,
  ...
}:
{
  imports = [ inputs.homelab-monitoring.nixosModules.alloy ];
  config = lib.mkIf config.homelab.k3s.enable {
    homelab.alloy.logs = {
      journal.k3s = {
        format = "go";
        # A Kubernetes event k3s records (an addon applied, ...): what happened is in its `message` field, which the
        # line's msg wins over
        demote.events.expression = "Event occurred";
        # The CronJob controller updating a CronJob's status from a stale copy, as when a Job finishes within seconds of
        # its start: it requeues and the next try lands. The message is klog's HandleError, what happened is in `error`
        demote.cronjob-conflict = {
          expression = "Unhandled Error";
          fields.error = "error syncing CronJobController [^,]+, requeuing: Operation cannot be fulfilled on cronjobs\\.batch \"[^\"]+\": the object has been modified; please apply your changes to the latest version and try again";
        };
        examples = [
          {
            lines = [
              ''time="2026-11-19T19:12:08+01:00" level=info msg="Event occurred" apiVersion=k3s.cattle.io/v1 fieldPath= kind=Addon logger=k3s/deploy message="Applied manifest at \"/mnt/cluster/k3s/server/manifests/vpn-egress.yaml\"" object=kube-system/vpn-egress reason=AppliedManifest type=Normal''
            ];
            expect = [
              {
                message = "Event occurred";
                level = "debug";
              }
            ];
          }
          {
            lines = [
              ''E1125 18:35:05.646668    2326 cronjob_controllerv2.go:179] "Unhandled Error" err="error syncing CronJobController ghostfolio/sync-accounts, requeuing: Operation cannot be fulfilled on cronjobs.batch \"sync-accounts\": the object has been modified; please apply your changes to the latest version and try again" logger="UnhandledError"''
              ''E1125 06:36:12.104512    2326 controller.go:102] "Unhandled Error" err="apiserver received an error that is not an metav1.Status"''
            ];
            expect = [
              {
                message = "Unhandled Error";
                level = "debug";
                fields.error = ''error syncing CronJobController ghostfolio/sync-accounts, requeuing: Operation cannot be fulfilled on cronjobs.batch "sync-accounts": the object has been modified; please apply your changes to the latest version and try again'';
              }
              {
                message = "Unhandled Error";
                level = "error";
                fields.error = "apiserver received an error that is not an metav1.Status";
              }
            ];
          }
          {
            lines = [
              ''time="2026-11-18T08:09:13+01:00" level=fatal msg="Error: exec: \"k3s-server\": executable file not found in $PATH"''
              ''E1118 18:24:39.697234    2873 authentication.go:75] "Unable to authenticate the request" err="x509: certificate has expired or is not yet valid"''
            ];
            expect = [
              {
                message = ''Error: exec: "k3s-server": executable file not found in $PATH'';
                level = "error";
                program = "k3s";
                service_name = "k3s";
              }
              {
                message = "Unable to authenticate the request";
                level = "error";
                fields = {
                  caller = "authentication.go:75";
                  error = "x509: certificate has expired or is not yet valid";
                };
              }
            ];
          }
        ];
      };
      # [INFO] plugin/reload: message, or a query log line
      formats.coredns.stages = ''
        stage.regex {
          expression = "^\\[(?P<level>[A-Z]+)\\] (?:(?P<component>plugin/[\\w-]+): )?(?s)(?P<message>.*)$"
        }
      '';
      pods.coredns = {
        namespace = "kube-system";
        format = "coredns";
        # k3s' Corefile imports custom files nobody has to write, and CoreDNS says so every 15 s
        demote.custom-imports.expression = "No files matching import glob pattern: /etc/coredns/custom/\\*\\.(override|server)";
        examples = [
          {
            lines = [
              "[WARNING] No files matching import glob pattern: /etc/coredns/custom/*.override"
              "[INFO] plugin/reload: Running configuration SHA512 = 591cf328cccc12bc490481273e738df59329c62c0b729d94e8b61db9961c2fa5"
            ];
            expect = [
              {
                message = "No files matching import glob pattern: /etc/coredns/custom/*.override";
                # Demoted
                level = "debug";
              }
              {
                message = "Running configuration SHA512 = 591cf328cccc12bc490481273e738df59329c62c0b729d94e8b61db9961c2fa5";
                level = "info";
                fields.component = "plugin/reload";
              }
            ];
          }
        ];
      };
      pods.metrics-server = {
        namespace = "kube-system";
        format = "klog";
        examples = [
          {
            lines = [ ''I1118 07:22:06.223829       1 shared_informer.go:402] "Waiting for caches to sync"'' ];
            expect = [
              {
                message = "Waiting for caches to sync";
                level = "info";
                fields.caller = "shared_informer.go:402";
              }
            ];
          }
        ];
      };
    };
  };
}
