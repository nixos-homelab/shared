# kubenix

`homelab.kubernetes` takes [kubenix](https://github.com/hall/kubenix)
configuration of the cluster: typed Kubernetes resources, so a misspelled
field fails at evaluation and names where it was set. Each submodule
instance goes to k3s as a manifest of its own, named after the instance;
the other objects go to the manifest `kubenix`. It runs next to the
[workload macros](https://nixos-homelab.github.io/shared/workload-macros/) while workloads move over.

## Custom resources

The custom resources are typed too, from the CRDs:
[`lib.crd2types.customTypes`](https://nixos-homelab.github.io/shared/lib/) turns a
CustomResourceDefinition into kubenix `customTypes`, at evaluation, so a
bump of a CRD retypes its resources. The cluster has Gateway API's
experimental channel, Cilium's and ClusterNetworkPolicy, as pinned in
`lib.crds.pinned`; the cert-manager module adds those of its chart. Every
submodule gets them. Their attribute names are kubenix's: the plural cased
like the kind (`gateways`, `hTTPRoutes`, `ciliumNetworkPolicies`,
`certificates`, `clusterIssuers`). Optional fields default to null and are
left out; value validations (patterns, bounds, CEL rules) stay with the
API server. A list the CRD merges by one key takes an attribute set by
that key, like the lists kubenix keys in its core types: Gateway
listeners by `name`, so an instance changes one listener of its Gateway
(`mkForce` where the workload sets the field already):

```nix
homelab.kubernetes.submodules.instances.grafana.config.kubernetes.resources.gateways.grafana.spec.listeners.grafana.port =
  lib.mkForce 8443;
```

A list still works there; its items keep their order, ahead of those
given by key. A CRD that starts using a schema construct crd2types doesn't
know fails evaluation, naming where.

```nix
homelab.kubernetes.kubernetes.resources.certificates.plex = {
  metadata.namespace = "plex";
  spec = {
    secretName = "plex-tls";
    dnsNames = [ "plex.example.org" ];
    issuerRef = { kind = "ClusterIssuer"; name = "letsencrypt-production"; };
  };
};
```

A module adds the types of a CRD it installs to
`homelab.kubernetes.kubernetes.customTypes`. Cluster-scoped resources
need `metadata.namespace = null`.

## workload

A long-running workload: a Namespace and a Deployment named after the
instance, and depending on the args a PersistentVolumeClaim, a Service and
a Gateway with its HTTPRoutes.

```nix
homelab.kubernetes.submodules.instances.grafana = {
  submodule = "workload";
  args = {
    allowEgress = [ "internet" "mimir" "postgresql" ];
    dataPath = "/var/lib/grafana";
    ingressPort = 3000;
    ports.web = 3000;
    container = {
      image = "grafana:latest";
      env = [ { name = "GF_PATHS_DATA"; value = "/var/lib/grafana"; } ];
    };
  };
};
```

- `container`: the main container, named after the instance, as kubenix's
  Container type. It's locked down by default
  (`allowPrivilegeEscalation = false`, read-only root filesystem, all
  capabilities dropped, `NET_BIND_SERVICE` added when it has ports); set
  `securityContext.capabilities.add` for more.
- `ports`: the container ports by name, a port number or
  `{ containerPort; protocol; }`. They also make the Service, with the
  same names.
- `dataPath`: a 1Gi PersistentVolumeClaim named after the workload,
  mounted here in the main container.
- `ingressPort`: a Gateway at `<gateway.subdomain>.<gateway.domain>`
  (the bare domain when `gateway.subdomain = null`) routing to this
  Service port, with a redirect from HTTP; allows ingress from `gateway`.
  `httpRouteRules` go ahead of the catch-all rule.
- `allowIngress`/`allowEgress`: the pod labels
  `cluster.local/<workload>-ingress`/`-egress: allow`, for the label
  selectors of the network policies.

The workload holds no network policies of its own. The module of the CNI
adds them to every instance through `submodules.defaults`: with `ports`,
[networking's
cilium](https://github.com/nixos-homelab/networking/blob/main/nix/modules/cilium/README.md)
lets pods labeled `cluster.local/<workload>-egress: allow` reach them. The
manifests check, which has no CNI, expands the same intent into a
NetworkPolicy and a ClusterNetworkPolicy.
- `securityContext`: `runAsUser`, `runAsGroup` (also the `fsGroup`) and
  `supplementalGroups` of the pod. They default to
  `kubetree.workload-macros.securityContext`, as `gateway.domain`,
  `gateway.className` and `gateway.issuer` default to the `domain`,
  `gatewayClassName` and `acmeProvider` there.

Anything else goes on the instance `config`, where the objects are
kubenix resources. Lists kubenix keys by name (containers, volumes, ports)
take attribute sets:

```nix
homelab.kubernetes.submodules.instances.unifi.config.kubernetes.resources = {
  services.unifi.spec.type = "LoadBalancer";
  deployments.unifi.spec.template.spec.volumes.config.hostPath.path = "/srv/unifi";
};
```

`pod-spec.nix` holds the main container and the pod security context for
every submodule that runs pods; `submodules.defaults` with
`features = [ "pod-spec" ]` reaches all of them.
