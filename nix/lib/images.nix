{ lib, ... }:
rec {
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

  /**
    Image archives for refs that something upstream names (a chart, another
    module), locked to a digest and hash in `lockFile`, which
    `lock-images --lock FILE REF...` writes. Returns the archives for
    `services.k3s.images` and `refFor`, which maps each ref to its archive's
    `name:tag` (the tag suffixed with the digest's first 12 hex digits).

    # Arguments

    `pkgs`: nixpkgs

    `lockFile` (`Path`): JSON of ref to `{ digest, hash }`

    `refs` (`[String]`): image refs, with or without a digest
  */
  locked =
    pkgs: lockFile: refs:
    let
      lock = lib.importJSON lockFile;
      pull =
        ref:
        let
          entry = lock.${ref} or (throw "${ref} isn't in ${toString lockFile}, run lock-images --lock");
          parts = builtins.match "([^@]+):([^:@/]+)(@.*)?" ref;
          name = lib.elemAt parts 0;
          tag = "${lib.elemAt parts 1}-${builtins.substring 7 12 entry.digest}";
        in
        pkgs.dockerTools.pullImage {
          imageName = name;
          imageDigest = entry.digest;
          finalImageTag = tag;
          inherit (entry) hash;
        }
        // {
          ref = "${name}:${tag}";
        };
      archives = lib.genAttrs refs pull;
    in
    {
      images = lib.attrValues archives;
      refFor = ref: archives.${ref}.ref;
    };

  /**
    A rendered manifest (a Helm chart's, say) with every `image:` ref
    replaced by its locked archive, see `locked`. Reading the manifest
    builds it during evaluation. Returns `manifest`, `images` and `refs`
    (what the manifest names, for `lock-images --lock`).

    # Arguments

    `pkgs`: nixpkgs

    `lockFile` (`Path`): JSON of ref to `{ digest, hash }`

    `manifest` (`Path`): the rendered manifest
  */
  chart =
    pkgs: lockFile: manifest:
    let
      text = builtins.readFile manifest;
      refs = lib.unique (
        lib.concatMap (
          line:
          let
            ref = builtins.match "[[:space:]-]*image: \"?([^\"[:space:]]+)\"?[[:space:]]*" line;
          in
          if ref == null then [ ] else ref
        ) (lib.splitString "\n" text)
      );
      pinned = locked pkgs lockFile refs;
    in
    {
      inherit refs;
      inherit (pinned) images;
      manifest = pkgs.writeText (baseNameOf manifest) (
        builtins.replaceStrings refs (map pinned.refFor refs) text
      );
    };

  /**
    An image archive from `pinned` or `locked`, flattened into one layer
    without the files that match `paths` (bsdtar `--exclude` patterns from
    the root, a directory takes its contents along). For upstream images
    that ship what the cluster can't use, like drivers for hardware the
    node lacks. The tag gets `-stripped`, so the ref differs from the full
    image.

    # Arguments

    `pkgs`: nixpkgs

    `image`: an archive with `ref`

    `paths` (`[String]`): patterns of what to drop

    # Example

    ```nix
    server = images.strip pkgs (images.pinned pkgs ./Dockerfile)."ghcr.io/immich-app/immich-server" [
      "usr/local/lib/*.a"
    ];
    ```
  */
  strip =
    pkgs: image: paths:
    let
      imageTag = "${image.imageTag}-stripped";
      ref = "${image.imageName}:${imageTag}";
    in
    pkgs.runCommand "${lib.removeSuffix ".tar" image.name}-stripped.tar"
      {
        nativeBuildInputs = [
          pkgs.crane
          pkgs.jq
          pkgs.libarchive
        ];
      }
      ''
        # GNU tar --delete corrupts large archives
        crane export - - < ${image} |
          bsdtar -cf fs.tar ${lib.concatMapStringsSep " " (p: "--exclude ${lib.escapeShellArg p}") paths} @-
        diff=$(sha256sum fs.tar | cut -d' ' -f1)
        mv fs.tar "$diff.tar"
        tar -xOf ${image} "$(tar -xOf ${image} manifest.json | jq -r '.[0].Config')" |
          jq --arg diff "sha256:$diff" \
            '.rootfs.diff_ids = [$diff] | .history = [{ created, comment: "stripped" }]' > config.json
        config=$(sha256sum config.json | cut -d' ' -f1).json
        mv config.json "$config"
        jq -n --arg config "$config" --arg layer "$diff.tar" --arg ref ${lib.escapeShellArg ref} \
          '[{ Config: $config, RepoTags: [$ref], Layers: [$layer] }]' > manifest.json
        tar -cf $out manifest.json "$config" "$diff.tar"
      ''
    // {
      inherit (image) imageName;
      inherit imageTag ref;
    };
}
