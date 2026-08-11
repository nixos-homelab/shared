{ lib, ... }:
{
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
