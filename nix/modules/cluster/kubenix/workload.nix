# A long-running workload: Namespace, Deployment, and depending on the args a PersistentVolumeClaim, a Service and a
# Gateway with its HTTPRoutes. Everything lands in the namespace named after the instance; change any object through
# the instance's `config`.
{
  config,
  lib,
  kubenix,
  name,
  args,
  ...
}:
let
  inherit (lib) mkOption types;
  labels."app.kubernetes.io/name" = name;
  hostname = if args.gateway.subdomain == null then args.gateway.domain else "${args.gateway.subdomain}.${args.gateway.domain}";
in
{
  imports = [
    kubenix.modules.submodule
    kubenix.modules.k8s
    ./pod-spec.nix
  ];
  options.submodule.args = {
    dataPath = mkOption {
      description = "Where the main container mounts a 1Gi PersistentVolumeClaim named after the workload.";
      type = types.nullOr types.str;
      default = null;
    };
    ingressPort = mkOption {
      description = "Port of the Service the Gateway routes to; allows ingress from the gateway.";
      type = types.nullOr types.port;
      default = null;
    };
    httpRouteRules = mkOption {
      description = "HTTPRoute rules ahead of the catch-all rule to `ingressPort`.";
      type = types.listOf types.attrs;
      default = [ ];
    };
    gateway = {
      subdomain = mkOption {
        description = "Subdomain of the Gateway hostname, the bare domain when null.";
        type = types.nullOr types.str;
        default = name;
        defaultText = lib.literalExpression "name";
      };
      domain = mkOption {
        description = "Domain of the Gateway hostname.";
        type = types.str;
      };
      className = mkOption {
        description = "Gateway class of the Gateway.";
        type = types.str;
      };
      issuer = mkOption {
        description = "cert-manager ClusterIssuer of the Gateway certificate.";
        type = types.str;
      };
    };
  };
  config = {
    submodule.name = "workload";
    submodule.passthru.kubernetes.objects = config.kubernetes.objects;
    submodule.args.allowIngress = lib.optional (args.ingressPort != null) "gateway";
    kubernetes = {
      namespace = name;
      # Freeform until the Gateway API CRDs are typed
      customTypes = {
        gateway = {
          attrName = "gateways";
          group = "gateway.networking.k8s.io";
          version = "v1";
          kind = "Gateway";
        };
        httproute = {
          attrName = "httproutes";
          group = "gateway.networking.k8s.io";
          version = "v1";
          kind = "HTTPRoute";
        };
      };
      resources = {
        # Cluster-scoped: no namespace, which kubenix gives every object by default
        namespaces.${name}.metadata.namespace = null;
        deployments.${name} = {
          metadata = { inherit labels; };
          spec = {
            strategy.type = "Recreate";
            selector.matchLabels = labels;
            template = lib.mkMerge [
              config.podTemplate
              (lib.mkIf (args.dataPath != null) {
                spec.containers.${name}.volumeMounts.${args.dataPath}.name = "data";
                spec.volumes.data.persistentVolumeClaim.claimName = name;
              })
            ];
          };
        };
        persistentVolumeClaims = lib.mkIf (args.dataPath != null) {
          ${name} = {
            metadata = { inherit labels; };
            spec = {
              accessModes = [ "ReadWriteOnce" ];
              resources.requests.storage = "1Gi";
              volumeMode = "Filesystem";
            };
          };
        };
        services = lib.mkIf (args.ports != { }) {
          ${name} = {
            metadata = { inherit labels; };
            spec = {
              selector = labels;
              ports = lib.mapAttrs (
                _: p: { port = p.containerPort; } // lib.optionalAttrs (p.protocol != null) { inherit (p) protocol; }
              ) args.ports;
            };
          };
        };
        gateways = lib.mkIf (args.ingressPort != null) {
          ${name} = {
            metadata = {
              inherit labels;
              annotations."cert-manager.io/cluster-issuer" = args.gateway.issuer;
            };
            spec = {
              gatewayClassName = args.gateway.className;
              listeners = [
                {
                  inherit hostname;
                  name = "${name}-cleartext-redirect";
                  port = 80;
                  protocol = "HTTP";
                }
                {
                  inherit hostname name;
                  port = 443;
                  protocol = "HTTPS";
                  tls.mode = "Terminate";
                  tls.certificateRefs = [ { name = "${name}-tls"; } ];
                }
              ];
            };
          };
        };
        httproutes = lib.mkIf (args.ingressPort != null) {
          ${name} = {
            metadata = { inherit labels; };
            spec = {
              parentRefs = [
                {
                  inherit name;
                  port = 443;
                }
              ];
              hostnames = [ hostname ];
              rules = args.httpRouteRules ++ [
                {
                  matches = [
                    {
                      path.type = "PathPrefix";
                      path.value = "/";
                    }
                  ];
                  backendRefs = [
                    {
                      inherit name;
                      port = args.ingressPort;
                    }
                  ];
                }
              ];
            };
          };
          "${name}-cleartext-redirect" = {
            metadata = { inherit labels; };
            spec = {
              parentRefs = [
                {
                  inherit name;
                  port = 80;
                }
              ];
              hostnames = [ hostname ];
              rules = [
                {
                  filters = [
                    {
                      type = "RequestRedirect";
                      requestRedirect.scheme = "https";
                      requestRedirect.statusCode = 301;
                    }
                  ];
                }
              ];
            };
          };
        };
      };
    };
  };
}
