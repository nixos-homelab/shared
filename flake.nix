{
  description = "NixOS Homelab";
  inputs = {
    systems.url = "github:nix-systems/default-linux";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    kubenix = {
      url = "github:hall/kubenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.systems.follows = "systems";
    };
    setup-secrets = {
      url = "github:andsens/nixos-setup-secrets";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    k8sss = {
      url = "github:andsens/k8sss";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    kube-generators.url = "github:farcaller/nix-kube-generators";
    # Alloy's module, for the `homelab.alloy.monitors` of the components here
    homelab-monitoring = {
      url = "github:nixos-homelab/monitoring";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.setup-secrets.follows = "setup-secrets";
      inputs.kube-generators.follows = "kube-generators";
      inputs.docs.follows = "docs";
      inputs.homelab-shared.follows = "";
    };
    docs = {
      url = "github:andsens/nix-docs";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
  };
  outputs =
    {
      systems,
      flake-parts,
      nixpkgs,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } (
      {
        flake-parts-lib,
        self,
        inputs,
        lib,
        ...
      }:
      let
        inherit (flake-parts-lib) importApply;
      in
      {
        systems = import systems;
        flake = {
          lib = {
            importsApply = map (path: importApply path { inherit self inputs; });
            checks = import ./nix/lib/checks.nix { inherit self inputs lib; };
            crd2types = import ./nix/lib/crd2types.nix { inherit lib; };
            crds = import ./nix/lib/crds.nix { inherit self inputs lib; };
            homepage = import ./nix/lib/homepage.nix { inherit lib; };
            images = import ./nix/lib/images.nix { inherit lib; };
            ipv4 = import ./nix/lib/ipv4.nix { inherit lib; };
            k8s = import ./nix/lib/k8s.nix { inherit lib; };
            pins = import ./nix/lib/pins.nix { inherit lib; };
            setup-secrets = import ./nix/lib/setup-secrets.nix { inherit lib; };
          };
          nixosModules = {
            cert-manager = importApply ./nix/modules/cert-manager { inherit self inputs; };
            cluster = importApply ./nix/modules/cluster { inherit self inputs; };
            homepage = importApply ./nix/modules/homepage { inherit self inputs; };
            k3s = importApply ./nix/modules/k3s { inherit self inputs; };
            k8sss = importApply ./nix/modules/k8sss { inherit self inputs; };
            workloads = importApply ./nix/modules/workloads { inherit self inputs; };
          };
        };
        perSystem =
          { pkgs, system, ... }:
          {
            # Dead Nix code. Pattern names stay: modules take { config, lib, pkgs, ... } whether they use them or not
            checks.deadnix = pkgs.runCommand "deadnix" { nativeBuildInputs = [ pkgs.deadnix ]; } ''
              deadnix --fail --no-lambda-pattern-names ${self}
              touch $out
            '';
            # k3s itself on one node, under the NixOS test driver (needs KVM)
            checks.k3s = import ./nix/tests/k3s.nix { inherit self pkgs lib; };
            # The parsers of this flake's workloads on their examples, through the pinned Alloy and Loki
            checks.logs = inputs.homelab-monitoring.lib.logs.check {
              inherit pkgs;
              modules = [ { homelab.k8sss.enable = true; } ];
            };
            # The LogQL queries of this flake's dashboard panels, through the pinned Loki: k3s' journal on Cluster
            checks.logql = inputs.homelab-monitoring.lib.logs.queries {
              inherit pkgs;
              config =
                (inputs.nixpkgs.lib.nixosSystem {
                  modules =
                    lib.attrValues self.nixosModules
                    ++ lib.attrValues inputs.homelab-monitoring.nixosModules
                    ++ [
                      self.lib.checks.fixture
                      { nixpkgs.hostPlatform = system; }
                      {
                        homelab = {
                          alloy.enable = true;
                          grafana.enable = true;
                          loki.enable = true;
                        };
                      }
                    ];
                }).config;
              streams = [
                {
                  source = "journal";
                  node = "nas";
                  unit = "k3s.service";
                  program = "k3s";
                  service_name = "k3s";
                }
              ];
            };
            # The PromQL of this flake's alert rules through promtool, with Grafana on to have them
            checks.promql = inputs.homelab-monitoring.lib.alerts.check {
              inherit pkgs;
              config =
                (inputs.nixpkgs.lib.nixosSystem {
                  modules =
                    lib.attrValues self.nixosModules
                    ++ lib.attrValues inputs.homelab-monitoring.nixosModules
                    ++ [
                      self.lib.checks.fixture
                      { nixpkgs.hostPlatform = system; }
                      {
                        homelab = {
                          alloy.enable = true;
                          grafana.enable = true;
                        };
                      }
                    ];
                }).config;
            };
            checks.manifests = self.lib.checks.manifests {
              inherit pkgs;
              modules = [
                {
                  homelab = {
                    homepage = {
                      enable = true;
                      allowEgress = [ ];
                    };
                    k8sss.enable = true;
                    # Evaluates the metrics parts of the modules, off with Alloy
                    alloy.enable = true;
                  };
                }
              ];
            };
            packages = {
              container-utils = pkgs.callPackage ./nix/packages/container-utils { };
              lock-images = pkgs.callPackage ./nix/packages/lock-images { };
              lib-docs = inputs.docs.lib.docs.lib {
                inherit pkgs;
                paths.lib = ./nix/lib;
              };
              options-docs = inputs.docs.lib.docs.options {
                inherit pkgs;
                modules = lib.attrValues self.nixosModules;
                repoPath = toString self;
                repoLinkPrefix = "https://github.com/nixos-homelab/shared/blob/main";
                prefixGroups = {
                  cert-manager = [ "homelab.cert-manager" ];
                  cluster = [ "homelab.cluster" ];
                  k3s = [ "homelab.k3s" ];
                  k8sss = [ "homelab.k8sss" ];
                  workloads = [
                    "homelab.workloads"
                    "homelab.kubernetes"
                  ];
                  homepage = [ "homelab.homepage.sections" ];
                };
              };
              manual-docs = inputs.docs.lib.mkdocs.manual {
                inherit pkgs;
                rootDoc = ./README.md;
                pathMap = {
                  kubenix = ./nix/modules/workloads/README.md;
                };
              };
            };
          };
      }
    );
}
