# How cert-manager's logs are parsed: klog in all its containers
{ inputs, ... }:
{ lib, ... }:
let
  klog = container: {
    namespace = "cert-manager";
    inherit container;
    format = "klog";
  };
in
{
  imports = [ inputs.homelab-monitoring.nixosModules.alloy ];
  config.homelab.alloy.logs.pods = {
    cert-manager-controller = klog "cert-manager-controller" // {
      examples = [
        {
          lines = [
            ''I1118 07:20:57.224618       1 controller.go:257] "starting controller" logger="cert-manager.controller" controller="certificaterequests-issuer-vault"''
            ''E1118 07:23:16.226150       1 indexers.go:67] "unable to fetch certificate that owns the secret" err="Certificate.cert-manager.io \"flood-tls\" not found" logger="cert-manager"''
          ];
          expect = [
            {
              message = "starting controller";
              level = "info";
              fields = {
                component = "cert-manager.controller";
                caller = "controller.go:257";
              };
            }
            {
              message = "unable to fetch certificate that owns the secret";
              level = "error";
              fields.error = ''Certificate.cert-manager.io "flood-tls" not found'';
            }
          ];
        }
      ];
    };
    cert-manager-cainjector = klog "cert-manager-cainjector";
    cert-manager-webhook = klog "cert-manager-webhook";
    cert-manager-webhook-libdns = klog "cert-manager-webhook-libdns" // {
      examples = [
        {
          lines = [
            "I1118 07:22:08.243661       1 handler.go:286] Adding GroupVersion cluster.local v1alpha1 to ResourceManager"
          ];
          expect = [
            {
              message = "Adding GroupVersion cluster.local v1alpha1 to ResourceManager";
              level = "info";
            }
          ];
        }
      ];
    };
  };
}
