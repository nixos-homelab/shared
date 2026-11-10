{
  lib,
  writeShellApplication,
  findutils,
  gawk,
  jq,
  nix-prefetch-docker,
}:
writeShellApplication {
  name = "lock-images";
  runtimeInputs = [
    findutils
    gawk
    jq
    nix-prefetch-docker
  ];
  text = lib.readFile ./lock-images.sh;
}
