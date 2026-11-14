{
  self,
  inputs,
  lib,
}:
{
  # Checks what a set of NixOS modules sends to k3s, on top of a cluster with this flake's modules, without running
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
              {
                nixpkgs.hostPlatform = pkgs.stdenv.hostPlatform.system;
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
                homelab.cluster = {
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
              }
            ]
            ++ modules;
        }).config,
      name ? "manifests",
    }:
    let
      pins = self.lib.pins.refs ../../.github/workflows/pins.yaml;
      pinned = self.lib.pins.locked ../../.github/pins.lock;
      # The JSON schemas of the Kubernetes version k3s runs, from the repository kubeconform reads them from by default
      schemas = "v${lib.head (lib.splitString "+" config.services.k3s.package.version)}-standalone-strict";
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
      inherit (self.lib.crds.pinned pkgs) cilium clusterNetworkPolicy gatewayAPI;
      manifests = config.homelab.cluster.payload;
      # What k3s imports at start (k3s' own airgap images aside, which carry no name)
      preloaded = pkgs.writeText "preloaded-images" (
        lib.concatMapStrings (i: "${i.imageName}:${i.imageTag}\n") (
          lib.filter (i: i ? imageName) config.services.k3s.images
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
                cilium
                clusterNetworkPolicy
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
        cp ${cilium.src}/pkg/k8s/apis/cilium.io/client/crds/v2/*.yaml ${clusterNetworkPolicy.src} crds/
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
}
