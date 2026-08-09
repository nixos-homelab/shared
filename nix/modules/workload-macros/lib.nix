{ lib, transform, ... }:
with builtins;
let
  inherit (transform) mkDotPath buildMetadata;
in
{
  transformWorkloadMacro =
    cfg: resource:
    let
      dotPath = mkDotPath resource;
      metadata = buildMetadata resource;
      dataPath = dotPath "spec.dataPath" null;
      podSpecMacro = dotPath "spec.podSpecMacro" null;
      portsByName = (lib.attrByPath [ "mainContainer" "portsByName" ] { } podSpecMacro);
      netpolPorts = lib.mapAttrsToList (
        name: portSpec:
        if isInt portSpec then
          portSpec
        else
          {
            port = portSpec.containerPort;
          }
          // lib.optionalAttrs (hasAttr "protocol" portSpec) { protocol = portSpec.protocol; }
      ) portsByName;
      ingressPort = dotPath "spec.ingressPort" null;
      allowIngress = (lib.optional (ingressPort != null) "gateway") ++ (dotPath "spec.allowIngress" [ ]);
      allowEgress = dotPath "spec.allowEgress" [ ];
    in
    {
      apiVersion = "v1";
      kind = "List";
      items = [
        {
          apiVersion = "v1";
          kind = "Namespace";
          metadata.name = metadata.namespace;
        }
        {
          inherit metadata;
          apiVersion = "cluster.local";
          kind = "DeploymentMacro";
          spec =
            lib.recursiveUpdate
              (removeAttrs (dotPath "spec" { }) [
                "allowEgress"
                "allowIngress"
                "dataPath"
                "podSpecMacro"
                "ingressPort"
              ])
              {
                inherit allowEgress allowIngress;
                podSpecMacro =
                  if dataPath != null then
                    lib.recursiveUpdate {
                      mainContainer.volumeMountsByPath.${dataPath} = "data";
                      volumesByName.data.persistentVolumeClaim.claimName = metadata.name;
                    } podSpecMacro
                  else
                    podSpecMacro;
              };
        }
      ]
      ++ (lib.optional (dataPath != null) {
        apiVersion = "v1";
        kind = "PersistentVolumeClaim";
        inherit metadata;
        spec = {
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "1Gi";
          volumeMode = "Filesystem";
        };
      })
      ++ (
        lib.optionals (length (attrNames portsByName) > 0) [
          {
            inherit metadata;
            apiVersion = "cluster.local";
            kind = "ServiceMacro";
            spec.portsByName = lib.mapAttrs (
              name: portSpec:
              if isInt portSpec then
                portSpec
              else
                {
                  inherit name;
                  port = portSpec.containerPort;
                }
                // lib.optionalAttrs (hasAttr "protocol" portSpec) { protocol = portSpec.protocol; }
            ) portsByName;
          }
          {
            inherit metadata;
            apiVersion = "cluster.local";
            kind = "NetpolMacro";
            spec.ports = netpolPorts;
          }
        ]
        ++ lib.optional (ingressPort != null) ({
          inherit metadata;
          apiVersion = "cluster.local";
          kind = "GatewayMacro";
          spec.port = ingressPort;
        })
      );
    };
  transformDeploymentMacro =
    cfg: resource:
    let
      dotPath = mkDotPath resource;
      metadata = buildMetadata resource;
      podSpecMacro = dotPath "spec.podSpecMacro" null;
    in
    {
      inherit metadata;
      apiVersion = "apps/v1";
      kind = "Deployment";
      spec =
        lib.recursiveUpdate
          {
            strategy.type = "Recreate";
            selector.matchLabels = {
              "app.kubernetes.io/name" = metadata.name;
            }
            // lib.optionalAttrs (hasAttr "labels" metadata) metadata.labels;
            template = {
              metadata.labels = {
                "app.kubernetes.io/name" = metadata.name;
              }
              // lib.optionalAttrs (hasAttr "labels" metadata) metadata.labels
              // (lib.mergeAttrsList (
                (map (workload: { "cluster.local/${workload}-ingress" = "allow"; }) (
                  dotPath "spec.allowIngress" [ ]
                ))
                ++ (map (workload: { "cluster.local/${workload}-egress" = "allow"; }) (
                  dotPath "spec.allowEgress" [ ]
                ))
              ));
            }
            // lib.optionalAttrs (podSpecMacro != null) ({
              podSpecMacro = podSpecMacro // {
                name = metadata.name;
              };
            });
          }
          (
            removeAttrs (dotPath "spec" { }) [
              "podSpecMacro"
              "allowIngress"
              "allowEgress"
            ]
          );
    };
  transformPodSpecMacro =
    cfg: resource:
    let
      dotPath = mkDotPath resource;
      name = dotPath "podSpecMacro.name" (throw "The PodSpecMacro has no name");
    in
    if (dotPath "podSpecMacro" null) == null then
      resource
    else
      lib.recursiveUpdate (removeAttrs resource [ "podSpecMacro" ]) ({
        spec =
          lib.recursiveUpdate
            {
              securityContext = {
                runAsUser = cfg.workload-macros.securityContext.runAsUser;
                runAsGroup = cfg.workload-macros.securityContext.runAsGroup;
                supplementalGroups = cfg.workload-macros.securityContext.supplementalGroups;
                fsGroup = cfg.workload-macros.securityContext.runAsGroup;
              };
              containersByName = {
                "${name}" =
                  lib.recursiveUpdate
                    {
                      inherit name;
                      securityContext = {
                        allowPrivilegeEscalation = false;
                        readOnlyRootFilesystem = true;
                        capabilities.add =
                          (dotPath "podSpecMacro.mainContainer.addCapabilities" [ ])
                          ++ lib.optional (
                            length (attrNames (dotPath "podSpecMacro.mainContainer.portsByName" { })) > 0
                          ) "NET_BIND_SERVICE";
                        capabilities.drop = [ "ALL" ];
                      };
                      volumeMountsByPath = dotPath "podSpecMacro.mainContainer.volumeMountsByPath" { };
                    }
                    (
                      removeAttrs (dotPath "podSpecMacro.mainContainer" { }) [
                        "addCapabilities"
                      ]
                    );
              };
              volumesByName = dotPath "podSpecMacro.volumesByName" { };
            }
            (
              removeAttrs ((dotPath "podSpecMacro") (throw "Unable to find 'podSpecMacro' attribute")) [
                "name"
                "mainContainer"
              ]
            );
      });
  transformServiceMacro =
    cfg: resource:
    let
      dotPath = mkDotPath resource;
      metadata = buildMetadata resource;
    in
    lib.recursiveUpdate
      {
        inherit metadata;
        apiVersion = "v1";
        kind = "Service";
        spec.selector."app.kubernetes.io/name" = metadata.name;
      }
      (
        removeAttrs (dotPath "." (throw null)) [
          "apiVersion"
          "kind"
          "metadata"
        ]
      );
  transformGatewayMacro =
    cfg: resource:
    let
      dotPath = mkDotPath resource;
      metadata = buildMetadata resource;
      subdomain = dotPath "spec.subdomain" (metadata.name);
      hostname =
        if subdomain == null then
          cfg.workload-macros.domain
        else
          "${subdomain}.${cfg.workload-macros.domain}";
    in
    {
      apiVersion = "v1";
      kind = "List";
      items = [
        {
          apiVersion = "gateway.networking.k8s.io/v1";
          kind = "Gateway";
          metadata = metadata // {
            annotations."cert-manager.io/cluster-issuer" = cfg.workload-macros.acmeProvider;
          };
          spec = {
            gatewayClassName = cfg.workload-macros.gatewayClassName;
            listeners = [
              {
                inherit hostname;
                name = "${metadata.name}-cleartext-redirect";
                port = 80;
                protocol = "HTTP";
              }
              {
                inherit hostname;
                name = metadata.name;
                port = 443;
                protocol = "HTTPS";
                tls.mode = "Terminate";
                tls.certificateRefs = [ { name = "${metadata.name}-tls"; } ];
              }
            ];
          };
        }
        {
          inherit metadata;
          apiVersion = "gateway.networking.k8s.io/v1";
          kind = "HTTPRoute";
          spec = {
            parentRefs = [
              {
                name = metadata.name;
                port = 443;
              }
            ];
            hostnames = [ hostname ];
            rules = [
              (
                {
                  matches = [
                    {
                      path.type = "PathPrefix";
                      path.value = "/";
                    }
                  ];
                  backendRefs = [
                    {
                      name = metadata.name;
                      port = dotPath "spec.port" (throw "You must specificy a port for GatewayMacro");
                    }
                  ];
                }
                // lib.optionalAttrs ((dotPath "spec.requestHeaderModifier" null) != null) {
                  filters = [
                    {
                      type = "RequestHeaderModifier";
                      requestHeaderModifier = dotPath "spec.requestHeaderModifier" null;
                    }
                  ];
                }
              )
            ];
          };
        }
        {
          apiVersion = "gateway.networking.k8s.io/v1";
          kind = "HTTPRoute";
          metadata = metadata // {
            name = "${metadata.name}-cleartext-redirect";
          };
          spec = {
            parentRefs = [
              {
                name = metadata.name;
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
        }
      ];
    };
}
