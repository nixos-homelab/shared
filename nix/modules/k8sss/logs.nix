# How step-ca's logs are parsed: logrus logfmt; its access log has no msg, so the request is the message
{ inputs, ... }:
{
  lib,
  config,
  ...
}:
{
  imports = [ inputs.homelab-monitoring.nixosModules.alloy ];
  config = lib.mkIf config.homelab.k8sss.enable {
    homelab.alloy.logs = {
      formats.step-ca = {
        inherit (config.homelab.alloy.logs.formats.logfmt) firstline fields;
        stages = config.homelab.alloy.logs.formats.logfmt.stages + ''
          stage.template {
            source   = "message"
            template = "{{ with index . \"f.msg\" }}{{ . }}{{ else }}{{ with index . \"f.method\" }}{{ . }} {{ index $ \"f.path\" }} {{ index $ \"f.status\" }}{{ end }}{{ end }}"
          }
        '';
      };
      pods.step-ca = {
        namespace = "k8sss";
        format = "step-ca";
        # The kubelet's probes, every few seconds
        demote.health.expression = "GET /health 200";
        examples = [
          {
            lines = [
              ''time="2026-11-18T17:03:27Z" level=info duration="11.742µs" duration-ns=11742 fields.time="2026-11-18T17:03:27Z" method=GET name=ca path=/health protocol=HTTP/2.0 referer= remote-address=10.42.80.71 request-id=3e230509-de6c-4757-abd0-8c535e1c7563 size=16 status=200 user-agent=kube-probe/1.35 user-id=''
            ];
            expect = [
              {
                message = "GET /health 200";
                # Demoted
                level = "debug";
                fields = {
                  method = "GET";
                  path = "/health";
                  status = "200";
                  duration = "11.742µs";
                  remote_addr = "10.42.80.71";
                  request_id = "3e230509-de6c-4757-abd0-8c535e1c7563";
                };
              }
            ];
          }
        ];
      };
    };
  };
}
