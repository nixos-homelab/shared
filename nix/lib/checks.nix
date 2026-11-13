{
  self,
  inputs,
  lib,
}:
let
  transform = inputs.kubetree.lib.transform;
  # Without a CNI module (networking's cilium) to expand them, NetpolMacro and toPortsFlattened stay as they are, which
  # isn't valid Kubernetes. This expands them CNI-neutrally, into a NetworkPolicy and a ClusterNetworkPolicy, so the
  # manifests can be checked. It's for the check only: nothing deploys it
  networkPolicies =
    { config, ... }:
    let
      toPorts = map (p: if builtins.isInt p then { port = p; } else p);
      transformNetpolMacro =
        cfg: resource:
        let
          inherit (transform.mkResourceHelper resource) dotPath;
          name = dotPath "metadata.name" (throw "You must specify metadata.name");
          namespace = dotPath "metadata.namespace" name;
          ports = toPorts (dotPath "spec.ports" [ ]);
          egressLabel = "cluster.local/${name}-egress";
        in
        {
          apiVersion = "v1";
          kind = "List";
          items = [
            {
              apiVersion = "networking.k8s.io/v1";
              kind = "NetworkPolicy";
              metadata = {
                name = "${name}-from-pod";
                inherit namespace;
              };
              spec = {
                podSelector.matchLabels."app.kubernetes.io/name" = name;
                policyTypes = [ "Ingress" ];
                ingress = [
                  {
                    from = [
                      {
                        namespaceSelector = { };
                        podSelector.matchLabels.${egressLabel} = "allow";
                      }
                    ];
                    ports = map (p: {
                      inherit (p) port;
                      protocol = p.protocol or "TCP";
                    }) ports;
                  }
                ];
              };
            }
            {
              apiVersion = "policy.networking.k8s.io/v1alpha2";
              kind = "ClusterNetworkPolicy";
              metadata.name = "pod-to-${name}";
              spec = {
                # Allows what namespaced policies don't deny, like Cilium's clusterwide policies
                tier = "Baseline";
                priority = 500;
                subject.pods = {
                  namespaceSelector = { };
                  podSelector.matchLabels.${egressLabel} = "allow";
                };
                egress = [
                  (
                    {
                      name = "to-${name}";
                      action = "Accept";
                      to = [
                        {
                          pods = {
                            namespaceSelector.matchLabels."kubernetes.io/metadata.name" = namespace;
                            podSelector.matchLabels."app.kubernetes.io/name" = name;
                          };
                        }
                      ];
                    }
                    // lib.optionalAttrs (ports != [ ]) {
                      protocols = map (p: {
                        ${lib.toLower (p.protocol or "TCP")}.destinationPort.number = p.port;
                      }) ports;
                    }
                  )
                ];
              };
            }
          ];
        };
      # Cilium's nested toPorts, from a flat list of ports, as networking's cilium module does it
      transformToPortsFlattened =
        cfg: resource:
        let
          ports = map (p: {
            port = toString p.port;
            protocol = p.protocol or "TCP";
          }) (toPorts (resource.toPortsFlattened or [ ]));
        in
        removeAttrs resource [ "toPortsFlattened" ]
        // lib.optionalAttrs (ports != [ ]) {
          toPorts = (resource.toPorts or [ ]) ++ [ { inherit ports; } ];
        };
      rules = {
        ingress."[]"._transformers = [ transformToPortsFlattened ];
        egress."[]"._transformers = [ transformToPortsFlattened ];
      };
      # The same for the policies of kubenix pods, which networking's cilium module adds when Cilium runs
      podPolicies =
        {
          lib,
          name,
          args,
          config,
          ...
        }:
        let
          inherit (config.kubernetes) namespace;
          ports = map (
            n:
            let
              p = args.ports.${n};
            in
            {
              port = p.containerPort;
              protocol = if p.protocol == null then "TCP" else p.protocol;
            }
          ) args.policyPorts;
          egressLabel = "cluster.local/${name}-egress";
        in
        {
          kubernetes.resources = lib.mkIf (ports != [ ]) {
            networkPolicies."${name}-from-pod".spec = {
              podSelector.matchLabels."app.kubernetes.io/name" = name;
              policyTypes = [ "Ingress" ];
              ingress = [
                {
                  from = [
                    {
                      namespaceSelector = { };
                      podSelector.matchLabels.${egressLabel} = "allow";
                    }
                  ];
                  inherit ports;
                }
              ];
            };
            clusterNetworkPolicies."pod-to-${name}" = {
              metadata.namespace = null;
              spec = {
                tier = "Baseline";
                priority = 500;
                subject.pods = {
                  namespaceSelector = { };
                  podSelector.matchLabels.${egressLabel} = "allow";
                };
                egress = [
                  {
                    name = "to-${name}";
                    action = "Accept";
                    to = [
                      {
                        pods = {
                          namespaceSelector.matchLabels."kubernetes.io/metadata.name" = namespace;
                          podSelector.matchLabels."app.kubernetes.io/name" = name;
                        };
                      }
                    ];
                    protocols = map (p: { ${lib.toLower p.protocol}.destinationPort.number = p.port; }) ports;
                  }
                ];
              };
            };
          };
        };
    in
    {
      config.homelab.kubernetes.submodules.defaults = lib.mkIf (!(config.homelab.cilium.enable or false)) [
        {
          features = [ "pod-spec" ];
          default = podPolicies;
        }
      ];
      config.kubetree.transformers = lib.mkIf (!(config.kubetree.cilium.enable or false)) {
        "cluster.local".NetpolMacro._transformers = [
          transformNetpolMacro
          transform.transformResource
          transform.flattenResourceList
        ];
        "cilium.io" = {
          CiliumClusterwideNetworkPolicy.spec = rules;
          CiliumNetworkPolicy.spec = rules;
        };
      };
    };
in
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
              networkPolicies
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
                kubetree.workload-macros = {
                  acmeProvider = "letsencrypt-staging";
                  gatewayClassName = "example";
                };
                homelab.cluster = {
                  enable = true;
                  domain = "example.org";
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
      manifests = config.kubetree.k3s.payload.manifests;
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
