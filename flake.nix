{
  description = "NixOS Homelab";
  inputs = {
    systems.url = "github:nix-systems/default-linux";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
    kubetree = {
      url = "github:andsens/nix-kubetree";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
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
      inputs.kubetree.follows = "kubetree";
      inputs.flake-parts.follows = "flake-parts";
    };
    nixhelm = {
      url = "github:nix-community/nixhelm";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    kube-generators.url = "github:farcaller/nix-kube-generators";
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
            ipv4 = import ./nix/lib/ipv4.nix { inherit lib; };
            k8s = import ./nix/lib/k8s.nix { inherit lib; };
            setup-secrets = import ./nix/lib/setup-secrets.nix { inherit lib; };
          };
          nixosModules = {
            cert-manager = importApply ./nix/modules/cert-manager { inherit self inputs; };
            cluster = importApply ./nix/modules/cluster { inherit self inputs; };
            homepage = importApply ./nix/modules/homepage { inherit self inputs; };
            k8sss = importApply ./nix/modules/k8sss { inherit self inputs; };
            workload-macros = importApply ./nix/modules/workload-macros {
              inherit self inputs;
            };
            nfs-provisioner = importApply ./nix/modules/nfs-provisioner { inherit self inputs; };
            postgresql = importApply ./nix/modules/postgresql { inherit self inputs; };
            redis = importApply ./nix/modules/redis { inherit self inputs; };
            smb = importApply ./nix/modules/smb { inherit self inputs; };
          };
        };
        perSystem =
          { pkgs, system, ... }:
          let
            lib-docs = inputs.docs.lib.docs.lib {
              inherit pkgs;
              paths.lib = ./nix/lib;
            };
            options-docs = inputs.docs.lib.docs.options {
              inherit pkgs;
              modules = lib.attrValues self.nixosModules;
              repoPath = toString self;
              repoLinkPrefix = "https://github.com/nixos-homelab/shared/blob/main";
            };
          in
          {
            apps.update-docs.program = inputs.docs.lib.docs.updateRepo {
              inherit pkgs;
              paths."docs/lib" = "${lib-docs}/lib";
              paths."docs/options.md" = options-docs.optionsCommonMark;
            };
            packages = {
              container-utils = pkgs.callPackage ./nix/packages/container-utils { };
              lib-docs = lib-docs;
              options-docs = options-docs.optionsCommonMark;
            };
          };
      }
    );
}
