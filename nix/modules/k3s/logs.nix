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
        examples = [
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
        examples = [
          {
            lines = [
              "[WARNING] No files matching import glob pattern: /etc/coredns/custom/*.override"
              "[INFO] plugin/reload: Running configuration SHA512 = 591cf328cccc12bc490481273e738df59329c62c0b729d94e8b61db9961c2fa5"
            ];
            expect = [
              {
                message = "No files matching import glob pattern: /etc/coredns/custom/*.override";
                level = "warning";
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
