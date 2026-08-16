# Workload macros

`kubetree.resources` accepts custom resource kinds
(`apiVersion = "cluster.local"`) that expand into the real Kubernetes and
Gateway API resources a workload needs, so you don't hand-write a
Deployment, Service, NetworkPolicy and Gateway for every service.

Where a macro maps to one real resource (`DeploymentMacro` →
`Deployment`, `CronJobMacro` → `CronJob`, `ServiceMacro` → `Service`,
`podSpecMacro` → a Pod spec, etc.), it decorates rather than replaces:
only `podSpecMacro`/`allowIngress`/`allowEgress` (plus
`dataPath`/`ingressPort` on `WorkloadMacro`) are intercepted and lifted
into place. Everything else in `spec` passes straight through untouched,
as the real Kind's own field. `GatewayMacro` is the one exception -- see
below.

## WorkloadMacro

The usual entry point. Expands into a `Namespace`, a `DeploymentMacro`
carrying the pod spec, and -- depending on what's set -- a
`PersistentVolumeClaim`, a `ServiceMacro` + `NetpolMacro`, and a
`GatewayMacro`.

```nix
kubetree.resources.grafana.workload = {
  apiVersion = "cluster.local";
  kind = "WorkloadMacro";
  metadata.name = "grafana";
  spec = {
    allowEgress = [ "internet" "mimir" "postgresql" ];
    allowIngress = [ "gateway" ];
    dataPath = "/var/lib/grafana";
    podSpecMacro.mainContainer = {
      image = "grafana:latest";
      portsByName.web = 3000;
    };
  };
};
```

- `dataPath`: provisions a 1Gi `PersistentVolumeClaim`, mounted here in
  the main container.
- `ingressPort`: exposes the workload via `GatewayMacro` on this port, and
  adds `"gateway"` to `allowIngress`.

Container ports declared under `podSpecMacro.mainContainer.portsByName`
also get a `ServiceMacro` and a `NetpolMacro` automatically -- the latter
implemented in [homelab-networking's Cilium
module](https://github.com/nixos-homelab/networking/blob/main/docs/cilium.md).

## DeploymentMacro / DaemonSetMacro / CronJobMacro / JobMacro

What `WorkloadMacro` expands into internally. Use these directly for a
DaemonSet/CronJob/Job, or to skip `WorkloadMacro`'s extras (PVC, Service,
Gateway).

```nix
kubetree.resources.zfs-exporter.daemonset = {
  apiVersion = "cluster.local";
  kind = "DaemonSetMacro";
  metadata.name = "zfs-exporter";
  spec.podSpecMacro = {
    name = "zfs-exporter";
    mainContainer = {
      image = "zfs-exporter:latest";
      addCapabilities = [ "SYS_RAWIO" ];
      portsByName.metrics = 9134;
      volumeMountsByPath."/dev" = "dev";
    };
    volumesByName.dev.hostPath = { path = "/dev"; type = "Directory"; };
  };
};
```

`CronJobMacro` and `JobMacro` default to `restartPolicy = "OnFailure"`:

```nix
kubetree.resources.imap-backup.cronJob = {
  apiVersion = "cluster.local";
  kind = "CronJobMacro";
  metadata.name = "imap-backup";
  spec = {
    schedule = "0 3 * * *";
    allowEgress = [ "internet" ];
    podSpecMacro.mainContainer.image = "imap-backup:latest";
  };
};
```

## podSpecMacro

The shorthand pod spec embedded in the workload macros above.
`mainContainer` becomes the container named after the workload, locked
down by default (`allowPrivilegeEscalation = false`, read-only root
filesystem, all capabilities dropped except `addCapabilities`, plus
`NET_BIND_SERVICE` if any ports are declared). `securityContext`
(`runAsUser`/`runAsGroup`/`fsGroup`/`supplementalGroups`) comes from
`kubetree.workloadMacros.securityContext` unless overridden.

`initContainersByName` and `volumesByName` work the same as on a real pod
spec (see [kubetree's Kubernetes primitives
docs](https://github.com/andsens/nix-kubetree/blob/main/docs/transformers/kubernetes.md)).

`allowIngress`/`allowEgress` become
`cluster.local/<workload>-ingress`/`-egress: allow` pod labels, for
Cilium label-selector network policies.

## ServiceMacro

Expands into a `v1 Service` selecting the workload by name. Everything
else (`spec.portsByName`, etc.) passes through.

```nix
kubetree.resources.node-exporter.service = {
  apiVersion = "cluster.local";
  kind = "ServiceMacro";
  metadata.name = "node-exporter";
  spec.portsByName.metrics = 9100;
};
```

## GatewayMacro

Exposes `spec.port` externally at
`<subdomain-or-name>.<kubetree.workloadMacros.domain>` (or just the bare
domain if `spec.subdomain = null;`). Expands into a `Gateway` (HTTPS with
TLS terminated via `kubetree.workloadMacros.acmeProvider`, plus a
cleartext HTTP listener) and two `HTTPRoute`s: one forwarding HTTPS
traffic to `spec.port`, and one redirecting the cleartext listener to
HTTPS. Only the fields listed here are accepted -- unlike the other
macros, nothing else passes through.

```nix
kubetree.resources.grafana.gateway = {
  apiVersion = "cluster.local";
  kind = "GatewayMacro";
  metadata.name = "grafana";
  spec.port = 3000;
  spec.requestHeaderModifier.add = [
    { name = "X-WEBAUTH-USER"; value = "admin"; }
  ];
};
```

`spec.requestHeaderModifier` is optional and gets attached to the HTTPS
route as a `RequestHeaderModifier` filter.

## ScriptMacro

Runs `spec.script` as a one-off Kubernetes Job. Expands into a `ConfigMap`
holding the script and a `JobMacro` that mounts and runs it with
`kubetree.workloadMacros.containerUtils`; the mount path is derived from a
hash of the script's content, so the Job re-runs whenever the script
changes.

```nix
kubetree.resources.prowlarr."sonarr-integration" = {
  apiVersion = "cluster.local";
  kind = "ScriptMacro";
  metadata.namespace = "prowlarr";
  metadata.name = "integrate-sonarr";
  spec.script = ''
    curl -sfX POST "$PROWLARR_URL/api/v1/applications" -d '{"name":"Sonarr"}'
  '';
};
```
