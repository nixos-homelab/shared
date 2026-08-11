{ lib, transform, ... }:
with builtins;
let
  mkResourceHelper =
    resource:
    let
      fns = transform.mkResourceHelper resource;
    in
    fns
    // {
      metadata =
        let
          name = fns.dotPath "metadata.name" (throw "You must specify metadata.name");
          namespace = fns.dotPath "metadata.namespace" name;
        in
        {
          inherit namespace;
          labels."app.kubernetes.io/name" = name;
        }
        // fns.dotPath "metadata" (throw "You must specify metadata");
    };
  inheritPodSpecMacro =
    path: resource:
    let
      inherit (mkResourceHelper resource) dotPath metadata inheritPaths;
      podSpecMacro = dotPath "spec.podSpecMacro" null;
    in
    lib.recursiveUpdate
      (lib.setAttrByPath (lib.splitString "." path) (
        {
          metadata.labels = {
            "app.kubernetes.io/name" = metadata.name;
          }
          // lib.optionalAttrs (hasAttr "labels" metadata) metadata.labels;
        }
        // (inheritPaths [
          "spec.allowIngress"
          "spec.allowEgress"
        ])
        // lib.optionalAttrs (podSpecMacro != null) ({
          podSpecMacro = podSpecMacro // {
            name = metadata.name;
          };
        })
      ))
      (
        removeAttrs (dotPath "spec" { }) [
          "allowIngress"
          "allowEgress"
          "dataPath"
          "ingressPort"
          "podSpecMacro"
        ]
      );
in
{
  transformWorkloadMacro =
    cfg: resource:
    let
      inherit (mkResourceHelper resource) dotPath metadata;
      dataPath = dotPath "spec.dataPath" null;
      portsByName = dotPath "spec.podSpecMacro.mainContainer.portsByName" { };
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
          spec = (
            # Nested rec.-update. allowIngress must override, but data volume setup may not.
            lib.recursiveUpdate
              (lib.recursiveUpdate (lib.optionalAttrs (dataPath != null) {
                podSpecMacro = {
                  mainContainer.volumeMountsByPath.${dataPath} = "data";
                  volumesByName.data.persistentVolumeClaim.claimName = metadata.name;
                };
              }) (inheritPodSpecMacro "template" resource))
              {
                allowIngress = (lib.optional (ingressPort != null) "gateway") ++ (dotPath "spec.allowIngress" [ ]);
              }
          );
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
      inherit (mkResourceHelper resource) metadata;
    in
    {
      inherit metadata;
      apiVersion = "apps/v1";
      kind = "Deployment";
      spec = lib.recursiveUpdate {
        strategy.type = "Recreate";
        selector.matchLabels = {
          "app.kubernetes.io/name" = metadata.name;
        }
        // lib.optionalAttrs (hasAttr "labels" metadata) metadata.labels;
      } (inheritPodSpecMacro "template" resource);
    };
  transformDaemonSetMacro =
    cfg: resource:
    let
      inherit (mkResourceHelper resource) metadata;
    in
    {
      inherit metadata;
      apiVersion = "apps/v1";
      kind = "DaemonSet";
      spec = lib.recursiveUpdate {
        selector.matchLabels = {
          "app.kubernetes.io/name" = metadata.name;
        }
        // lib.optionalAttrs (hasAttr "labels" metadata) metadata.labels;
      } (inheritPodSpecMacro "template" resource);
    };
  transformCronJobMacro =
    cfg: resource:
    let
      inherit (mkResourceHelper resource) metadata;
    in
    {
      inherit metadata;
      apiVersion = "batch/v1";
      kind = "CronJob";
      spec = lib.recursiveUpdate {
        jobTemplate.spec.template.podSpecMacro.restartPolicy = "OnFailure";
      } (inheritPodSpecMacro "jobTemplate.spec.template" resource);
    };
  transformJobMacro =
    cfg: resource:
    let
      inherit (mkResourceHelper resource) metadata;
    in
    {
      inherit metadata;
      apiVersion = "batch/v1";
      kind = "Job";
      spec = lib.recursiveUpdate {
        template.podSpecMacro.restartPolicy = "OnFailure";
      } (inheritPodSpecMacro "template" resource);
    };
  transformPodSpecMacro =
    cfg: resource:
    let
      inherit (mkResourceHelper resource) dotPath;
      name = dotPath "podSpecMacro.name" (throw "The PodSpecMacro has no name");
      podSpecMacro = dotPath "podSpecMacro" null;
    in
    lib.recursiveUpdate
      (removeAttrs resource [
        "podSpecMacro"
        "allowIngress"
        "allowEgress"
      ])
      (
        {
          metadata.labels = (
            lib.mergeAttrsList (
              (map (workload: { "cluster.local/${workload}-ingress" = "allow"; }) (dotPath "allowIngress" [ ]))
              ++ (map (workload: { "cluster.local/${workload}-egress" = "allow"; }) (dotPath "allowEgress" [ ]))
            )
          );
        }
        // lib.optionalAttrs (podSpecMacro != null) ({
          spec =
            lib.recursiveUpdate
              {
                securityContext = {
                  runAsUser = cfg.workloadMacros.securityContext.runAsUser;
                  runAsGroup = cfg.workloadMacros.securityContext.runAsGroup;
                  supplementalGroups = cfg.workloadMacros.securityContext.supplementalGroups;
                  fsGroup = cfg.workloadMacros.securityContext.runAsGroup;
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
                removeAttrs podSpecMacro [
                  "name"
                  "mainContainer"
                ]
              );
        })
      );
  transformServiceMacro =
    cfg: resource:
    let
      inherit (mkResourceHelper resource) dotPath metadata;
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
      inherit (mkResourceHelper resource) dotPath metadata;
      subdomain = dotPath "spec.subdomain" (metadata.name);
      hostname =
        if subdomain == null then
          cfg.workloadMacros.domain
        else
          "${subdomain}.${cfg.workloadMacros.domain}";
    in
    {
      apiVersion = "v1";
      kind = "List";
      items = [
        {
          apiVersion = "gateway.networking.k8s.io/v1";
          kind = "Gateway";
          metadata = metadata // {
            annotations."cert-manager.io/cluster-issuer" = cfg.workloadMacros.acmeProvider;
          };
          spec = {
            gatewayClassName = cfg.workloadMacros.gatewayClassName;
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
