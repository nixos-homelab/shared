# A Service named after the instance, selecting the pods of the workload by that name, as the pod-running submodules
# label them.
{
  config,
  lib,
  kubenix,
  name,
  args,
  ...
}:
let
  labels."app.kubernetes.io/name" = name;
in
{
  imports = [
    kubenix.modules.submodule
    kubenix.modules.k8s
    ./namespace.nix
  ];
  options.submodule.args.ports = lib.mkOption {
    description = "Ports by name: a port number, or the fields of a kubenix ServicePort (`port`, `targetPort`, `protocol`, ...).";
    type = lib.types.attrsOf (
      lib.types.coercedTo lib.types.port (port: { inherit port; }) (lib.types.attrsOf lib.types.anything)
    );
    default = { };
    example = {
      https = {
        port = 443;
        targetPort = 8443;
      };
      metrics = 9100;
    };
  };
  config = {
    submodule.name = "service";
    submodule.passthru.kubernetes.objects = config.kubernetes.objects;
    kubernetes.resources.services.${name} = {
      metadata = { inherit labels; };
      spec = {
        selector = labels;
        inherit (args) ports;
      };
    };
  };
}
