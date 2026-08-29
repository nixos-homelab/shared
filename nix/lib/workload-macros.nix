{ lib, ... }:
rec {
  /**
    Get the in-cluster hostname and port for a `WorkloadMacro` resource's
    Kubernetes Service, as `{ host; port; }`. The host is the
    `<name>.<namespace>` short form that's resolvable cluster-internally
    without the full `.svc.cluster.local` suffix; `namespace` falls back to
    `metadata.name` if `metadata.namespace` isn't set.

    # Arguments

    `workload`: A resource with `metadata.name` and `spec.ingressPort` (an
    `apiVersion = "cluster.local"; kind = "WorkloadMacro";` resource, as
    found at `config.kubetree.resources.<name>.<item>`)

    # Example

    ```nix
    workloadServiceHostPort {
      metadata = { name = "sonarr"; namespace = "media"; };
      spec.ingressPort = 8989;
    }
    => { host = "sonarr.media"; port = "8989"; }
    ```
  */
  workloadServiceHostPort = { metadata, spec, ... }: {
    host = "${metadata.name}.${lib.attrByPath [ "namespace" ] metadata.name metadata}";
    port = toString spec.ingressPort;
  };
  /**
    Get the in-cluster `http://` URL for a `WorkloadMacro` resource's
    Kubernetes Service.

    # Arguments

    `workload`: A resource with `metadata.name` and `spec.ingressPort` (see
    [`workloadServiceHostPort`](#libintegrationworkloadservicehostport))

    # Example

    ```nix
    workloadServiceUrl {
      metadata = { name = "sonarr"; namespace = "media"; };
      spec.ingressPort = 8989;
    }
    => "http://sonarr.media:8989"
    ```
  */
  workloadServiceUrl =
    workload:
    let
      hostPort = workloadServiceHostPort workload;
    in
    "http://${hostPort.host}:${hostPort.port}";
}
