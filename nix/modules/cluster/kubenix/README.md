# kubenix

`homelab.kubernetes` takes [kubenix](https://github.com/hall/kubenix)
configuration of the cluster: typed Kubernetes resources, so a misspelled
field fails at evaluation and names where it was set. Each submodule
instance goes to k3s as a manifest of its own, named after the instance;
the other objects go to the manifest `kubenix`. It runs next to the
[workload macros](https://nixos-homelab.github.io/shared/workload-macros/) while workloads move over.

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
