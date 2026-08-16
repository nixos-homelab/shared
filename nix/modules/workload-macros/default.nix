{ inputs, self, ... }:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.kubetree.workloadMacros;
  transform = inputs.kubetree.lib.transform;
  sm = import ./lib.nix { inherit lib transform; };
  container-utils = self.packages.${pkgs.stdenv.hostPlatform.system}.container-utils;
in
{
  key = "${toString __curPos.file}#modules.nixos.workload-macros";
  options.kubetree.workloadMacros = {
    enable = lib.mkEnableOption "service macro transformers";
    domain = lib.mkOption {
      description = "Domain name to suffix hostnames with";
      type = lib.types.str;
      default = config.networking.domain;
      defaultText = lib.literalExpression "config.networking.domain";
    };
    gatewayClassName = lib.mkOption {
      description = "Name of the Gateway class that should set on all gateways generated through the \"GatewayMacro\" macro";
      type = lib.types.str;
    };
    acmeProvider = lib.mkOption {
      description = "The ACME provider that Ingresses should use for obtaining TLS certs";
      type = lib.types.str;
    };
    containerUtils = lib.mkOption {
      description = "Image ref for container-utils";
      type = lib.types.str;
      default = "${container-utils.buildArgs.name}:${container-utils.imageTag}";
      defaultText = lib.literalExpression "homelab-shared.packages.container-utils";
    };
    securityContext = {
      runAsUser = lib.mkOption {
        description = "UID for pods to run as";
        type = lib.types.int;
        default = 1000;
      };
      runAsGroup = lib.mkOption {
        description = "GID for pods to run with, also sets securityContext.fsGroup";
        type = lib.types.int;
        default = 1000;
      };
      supplementalGroups = lib.mkOption {
        description = "Additional GIDs to apply to the pods";
        type = lib.types.listOf lib.types.int;
        default = [ 100 ];
      };
    };
  };
  config = {
    kubetree.transformers = lib.mkIf cfg.enable {
      v1.Pod._transformers = [ sm.transformPodSpecMacro ];
      "cluster.local" = {
        WorkloadMacro._transformers = [
          sm.transformWorkloadMacro
          transform.transformResource
          transform.flattenResourceList
        ];
        DeploymentMacro._transformers = [
          sm.transformDeploymentMacro
          transform.transformResource
        ];
        DaemonSetMacro._transformers = [
          sm.transformDaemonSetMacro
          transform.transformResource
        ];
        CronJobMacro._transformers = [
          sm.transformCronJobMacro
          transform.transformResource
        ];
        JobMacro._transformers = [
          sm.transformJobMacro
          transform.transformResource
        ];
        ServiceMacro._transformers = [
          sm.transformServiceMacro
          transform.transformResource
        ];
        GatewayMacro._transformers = [
          sm.transformGatewayMacro
          transform.transformResource
          transform.flattenResourceList
        ];
        ScriptMacro._transformers = [
          sm.transformScriptMacro
          transform.transformResource
        ];
      };
    };
  };
}
