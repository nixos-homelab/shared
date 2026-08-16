# k8s 


## `lib.k8s.createNamespace` 

Build a Kubernetes `Namespace` manifest for `namespace`.

### Arguments

`namespace` (`String`): The namespace's name

### Example

```nix
createNamespace { namespace = "media"; }
=> { apiVersion = "v1"; kind = "Namespace"; metadata.name = "media"; }
```

## `lib.k8s.replaceInvalidCharacters` 

Replace every character in `string` that doesn't match `validCharsRE`
with `replaceWith`.

### Arguments

`validCharsRE` (`String`): A regular expression matched against each
character individually

`replaceWith` (`String`): The replacement for characters that don't
match

`string` (`String`): The string to sanitize

### Example

```nix
replaceInvalidCharacters "[a-z0-9-]" "-" "My_Path/To.File"
=> "-y--ath--o--ile"
```

## `lib.k8s.pathToMountName` 

Turn a filesystem path into a name safe for use as a Kubernetes
resource or volume mount name: strips the leading `/`, lowercases it,
and replaces every character outside `[a-z0-9-]` with `-`. If the
result is longer than 63 characters (the usual Kubernetes name length
limit), it's truncated to 54 characters plus a `-` and an 8-character
hash of the full cleaned name, to stay under the limit without losing
uniqueness.

### Arguments

`path` (`String`): The path to convert

### Example

```nix
pathToMountName "/data/media/downloads"
=> "data-media-downloads"
```

## `lib.k8s.buildKustomization` 

Build a derivation that renders the kustomization at `path` inside
`src` into a single Kubernetes manifest, via `kubectl kustomize`.

`extraFiles` are copied in before building -- useful for files the
kustomization references that aren't already part of `src`. If
`options` is given, it's serialized into a ConfigMap named `options`
and written to `${path}/options.yaml`, marked with the
`config.kubernetes.io/local-config` annotation so kustomize treats it
as local, non-deployed configuration (for use with generators or
replacements inside the kustomization).

### Arguments

`pkgs`: nixpkgs

`name` (`String`): Used only for the derivation's own name

`src`: Derivation or path containing the kustomization entrypoint and
any relative bases it references

`path` (`String`): Path inside `src` to build (*optional*, defaults to
`"."`)

`options`: Value to serialize into the `options` ConfigMap (*optional*)

`extraFiles` (`{ [DestPath] :: SrcPath }`): Additional files to copy in
before building (*optional*)

### Example

```nix
k8s.buildKustomization { inherit pkgs; } {
  name = "media";
  src = ./kustomize/media;
}
```

## `lib.k8s.patchManifest` 

Build a derivation that applies `patch` to the single manifest `src`
via `kubectl kustomize`, and returns the patched manifest.

### Arguments

`pkgs`: nixpkgs

`src`: The manifest file to patch

`patch`: The kustomize patch file to apply

### Example

```nix
k8s.patchManifest { inherit pkgs; } ./deployment.yaml ./patches/replicas.yaml
```


