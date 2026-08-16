# https://github.com/arnarg/nixidy/blob/65723ff09083d27d58792a739bb56a7885215f07/lib/kustomize.nix
{ lib, ... }:
with builtins;
rec {
  /**
    Build a Kubernetes `Namespace` manifest for `namespace`.

    # Arguments

    `namespace` (`String`): The namespace's name

    # Example

    ```nix
    createNamespace { namespace = "media"; }
    => { apiVersion = "v1"; kind = "Namespace"; metadata.name = "media"; }
    ```
  */
  createNamespace =
    { namespace }:
    {
      apiVersion = "v1";
      kind = "Namespace";
      metadata.name = namespace;
    };
  /**
    Replace every character in `string` that doesn't match `validCharsRE`
    with `replaceWith`.

    # Arguments

    `validCharsRE` (`String`): A regular expression matched against each
    character individually

    `replaceWith` (`String`): The replacement for characters that don't
    match

    `string` (`String`): The string to sanitize

    # Example

    ```nix
    replaceInvalidCharacters "[a-z0-9-]" "-" "My_Path/To.File"
    => "-y--ath--o--ile"
    ```
  */
  replaceInvalidCharacters =
    validCharsRE: replaceWith: string:
    lib.concatStrings (
      map (c: if match validCharsRE c == null then replaceWith else c) (lib.stringToCharacters string)
    );
  /**
    Turn a filesystem path into a name safe for use as a Kubernetes
    resource or volume mount name: strips the leading `/`, lowercases it,
    and replaces every character outside `[a-z0-9-]` with `-`. If the
    result is longer than 63 characters (the usual Kubernetes name length
    limit), it's truncated to 54 characters plus a `-` and an 8-character
    hash of the full cleaned name, to stay under the limit without losing
    uniqueness.

    # Arguments

    `path` (`String`): The path to convert

    # Example

    ```nix
    pathToMountName "/data/media/downloads"
    => "data-media-downloads"
    ```
  */
  pathToMountName =
    path:
    let
      cleaned = replaceInvalidCharacters "[a-z0-9-]" "-" (
        lib.toLower (lib.strings.removePrefix "/" path)
      );
    in
    if lib.stringLength cleaned > 63 then
      ((substring 0 54 cleaned) + "-" + (substring 0 8 (hashString "sha256" cleaned)))
    else
      cleaned;
  /**
    Build a derivation that renders the kustomization at `path` inside
    `src` into a single Kubernetes manifest, via `kubectl kustomize`.

    `extraFiles` are copied in before building -- useful for files the
    kustomization references that aren't already part of `src`. If
    `options` is given, it's serialized into a ConfigMap named `options`
    and written to `${path}/options.yaml`, marked with the
    `config.kubernetes.io/local-config` annotation so kustomize treats it
    as local, non-deployed configuration (for use with generators or
    replacements inside the kustomization).

    # Arguments

    `pkgs`: nixpkgs

    `name` (`String`): Used only for the derivation's own name

    `src`: Derivation or path containing the kustomization entrypoint and
    any relative bases it references

    `path` (`String`): Path inside `src` to build (*optional*, defaults to
    `"."`)

    `options`: Value to serialize into the `options` ConfigMap (*optional*)

    `extraFiles` (`{ [DestPath] :: SrcPath }`): Additional files to copy in
    before building (*optional*)

    # Example

    ```nix
    k8s.buildKustomization { inherit pkgs; } {
      name = "media";
      src = ./kustomize/media;
    }
    ```
  */
  buildKustomization =
    { pkgs, ... }:
    {
      # Only used for derivation name.
      name,
      # Derivation containing the kustomization entrypoint and
      # all relative bases that it might reference.
      src,
      # Path in the derivation to build
      path ? ".",
      # Options to serialize into a configmap named "options", saved in options.yaml
      options ? null,
      # Map {dst = src} of additional files to copy into the derivation
      extraFiles ? { },
    }:
    pkgs.stdenvNoCC.mkDerivation {
      inherit src;
      name = "kustomize-${name}";

      phases = [
        "unpackPhase"
        "patchPhase"
        "installPhase"
      ];

      patchPhase =
        lib.join "\n" (lib.mapAttrsToList (dst: src: ''cp "${src}" "${dst}"'') extraFiles)
        + pkgs.lib.optionalString (!isNull options) ''
          cat >"${path}/options.yaml" <<EOF
          ${toJSON {
            apiVersion = "v1";
            kind = "ConfigMap";
            metadata.name = "options";
            metadata.annotations."config.kubernetes.io/local-config" = "true";
            data = toJSON options;
          }}
          EOF
        '';

      installPhase = ''
        ${lib.getExe pkgs.kubectl} kustomize "${path}" -o "$out"
      '';
    };
  /**
    Build a derivation that applies `patch` to the single manifest `src`
    via `kubectl kustomize`, and returns the patched manifest.

    # Arguments

    `pkgs`: nixpkgs

    `src`: The manifest file to patch

    `patch`: The kustomize patch file to apply

    # Example

    ```nix
    k8s.patchManifest { inherit pkgs; } ./deployment.yaml ./patches/replicas.yaml
    ```
  */
  patchManifest =
    { pkgs, ... }:
    src: patch:
    pkgs.stdenvNoCC.mkDerivation {
      name = "k8s-patch-manifest";

      phases = [
        "buildPhase"
        "installPhase"
      ];

      buildPhase = ''
        runHook preBuild
        cp ${src} resource.yaml
        cp ${patch} patch.yaml
        cat >kustomization.yaml <<EOF
        apiVersion: kustomize.config.k8s.io/v1beta1
        kind: Kustomization
        resources: [resource.yaml]
        patches: [{path: patch.yaml}]
        EOF
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        ${lib.getExe pkgs.kubectl} kustomize . -o "$out"
        runHook postInstall
      '';
    };
}
