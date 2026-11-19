{ lib, ... }:
let
  /**
    Build an executable shell script from `script`, with `getKubeSecret`
    and `setKubeSecret` helper functions available to it, and `kubectl`
    already pointed at the cluster via `KUBECONFIG`.

    `getKubeSecret <namespace> <name> <field>` prints the base64-decoded
    value of a field in a Kubernetes secret. `setKubeSecret <namespace>
    <name> <field> <value> [<field> <value> ...]` creates or updates a
    secret with the given field/value pairs.

    Sources and destinations that talk to the cluster are best built with
    the helpers below, which put destinations in the `cluster` group (run
    after k3s, see the k3s module) and retry while the cluster comes up.

    # Arguments

    `pkgs`: nixpkgs

    `script` (`String`): Shell script appended after the helpers are
    defined

    # Example

    ```nix
    setup-secrets.sources.UNIFI_PASSWORD = {
      description = "Unifi password";
      cmd = setup-secrets.mkScript pkgs "getKubeSecret unifi unifi-credentials password";
    };
    ```
  */
  mkScript =
    pkgs: script:
    lib.getExe (
      pkgs.writeShellScriptBin "setup-secret-cmd.sh" ''
        set -eo pipefail
        export KUBECONFIG=/etc/kubernetes/kubeconfig
        PATH=${
          lib.makeBinPath [
            pkgs.coreutils
            pkgs.curl
            pkgs.gnugrep
            pkgs.gnused
            pkgs.kubectl
          ]
        }
        getKubeSecret() {
          local namespace=$1 name=$2 field=$3 value
          # kubectl prints a failed template to stdout, the whole object included, so nothing of a failed run may
          # reach the caller's value (`getKubeSecret ... || wg genkey`), where errexit doesn't apply
          value=$(kubectl -n "$namespace" get secret "$name" -ogo-template="{{.data.$field | base64decode}}") || return
          printf '%s\n' "$value"
        }
        setKubeSecret() {
          local namespace=$1 name=$2 field value manifest
          shift; shift
          # Values go through pipes only: on kubectl's argv any local user could read them
          manifest=$(printf 'apiVersion: v1\nkind: Secret\nmetadata: {name: "%s", namespace: "%s"}\ndata:\n' "$name" "$namespace")
          while [[ $# -gt 0 ]]; do
            field=$1
            value=$2
            shift; shift || { printf "Uneven number of arguments\n" >&2; return 1; }
            manifest+=$(printf '\n  "%s": %s' "$field" "$(printf '%s' "$value" | base64 -w0)")
          done
          kubectl apply -f - <<<"$manifest";
        }
        ${script}
      ''
    );

  # How long a cluster command may take and how often it is tried again: k3s answers a while after its unit is
  # active, and a workload a while after that
  clusterAttempts = {
    timeout = "60s";
    retries = 5;
  };
in
{
  inherit mkScript;

  /**
    A setup-secrets source that reads one field of a Kubernetes Secret.

    With `generate`, a missing Secret or a missing field makes a new value
    from that shell command in place of failing; an API that doesn't
    answer still fails the source, so a value is never replaced because
    the cluster was down.

    # Arguments

    `pkgs`: nixpkgs

    An attribute set:
    - `description` (`String`): shown in the form
    - `namespace`, `name`, `field` (`String`): the Secret and its field
    - `generate` (`String`, optional): shell command that prints a new value

    # Example

    ```nix
    setup-secrets.sources.APP_PASSWORD = setup-secrets.kubeSecretSource pkgs {
      description = "App password";
      namespace = "app";
      name = "app-secrets";
      field = "password";
      generate = "head -c 1024 /dev/urandom | tr -dc A-Za-z0-9 | head -c 32";
    };
    ```
  */
  kubeSecretSource =
    pkgs:
    {
      description,
      namespace,
      name,
      field,
      generate ? null,
    }:
    clusterAttempts
    // {
      inherit description;
      cmd = mkScript pkgs (
        if generate == null then
          "getKubeSecret ${
            lib.escapeShellArgs [
              namespace
              name
              field
            ]
          }"
        else
          ''
            # Empty for a missing Secret (--ignore-not-found) or a missing field, a failure when the API doesn't answer
            value=$(kubectl -n ${lib.escapeShellArg namespace} get secret ${lib.escapeShellArg name} --ignore-not-found \
              -ogo-template=${lib.escapeShellArg ''{{with index .data "${field}"}}{{.}}{{end}}''})
            if [[ -n $value ]]; then
              base64 -d <<<"$value"
            else
              ${generate}
            fi
          ''
      );
    };

  /**
    A setup-secrets source that runs a command in a container of a
    workload, after waiting for the workload to roll out, for values a
    workload makes itself (an API key in its configuration). It reads
    something setup-secrets never writes, so the value can only be changed
    in the workload.

    # Arguments

    `pkgs`: nixpkgs

    An attribute set:
    - `description` (`String`): shown in the form
    - `namespace`, `workload` (`String`): `workload` as kubectl takes it, `deploy/sonarr`
    - `container` (`String`)
    - `command` (`String`): shell words passed to `kubectl exec`, quoted as needed

    # Example

    ```nix
    setup-secrets.sources.SONARR_API_KEY = setup-secrets.kubeExecSource pkgs {
      description = "Sonarr API Key";
      namespace = "sonarr";
      workload = "deploy/sonarr";
      container = "sonarr";
      command = "xq -q 'Config>ApiKey' /data/config.xml";
    };
    ```
  */
  kubeExecSource =
    pkgs:
    {
      description,
      namespace,
      workload,
      container,
      command,
    }:
    {
      inherit description;
      # Long enough for the rollout to finish within one try
      timeout = "150s";
      retries = 2;
      cmd = mkScript pkgs ''
        kubectl -n ${lib.escapeShellArg namespace} rollout status ${lib.escapeShellArg workload} --timeout=120s >&2
        kubectl exec -n ${lib.escapeShellArg namespace} -c ${lib.escapeShellArg container} ${lib.escapeShellArg workload} -- \
          ${command}
      '';
    };

  /**
    A setup-secrets destination that writes one Kubernetes Secret, in the
    `cluster` group.

    # Arguments

    `pkgs`: nixpkgs

    An attribute set:
    - `logPrefix` (`String`)
    - `namespace`, `name` (`String`): the Secret
    - `data` (`AttrsOf String`): field of the Secret to the source whose value it gets; every source is required
    - `enable` (`Bool`, default `true`)

    # Example

    ```nix
    setup-secrets.destinations = [
      (setup-secrets.kubeSecretDestination pkgs {
        logPrefix = "Unifi credentials";
        namespace = "unifi";
        name = "unifi-credentials";
        data.password = "UNIFI_PASSWORD";
      })
    ];
    ```
  */
  kubeSecretDestination =
    pkgs:
    {
      logPrefix,
      namespace,
      name,
      data,
      enable ? true,
    }:
    clusterAttempts
    // {
      inherit enable logPrefix;
      group = "cluster";
      requires = lib.unique (lib.attrValues data);
      cmd = mkScript pkgs ''
        setKubeSecret ${
          lib.escapeShellArgs [
            namespace
            name
          ]
        } \
          ${lib.concatStringsSep " \\\n  " (
            lib.mapAttrsToList (field: source: ''${lib.escapeShellArg field} "''${${source}:?}"'') data
          )}
      '';
    };

  /**
    A setup-secrets destination in the `cluster` group with a script of its
    own, for what `kubeSecretDestination` doesn't cover (several Secrets,
    a value derived in the script).

    # Arguments

    `pkgs`: nixpkgs

    An attribute set:
    - `logPrefix` (`String`)
    - `requires`, `wants` (`ListOf String`, default `[ ]`)
    - `script` (`String`): run through `mkScript`
    - `enable` (`Bool`, default `true`)
  */
  clusterDestination =
    pkgs:
    {
      logPrefix,
      script,
      requires ? [ ],
      wants ? [ ],
      enable ? true,
    }:
    clusterAttempts
    // {
      inherit
        enable
        logPrefix
        requires
        wants
        ;
      group = "cluster";
      cmd = mkScript pkgs script;
    };
}
