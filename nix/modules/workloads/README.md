# kubenix

The `workloads` module holds the settings every workload shares, in
`homelab.workloads` (`domain`, `gatewayClassName`, `acmeProvider`,
`containerUtils`, `securityContext`), and the submodules below.
`homelab.kubernetes` takes [kubenix](https://github.com/hall/kubenix)
configuration of the cluster: typed Kubernetes resources, so a misspelled
field fails at evaluation and names where it was set. Each submodule
instance goes to k3s as a manifest of its own, named after the instance;
the other objects go to the manifest `kubenix`.

## Custom resources

The custom resources are typed too, from the CRDs:
[`lib.crd2types.customTypes`](https://nixos-homelab.github.io/shared/lib/) turns a
CustomResourceDefinition into kubenix `customTypes`, at evaluation, so a
bump of a CRD retypes its resources. This module types Gateway API's
experimental channel, as pinned in `lib.crds.pinned`; the cert-manager
module adds those of its chart, and the module of the CNI its own
(networking's `cilium-crds`). Every submodule gets them. Their attribute names are kubenix's: the plural cased
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
- `policyPorts`: the names of the `ports` other pods may reach, all of
  them by default; see below.
- `apiServerPorts`, `worldPorts`: the names of the `ports` the API server
  and the world outside the cluster may reach, none by default.
- `allowIngress`/`allowEgress`: the pod labels
  `cluster.local/<workload>-ingress`/`-egress: allow`, for the label
  selectors of the network policies.

The workload holds no network policies of its own, only this intent
(`policy.nix`). The module of the CNI turns it into policies for every
instance with the feature `pod-policy` through `submodules.defaults`:
[networking's
cilium](https://github.com/nixos-homelab/networking/blob/main/nix/modules/cilium/README.md)
lets pods labeled `cluster.local/<workload>-egress: allow` reach the
`policyPorts`, and so on. Without a CNI module there are none.
- `securityContext`: `runAsUser`, `runAsGroup` (also the `fsGroup`) and
  `supplementalGroups` of the pod. They default to
  `homelab.workloads.securityContext`, as `gateway.domain`,
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

## deployment, daemonset, job, cronjob, script

The pod alone, in the resource that runs it, named after the instance:
`container`, `ports`, `policyPorts`, `apiServerPorts`, `worldPorts`,
`allowIngress`, `allowEgress` and `securityContext` as in the workload, with no Namespace or Service. A Deployment
is recreated on change; the pod of a Job or CronJob isn't restarted
unless the instance sets `restartPolicy`. `cronjob` takes the `schedule`.

`script` runs a bash `script` once: a ConfigMap and a Job, the script
mounted at a path hashed from it, so a changed script changes the pod
template of the Job, k3s replaces the Job and it runs again. It runs in
`image`, the container-utils of the cluster unless set.

```nix
homelab.kubernetes.submodules.instances.backup-grafana-db = {
  submodule = "cronjob";
  args = {
    schedule = "10 3 * * *";
    allowEgress = [ "postgresql" ];
    container = {
      image = "postgresql:latest";
      command = [ "pg_dump" "--file=/dumps/grafana.pgdump" ];
      volumeMounts."/dumps".name = "dumps";
    };
  };
  config.kubernetes.resources.cronJobs.backup-grafana-db.spec.jobTemplate.spec.template.spec.volumes.dumps.persistentVolumeClaim.claimName =
    "database-dumps";
};
```

## service

A Service named after the instance, selecting the pods named so. `ports`
by name: a port number, or the fields of a ServicePort.

```nix
homelab.kubernetes.submodules.instances.alloy = {
  submodule = "service";
  args.ports.web = 3000;
};
```

## pods

The policy intent of pods something else runs (a release, a static
manifest, another module): `ports`, `policyPorts`, `apiServerPorts` and
`worldPorts` as in the workload, for the pods with the labels `selector`
in the namespace of the instance, `app.kubernetes.io/name` of the
instance name unless set. It writes no objects; the CNI module adds the
policies as for any pod.

```nix
homelab.kubernetes.submodules.instances.cert-manager.config.submodules.instances.webhook = {
  name = "cert-manager-webhook";
  submodule = "pods";
  args = {
    selector = {
      "app.kubernetes.io/name" = "webhook";
      "app.kubernetes.io/instance" = "cert-manager";
    };
    ports.https = 10250;
    apiServerPorts = [ "https" ];
  };
};
```

## manifest

Objects that go to k3s together: the resources on the instance `config`
and the instances nested in it. Every top-level instance is one k3s
manifest, and k3s deletes what a manifest stops holding. An object that
moves to another manifest is deleted when k3s applies the old manifest
first, and a Namespace or a PersistentVolumeClaim takes what it holds
with it. So objects that went to k3s together stay in one `manifest`,
under the old name.

```nix
homelab.kubernetes.submodules.instances.cert-manager = {
  submodule = "manifest";
  config = {
    kubernetes.resources.namespaces.cert-manager.metadata.namespace = null;
    submodules.instances = {
      webhook = {
        name = "cert-manager-webhook-libdns";
        submodule = "deployment";
        args.container.image = "cert-manager-webhook-libdns:latest";
      };
      webhook-service = {
        name = "cert-manager-webhook-libdns";
        submodule = "service";
        args.ports.https = { port = 443; targetPort = 8443; };
      };
    };
  };
};
```

All submodules, `workload` and `manifest` included, put their objects in the namespace of
the instance they're nested in, or the one named after the instance at the
top; set `config.kubernetes.namespace` for another. Two nested instances
whose objects share a name, like a Deployment and the Service in
front of it, take keys
of their own and the object name as `name`.
