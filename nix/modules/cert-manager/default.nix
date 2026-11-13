{ inputs, self, ... }:
{
  config,
  pkgs,
  lib,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.cert-manager;
  kubelib = inputs.kube-generators.lib { inherit pkgs; };
  charts = inputs.nixhelm.charts { inherit pkgs; };
  rendered = kubelib.buildHelmChart {
    name = "cert-manager";
    namespace = "cert-manager";
    chart = charts.jetstack.cert-manager;
    values = {
      crds.enabled = true;
      config.enableGatewayAPI = true;
      podLabels = {
        "cluster.local/apiserver-egress" = "allow";
        "cluster.local/internet-egress" = "allow";
      };
      webhook.podLabels."cluster.local/apiserver-egress" = "allow";
      cainjector.podLabels."cluster.local/apiserver-egress" = "allow";
      startupapicheck.podLabels."cluster.local/apiserver-egress" = "allow";
    };
  };
  # The chart's images, preloaded from images.lock
  certManager = self.lib.images.chart pkgs ./images.lock rendered;
  webhook = pkgs.buildGo126Module rec {
    name = "cert-manager-webhook-libdns";
    version = "1.1.1-inwx-fix";
    meta.mainProgram = "cert-manager-webhook-libdns";
    src = pkgs.fetchFromGitHub {
      owner = "andsens";
      repo = name;
      rev = "822a5ddb8ee35358d040bab1cf6ef3246a18f6c0";
      hash = "sha256-/7oY2Yt+YWcv6tY/vBOUiWr00hW9fIAsqtDs2wGQ9gk=";
    };
    proxyVendor = true;
    vendorHash = "sha256-8XsRK1BR/D2hv18Dko/T99tuFzHBWE07r6PF4CRoqkA=";
    subPackages = [ "." ];
    ldflags = [
      "-s"
      "-w"
    ];

    doCheck = false; # Tests require kubebuilder running through `make test`
  };
  webhookImage = pkgs.dockerTools.buildImage {
    name = "cluster.local/${webhook.name}";
    copyToRoot = [
      webhook
      pkgs.cacert
    ]
    ++ lib.optionals cfg.debug ccfg.debugTools;
    config.User = "1001:1001";
    config.Entrypoint = [
      (pkgs.lib.getExe webhook)
    ];
  };
  libdnsWebhookConfig = lib.types.submodule {
    options = {
      provider = lib.mkOption {
        description = "Name of the DNS provider";
        type = lib.types.str;
      };
      secretName = lib.mkOption {
        description = "Name of the DNS provider credentials secret in the cert-manager namespace";
        type = lib.types.str;
      };
    };
  };
in
{
  options.homelab.cert-manager = {
    debug = lib.mkEnableOption "debug mode";
    acme-staging-issuer.webhook-config = lib.mkOption {
      description = "LibDNS webhook configuration for the ACME staging issuer";
      type = libdnsWebhookConfig;
    };
    acme-production-issuer.webhook-config = lib.mkOption {
      description = "LibDNS webhook configuration for the ACME production issuer";
      type = libdnsWebhookConfig;
    };
  };
  config = {
    homelab.cluster.imageLocks.${toString ./images.lock} = certManager.refs;
    services.k3s.images = [ webhookImage ] ++ certManager.images;
    homelab.kubernetes.kubernetes.customTypes = lib.concatMap self.lib.crd2types.customTypes (
      lib.filter (d: d.kind or null == "CustomResourceDefinition") (
        kubelib.fromYAML (builtins.readFile rendered)
      )
    );
    services.k3s.manifests = {
      cert-manager-helm.source = certManager.manifest;
      cert-manager-webhook-libdns-static.source = ./cert-manager-webhook-libdns.yaml;
    };
    homelab.kubernetes.submodules.instances.cert-manager = {
      submodule = "manifest";
      config = {
        kubernetes.resources =
          let
            controller = {
              "app.kubernetes.io/name" = "cert-manager";
              "app.kubernetes.io/component" = "controller";
              "app.kubernetes.io/instance" = "cert-manager";
            };
            webhook = {
              "app.kubernetes.io/name" = "webhook";
              "app.kubernetes.io/component" = "webhook";
              "app.kubernetes.io/instance" = "cert-manager";
            };
            toPorts = [ { ports = [ { port = "10250"; } ]; } ];
            acmeIssuer = server: privateKey: webhook-config: {
              metadata.namespace = null;
              spec.acme = {
                inherit server;
                privateKeySecretRef.name = privateKey;
                solvers = [
                  {
                    dns01.webhook = {
                      groupName = "cluster.local";
                      solverName = "libdns";
                      config = {
                        inherit (webhook-config) provider;
                        secretRef = {
                          namespace = "cert-manager";
                          name = webhook-config.secretName;
                        };
                      };
                    };
                  }
                ];
              };
            };
          in
          {
            namespaces.cert-manager.metadata.namespace = null;
            ciliumNetworkPolicies = {
              controller-to-webhook = {
                metadata.labels = controller;
                spec = {
                  endpointSelector.matchLabels = controller;
                  egress = [
                    {
                      toEndpoints = [ { matchLabels = webhook; } ];
                      inherit toPorts;
                    }
                  ];
                };
              };
              webhook-from-controller = {
                metadata.labels = webhook;
                spec = {
                  endpointSelector.matchLabels = webhook;
                  ingress = [
                    {
                      fromEntities = [ "kube-apiserver" ];
                      inherit toPorts;
                    }
                    {
                      fromEndpoints = [ { matchLabels = controller; } ];
                      inherit toPorts;
                    }
                  ];
                };
              };
            };
            clusterIssuers = {
              selfsigned = {
                metadata.namespace = null;
                spec.selfSigned = { };
              };
              letsencrypt-staging =
                acmeIssuer "https://acme-staging-v02.api.letsencrypt.org/directory" "letsencrypt-staging"
                  cfg.acme-staging-issuer.webhook-config;
              letsencrypt-production =
                acmeIssuer "https://acme-v02.api.letsencrypt.org/directory" "letsencrypt-production"
                  cfg.acme-production-issuer.webhook-config;
            };
            roles."cert-manager-webhook-libdns:secret-reader" = {
              metadata.labels."app.kubernetes.io/name" = "cert-manager-webhook-libdns";
              rules = [
                {
                  apiGroups = [ "" ];
                  resources = [ "secrets" ];
                  resourceNames = [
                    cfg.acme-staging-issuer.webhook-config.secretName
                    cfg.acme-production-issuer.webhook-config.secretName
                  ];
                  verbs = [
                    "get"
                    "watch"
                  ];
                }
              ];
            };
          };
        submodules.instances = {
          webhook-libdns = {
            name = "cert-manager-webhook-libdns";
            submodule = "deployment";
            args = {
              allowEgress = [
                "apiserver"
                "internet"
              ];
              allowIngress = [ "apiserver" ];
              ports.https = 8443;
              # Only the API server calls it (`allowIngress`)
              policyPorts = [ ];
              container = {
                image = "${webhookImage.buildArgs.name}:${webhookImage.imageTag}";
                imagePullPolicy = "Never";
                args = [
                  "--tls-cert-file=/tls/tls.crt"
                  "--tls-private-key-file=/tls/tls.key"
                  "--secure-port=8443"
                ];
                env.GROUP_NAME.value = "cluster.local";
                livenessProbe.httpGet = {
                  scheme = "HTTPS";
                  path = "/healthz";
                  port = "https";
                };
                readinessProbe.httpGet = {
                  scheme = "HTTPS";
                  path = "/healthz";
                  port = "https";
                };
                volumeMounts."/tls" = {
                  name = "tls";
                  readOnly = true;
                };
              };
            };
            config.kubernetes.resources.deployments.cert-manager-webhook-libdns.spec.template.spec = {
              serviceAccountName = "cert-manager-webhook-libdns";
              securityContext.fsGroup = 1001;
              volumes.tls.secret.secretName = "cert-manager-webhook-libdns-tls";
            };
          };
          webhook-libdns-service = {
            name = "cert-manager-webhook-libdns";
            submodule = "service";
            args.ports.https = {
              port = 443;
              targetPort = 8443;
            };
          };
        };
      };
    };
  };
}
