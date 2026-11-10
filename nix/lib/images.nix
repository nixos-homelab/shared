{ lib, ... }:
{
  /**
    The upstream images pinned in a Dockerfile, as image archives for
    `services.k3s.images`. Dependabot bumps the `FROM name:tag@digest`
    lines; their Nix hashes are in `images.lock` next to the Dockerfile,
    which `nix run github:nixos-homelab/shared#lock-images` updates. The
    tag gets the digest's first 12 hex digits, so a bump changes the pod
    spec and rolls the workload. Each archive's `ref` is its `name:tag`.

    # Arguments

    `pkgs`: nixpkgs

    `dockerfile` (`Path`): Dockerfile with one `FROM` line per image

    # Example

    ```nix
    let
      redis = (images.pinned pkgs ./Dockerfile).redis;
    in
    {
      services.k3s.images = [ redis ];
      # ...
      image = redis.ref;
      imagePullPolicy = "Never";
    }
    ```
  */
  pinned =
    pkgs: dockerfile:
    let
      lockFile = dirOf dockerfile + "/images.lock";
      lock = lib.importJSON lockFile;
      pins = lib.filter (pin: pin != null) (
        map (builtins.match "FROM ([^ :@]+):([^ @]+)@(sha256:[0-9a-f]{64}).*") (
          lib.splitString "\n" (builtins.readFile dockerfile)
        )
      );
      pull =
        pin:
        let
          name = lib.elemAt pin 0;
          digest = lib.elemAt pin 2;
          key = "${name}@${digest}";
          tag = "${lib.elemAt pin 1}-${builtins.substring 7 12 digest}";
        in
        lib.nameValuePair name (
          pkgs.dockerTools.pullImage {
            imageName = name;
            imageDigest = digest;
            finalImageTag = tag;
            hash = lock.${key} or (throw "${key} isn't in ${toString lockFile}, run lock-images");
          }
          // {
            ref = "${name}:${tag}";
          }
        );
    in
    lib.listToAttrs (map pull pins);
}
