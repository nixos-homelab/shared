# nixos-homelab-shared

Every other `nixos-homelab-*` repo takes this one as an input and
requires its `cluster` module -- which bootstraps k3s and
[kubetree](https://github.com/andsens/nix-kubetree) -- enabled. It also
provides shared services used across those repos: a database, a
dashboard, TLS, and storage.

See the [workload macros docs](https://nixos-homelab.github.io/shared/workload-macros/) for the custom
resource kinds `kubetree.resources` accepts, and
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
  imports = [
    inputs.homelab-shared.nixosModules.cluster
    inputs.homelab-shared.nixosModules.postgresql
  ];
  config.homelab.cluster.enable = true;
}
```

## Modules

- **cluster**: bootstraps k3s and `kubetree`, and provides the shared
  `homelab.cluster.*` options (pod/service CIDRs, debug tools, backup
  aggregation) every other module in this ecosystem builds on.
- **workload-macros**: the `WorkloadMacro`/`DeploymentMacro`/etc. resource
  kinds -- see [the workload macros docs](https://nixos-homelab.github.io/shared/workload-macros/).
- **homepage**: the [homepage](https://gethomepage.dev) dashboard, with a
  per-service `integrations` allow-list.
- **cert-manager**: cert-manager plus a LibDNS ACME webhook, for
  automated TLS certificates.
- **postgresql**: a shared PostgreSQL instance with declarative database
  creation and backups.
- **redis**: a shared Redis instance with a database-index registry, to
  keep workloads from colliding on the same DB number.
- **nfs-provisioner**: a dynamic PersistentVolume provisioner backed by
  an NFS export.
- **smb**: Samba file sharing, with per-user passwords set up through
  `setup-secrets`.
- **k8sss**: deploys [k8sss](https://github.com/andsens/k8sss) for
  SSH-key-based `kubectl` access.
