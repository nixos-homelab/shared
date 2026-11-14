# The pod of a homelab workload: one main container named after the instance, locked down, running as the cluster's
# workload user. Submodules that run pods import this and put `podTemplate` where their kind keeps the pod template.
{
  lib,
  name,
  args,
  ...
}:
let
  inherit (lib) mkOption mkDefault types;
in
{
  # `ports`, `policyPorts` and the other policy intent
  imports = [ ./policy.nix ];
  options = {
    submodule.args = {
      container = mkOption {
        description = "The main container, a module of the kubenix Container type. Its name, ports and security context are set here.";
        type = types.deferredModule;
        default = { };
      };
      allowIngress = mkOption {
        description = "Workloads whose pods may connect to this one, as the label `cluster.local/<workload>-ingress: allow` on the pods.";
        type = types.listOf types.str;
        default = [ ];
      };
      allowEgress = mkOption {
        description = "Workloads this one may connect to, as the label `cluster.local/<workload>-egress: allow` on the pods.";
        type = types.listOf types.str;
        default = [ ];
      };
      securityContext = {
        runAsUser = mkOption {
          description = "UID the pod runs as";
          type = types.int;
          default = 1000;
        };
        runAsGroup = mkOption {
          description = "GID the pod runs as, also its fsGroup";
          type = types.int;
          default = 1000;
        };
        supplementalGroups = mkOption {
          description = "Additional GIDs of the pod";
          type = types.listOf types.int;
          default = [ 100 ];
        };
      };
    };
    podTemplate = mkOption {
      description = "The pod template (`metadata` and `spec`) built from the args, for the submodule to place in its resource.";
      type = types.raw;
      internal = true;
    };
  };
  config = {
    # Lets `submodules.defaults` single out the submodules that run pods
    _m.features = [ "pod-spec" ];
    podTemplate = {
      metadata.labels = {
        "app.kubernetes.io/name" = name;
      }
      // lib.genAttrs (map (w: "cluster.local/${w}-ingress") args.allowIngress) (_: "allow")
      // lib.genAttrs (map (w: "cluster.local/${w}-egress") args.allowEgress) (_: "allow");
      spec = {
        securityContext = {
          runAsUser = mkDefault args.securityContext.runAsUser;
          runAsGroup = mkDefault args.securityContext.runAsGroup;
          fsGroup = mkDefault args.securityContext.runAsGroup;
          supplementalGroups = mkDefault args.securityContext.supplementalGroups;
        };
        containers.${name} = lib.mkMerge [
          # A function: kubenix types take an attribute set as config only, imports included
          (_: { imports = [ args.container ]; })
          {
          # Unset without ports: kubenix writes an empty attribute set as `ports: []`
          ports = lib.mkIf (args.ports != { }) (lib.mapAttrs (_: p: lib.filterAttrs (_: v: v != null) p) args.ports);
          securityContext = {
            allowPrivilegeEscalation = mkDefault false;
            readOnlyRootFilesystem = mkDefault true;
            capabilities = {
              add = lib.optional (args.ports != { }) "NET_BIND_SERVICE";
              drop = mkDefault [ "ALL" ];
            };
          };
          }
        ];
      };
    };
  };
}
