{
  self,
  inputs,
  lib,
}:
{
  # A machine with this flake's modules set up enough to evaluate and run: the cluster's domain and issuers, a wheel
  # user for k8sss, k3s. For the checks here and in the other homelab repos
  fixture = {
    networking.hostName = "manifests";
    # k8sss makes the SSH keys of wheel users step-ca admins. The private half of this one is gone
    users.users.admin = {
      isNormalUser = true;
      uid = 1000;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN+kj02ez01d/NBAbS3ybonaf76LMymdbEblV9pHEwZj admin@example.org"
      ];
    };
    homelab.workloads = {
      domain = "example.org";
      acmeProvider = "letsencrypt-staging";
      gatewayClassName = "example";
    };
    homelab.k3s = {
      enable = true;
      dataDir = "/var/lib/rancher/k3s";
    };
    homelab.cert-manager =
      let
        webhook-config = {
          provider = "inwx";
          secretName = "dns-credentials";
        };
      in
      {
        acme-staging-issuer = { inherit webhook-config; };
        acme-production-issuer = { inherit webhook-config; };
      };
  };
  # Checks what a set of NixOS modules sends to the cluster, on top of a cluster with this flake's modules, without running
  # one: every manifest against the Kubernetes schemas and those of the CRDs it uses, every container against pulling.
  # config, a whole machine's NixOS configuration, takes the place of that cluster and the modules
  manifests =
    {
      pkgs,
      modules ? [ ],
      config ?
        (inputs.nixpkgs.lib.nixosSystem {
          modules =
            lib.attrValues self.nixosModules
            ++ [
              self.lib.checks.fixture
              { nixpkgs.hostPlatform = pkgs.stdenv.hostPlatform.system; }
            ]
            ++ modules;
        }).config,
      name ? "manifests",
    }:
    let
      pins = self.lib.pins.refs ../../.github/workflows/pins.yaml;
      pinned = self.lib.pins.locked ../../.github/pins.lock;
      # The JSON schemas of the Kubernetes minor the cluster runs, from the repository kubeconform reads them from by
      # default. Of its first patch release: the version is the consumer's k3s, from a nixpkgs that follows its own, and
      # keyed by the patch release a newer nixpkgs named a key pins.lock doesn't have
      schemas = "v${lib.versions.majorMinor config.homelab.cluster.kubernetesVersion}.0-standalone-strict";
      kubernetesSchemas = pinned "kubernetes-json-schema-${schemas}" pins."yannh/kubernetes-json-schema" (
        hash:
        pkgs.fetchFromGitHub {
          owner = "yannh";
          repo = "kubernetes-json-schema";
          rev = pins."yannh/kubernetes-json-schema";
          sparseCheckout = [ schemas ];
          inherit hash;
        }
      );
      inherit (self.lib.crds.pinned pkgs) gatewayAPI;
      manifests = config.homelab.cluster.payload;
      # What the node imports at start
      preloaded = pkgs.writeText "preloaded-images" (
        lib.concatMapStrings (i: "${i.imageName}:${i.imageTag}\n") (
          lib.filter (i: i ? imageName) config.homelab.cluster.images
        )
      );
    in
    pkgs.runCommand "check-${name}"
      {
        # What was checked, to look at when it fails
        passthru = {
          inherit manifests;
          inherit (config.homelab.cluster) imageLocks;
          sourceLocks = lib.recursiveUpdate config.homelab.cluster.sourceLocks {
            ${toString ../../.github/pins.lock} = lib.listToAttrs (
              map (pin: lib.nameValuePair pin.key pin.unlocked) [
                kubernetesSchemas
                gatewayAPI
              ]
            );
          };
        };
        nativeBuildInputs = [
          pkgs.kubeconform
          pkgs.yq-go
          (pkgs.python3.withPackages (p: [ p.pyyaml ]))
        ];
      }
      ''
        mkdir crds schemas
        for f in ${manifests}/*.yaml; do
          yq ea -N '(select(.kind == "List") | .items[]), select(.kind != "List")
            | select(.kind == "CustomResourceDefinition")' "$f" -s '"crds/" + .metadata.name + ".yaml"'
        done
        ${lib.concatImapStrings (
          i: crd: "cp ${crd} crds/runtime-${toString i}.yaml\n"
        ) config.homelab.cluster.runtimeCRDs}
        yq e -N 'select(.kind == "CustomResourceDefinition")' ${gatewayAPI.src} -s '"crds/" + .metadata.name + ".yaml"'
        (cd schemas && FILENAME_FORMAT='{fullgroup}-{kind}-{version}' \
          python3 ${pkgs.kubeconform.src}/scripts/openapi2jsonschema.py ../crds/*.yaml >/dev/null)
        # yannh's schemas leave out CustomResourceDefinition itself
        kubeconform -strict -summary -skip CustomResourceDefinition \
          -schema-location '${kubernetesSchemas.src}/${schemas}/{{.ResourceKind}}{{.KindSuffix}}.json' \
          -schema-location 'schemas/{{.Group}}-{{.ResourceKind}}-{{.ResourceAPIVersion}}.json' \
          ${manifests}/*.yaml
        # Every image comes preloaded from Nix, so nothing may be pulled
        pulled=$(yq e -N '(.items[]? // .)
          | select(.kind | test("^(Pod|Deployment|DaemonSet|StatefulSet|ReplicaSet|Job|CronJob)$"))
          | [.spec.jobTemplate.spec.template.spec, .spec.template.spec, .spec] | map(select(. != null)) | .[0]
          | (.containers // []) + (.initContainers // []) | .[] | .image' ${manifests}/*.yaml \
          | sort -u | grep -vxFf ${preloaded} || true)
        if [[ -n $pulled ]]; then
          printf "Not preloaded, so pulled at runtime:\n%s\n" "$pulled" >&2
          exit 1
        fi
        touch $out
      '';
  # Fails when a flake.lock has more than one node for a nixos-homelab repo. Two copies of one repo's modules declare
  # their options twice, which stops the eval deep in a trace; this names the inputs that bring each copy, so the
  # consumer can add the missing follows
  flakeLock =
    { pkgs, lockFile }:
    let
      inherit (lib.importJSON lockFile) nodes;
      homelab = lib.filterAttrs (_: node: (node.locked.owner or null) == "nixos-homelab") nodes;
      duplicates = lib.filterAttrs (_: keys: lib.length keys > 1) (
        lib.groupBy (key: homelab.${key}.locked.repo) (lib.attrNames homelab)
      );
      # The inputs locked to a node: "<node>.<input>", root being this flake
      owners =
        key:
        lib.concatLists (
          lib.mapAttrsToList (
            owner: node:
            lib.mapAttrsToList (input: _: "${owner}.${input}") (
              lib.filterAttrs (_: target: target == key) (node.inputs or { })
            )
          ) nodes
        );
      report = lib.concatStrings (
        lib.mapAttrsToList (
          repo: keys:
          "nixos-homelab/${repo} is locked ${toString (lib.length keys)} times:\n"
          + lib.concatMapStrings (
            key: "  ${homelab.${key}.locked.rev} through ${lib.concatStringsSep ", " (owners key)}\n"
          ) keys
        ) duplicates
      );
    in
    pkgs.runCommand "flake-lock" { inherit report; } (
      if duplicates == { } then
        "touch $out"
      else
        ''
          printf '%s' "$report" >&2
          echo 'Make all but one of each follow the flake input of that repo' >&2
          exit 1
        ''
    );
}
