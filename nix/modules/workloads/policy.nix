# Who may reach the pods of an instance, as CNI-neutral intent: the ports of the pods by name, and which of them other
# pods, the API server and the world outside the cluster may reach. The module of the CNI turns it into policies for
# every submodule with the feature `pod-policy` through `submodules.defaults`; without one there are none.
{
  lib,
  name,
  args,
  ...
}:
let
  inherit (lib) mkOption types;
  port = types.coercedTo types.port (containerPort: { inherit containerPort; }) (
    types.submodule {
      options = {
        containerPort = mkOption {
          description = "Port the pod listens on";
          type = types.port;
        };
        protocol = mkOption {
          description = "Protocol of the port, TCP when unset";
          type = types.nullOr (
            types.enum [
              "TCP"
              "UDP"
              "SCTP"
            ]
          );
          default = null;
        };
      };
    }
  );
  portNames = types.listOf (types.enum (lib.attrNames args.ports));
in
{
  options = {
    submodule.args = {
      ports = mkOption {
        description = "Ports of the pod by name: a port number, or `containerPort` and `protocol`.";
        type = types.attrsOf port;
        default = { };
        example = {
          web = 3000;
          dns = {
            containerPort = 53;
            protocol = "UDP";
          };
        };
      };
      policyPorts = mkOption {
        description = "Names of the `ports` other pods may reach: pods labeled `cluster.local/<name>-egress: allow` may connect to them, from any namespace. None, no such policies.";
        type = portNames;
        default = lib.attrNames args.ports;
        defaultText = lib.literalExpression "lib.attrNames args.ports";
      };
      apiServerPorts = mkOption {
        description = "Names of the `ports` the Kubernetes API server may reach, as it calls admission webhooks and API services.";
        type = portNames;
        default = [ ];
      };
      worldPorts = mkOption {
        description = "Names of the `ports` reachable from outside the cluster.";
        type = portNames;
        default = [ ];
      };
    };
    policySelector = mkOption {
      description = "Labels of the pods the policies are about.";
      type = types.attrsOf types.str;
      default."app.kubernetes.io/name" = name;
      defaultText = lib.literalExpression ''{ "app.kubernetes.io/name" = name; }'';
      internal = true;
    };
  };
  # Lets the CNI module single out the submodules with policy intent
  config._m.features = [ "pod-policy" ];
}
