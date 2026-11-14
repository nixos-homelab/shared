# nixos-homelab-shared

Every other `nixos-homelab-*` repo takes this one as an input and builds
on its `cluster` module, the facts of the cluster, with a runner that
runs it: the `k3s` module, enabled. It also
provides shared services used across those repos: a dashboard, TLS, and
SSH-key access to the cluster. Databases and storage are in
[nixos-homelab-storage](https://github.com/nixos-homelab/storage).

See [the kubenix docs](https://nixos-homelab.github.io/shared/kubenix/)
for the typed resources and submodules of `homelab.kubernetes`, and
[the options reference](https://nixos-homelab.github.io/shared/options/) for the full list of module options.

## Setup

```nix
{
  inputs = {
    ...
    homelab-shared = {
      url = "github:nixos-homelab/shared";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ...
  };
}
```

```nix
{ inputs, ... }:
{
  imports = [ inputs.homelab-shared.nixosModules.k3s ];
  config.homelab.k3s.enable = true;
}
```

## Modules

- **cluster**: the shared `homelab.cluster.*` options every other module
  in this ecosystem builds on, whichever runner runs the cluster: IP
  families, pod/service CIDRs, debug tools, backup aggregation, the
  images to preload and the manifests to apply, and the facts the runner
  sets (kubeconfig, unit, Kubernetes version).
- **k3s**: runs the cluster on [k3s](https://k3s.io) (`homelab.k3s`): it
  imports `cluster`, preloads its images, applies its manifests, and
  drains the node at shutdown.
- **workloads**: the settings every workload shares (`homelab.workloads`:
  domain, gateway class, ACME issuer, pod user and group) and kubenix
  configuration in `homelab.kubernetes`, with the `workload` submodule --
  see [the kubenix docs](https://nixos-homelab.github.io/shared/kubenix/).
  `cluster` imports it and hands what it holds to the runner.
- **homepage**: the [homepage](https://gethomepage.dev) dashboard, with a
  per-service `integrations` allow-list.
- **cert-manager**: cert-manager plus a LibDNS ACME webhook, for
  automated TLS certificates.
- **k8sss**: deploys [k8sss](https://github.com/andsens/k8sss) for
  SSH-key-based `kubectl` access.
