{ lib, ... }:
{
  /**
    Build an executable shell script from `script`, with `getKubeSecret`
    and `setKubeSecret` helper functions available to it, and `kubectl`
    already pointed at the cluster via `KUBECONFIG`.

    `getKubeSecret <namespace> <name> <field>` prints the base64-decoded
    value of a field in a Kubernetes secret. `setKubeSecret <namespace>
    <name> <field> <value> [<field> <value> ...]` creates or updates a
    secret with the given field/value pairs.

    # Arguments

    `pkgs`: nixpkgs

    `script` (`String`): Shell script appended after the helpers are
    defined

    # Example

    ```nix
    setup-secrets = {
      sources.UNIFI_PASSWORD = {
        description = "Unifi password";
        cmd = setup-secrets.mkScript pkgs "getKubeSecret unifi unifi-credentials password";
      };
      destinations = [
        {
          logPrefix = "Unifi credentials";
          requires = [ "UNIFI_PASSWORD" ];
          cmd = setup-secrets.mkScript pkgs ''
            setKubeSecret unifi unifi-credentials password "''${UNIFI_PASSWORD:?}"
          '';
        }
      ];
    };
    ```
  */
  mkScript =
    pkgs: script:
    lib.getExe (
      pkgs.writeShellScriptBin "setup-secret-cmd.sh" ''
        set -eo pipefail
        export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
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
          local namespace=$1 name=$2 field=$3
          kubectl -n "$namespace" get secret "$name" -ogo-template="{{.data.$field | base64decode}}";
        }
        setKubeSecret() {
          local namespace=$1 name=$2 field value args=()
          shift; shift
          while [[ $# -gt 0 ]]; do
            field=$1
            value=$2
            shift; shift || { printf "Uneven number of arguments\n" >&2; return 1; }
            args+=("--from-literal=$field=$value")
          done
          kubectl create secret generic --dry-run=client -oyaml \
            -n "$namespace" "$name" "''${args[@]}" | \
            kubectl apply -f -;
        }
        ${script}
      ''
    );
}
