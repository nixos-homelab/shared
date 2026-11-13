{ self, ... }:
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.homelab.workloads;
  container-utils = self.packages.${pkgs.stdenv.hostPlatform.system}.container-utils;
in
{
  # https://github.com/hercules-ci/flake-parts/pull/251
  key = "${toString __curPos.file}#modules.nixos.workloads";
  options.homelab = {
    workloads = {
      domain = lib.mkOption {
        description = "Domain name to suffix hostnames with";
        type = lib.types.str;
      };
      gatewayClassName = lib.mkOption {
        description = "Gateway class of the Gateways of workloads";
        type = lib.types.str;
      };
      acmeProvider = lib.mkOption {
        description = "The ClusterIssuer that Gateways and Certificates get their TLS certificates from";
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
    kubernetes = lib.mkOption {
      description = "kubenix configuration of the cluster, with the submodules of this module.";
      type = lib.types.deferredModule;
      default = { };
    };
  };
  config.homelab.kubernetes =
    { kubenix, config, ... }:
    {
      imports = [ kubenix.modules.submodules ];
      submodules.imports = [
        ./cronjob.nix
        ./daemonset.nix
        ./deployment.nix
        ./job.nix
        ./manifest.nix
        ./script.nix
        ./service.nix
        ./workload.nix
      ];
      submodules.defaults = [
        # The cluster's custom types reach every submodule
        {
          features = [ "k8s" ];
          default.kubernetes = {
            inherit (config.kubernetes) customTypes;
            customTypesModuleDefinesCRDSpec = false;
          };
        }
        {
          features = [ "pod-spec" ];
          default.submodule.args.securityContext = lib.mapAttrs (_: lib.mkDefault) cfg.securityContext;
        }
        {
          name = "workload";
          default.submodule.args.gateway = {
            domain = lib.mkDefault cfg.domain;
            className = lib.mkDefault cfg.gatewayClassName;
            issuer = lib.mkDefault cfg.acmeProvider;
          };
        }
        {
          name = "script";
          default.submodule.args.image = lib.mkDefault cfg.containerUtils;
        }
      ];
    };
}
