{
  lib,
  writeShellApplication,
  findutils,
  gawk,
  jq,
  nix-prefetch-docker,
  skopeo,
}:
writeShellApplication {
  name = "lock-images";
  runtimeInputs = [
    findutils
    gawk
    jq
    nix-prefetch-docker
    skopeo
  ];
  text = lib.readFile ./lock-images.sh;
  # docopt assigns the variables in an eval, and its parser isn't nounset-safe
  excludeShellChecks = [ "SC2154" ];
  bashOptions = [
    "errexit"
    "pipefail"
  ];
}
