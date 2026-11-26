{
  lib,
  writeShellApplication,
  coreutils,
  gatewayCRDs,
  findutils,
  gnugrep,
  iproute2,
  iptables,
  jq,
  k3s,
  kubectl,
  nix,
  util-linux,
}:
writeShellApplication {
  name = "dev-cluster";
  runtimeInputs = [
    coreutils
    findutils
    gnugrep
    iproute2
    iptables
    jq
    k3s
    kubectl
    nix
    util-linux
  ];
  runtimeEnv = {
    AIRGAP_IMAGES = k3s.passthru.airgap-images-amd64-tar-zst;
    CNI_PLUGINS = k3s.passthru.k3sCNIPlugins;
    GATEWAY_CRDS = gatewayCRDs;
    PAYLOAD_NIX = ./payload.nix;
  };
  text = lib.readFile ./dev-cluster.sh;
  # docopt assigns the variables in an eval, and its parser isn't nounset-safe
  excludeShellChecks = [ "SC2154" ];
  bashOptions = [
    "errexit"
    "pipefail"
  ];
  meta.platforms = [ "x86_64-linux" ];
}
