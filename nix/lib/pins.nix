{ lib, ... }:
{
  /**
    The refs pinned in a workflow that never runs, as `{ "owner/repo" = ref; }`:
    its `uses: owner/repo@ref` lines, which Dependabot's github-actions
    ecosystem bumps, whether or not the repository is an action. For sources
    that are neither images nor flake inputs, such as a release asset.

    # Arguments

    `file` (`Path`): the workflow, `.github/workflows/pins.yaml`
  */
  refs =
    file:
    lib.listToAttrs (
      map (pin: lib.nameValuePair (lib.elemAt pin 0) (lib.elemAt pin 1)) (
        lib.filter (pin: pin != null) (
          map (builtins.match "[[:space:]-]*uses: ([^@[:space:]]+)@([^[:space:]#]+).*") (
            lib.splitString "\n" (builtins.readFile file)
          )
        )
      )
    );

  /**
    A fixed-output fetch whose hash is in `lockFile` under `name@ref`, which
    `lock-images` writes. Returns `src`, the fetch, and for
    `homelab.cluster.sourceLocks`, `key` and `unlocked`: the fetch with an
    empty hash, whose mismatch error names the hash.

    The ref has to come from the flake that holds `lockFile` (its pins.yaml,
    say), never from an input a consumer can override with `follows`, such
    as a nixhelm chart's version: a consumer whose input is newer would name
    a key this lock doesn't have, and its evaluation fails.

    # Arguments

    `lockFile` (`Path`): JSON of `name@ref` to hash

    `name` (`String`): what is fetched, with anything besides the ref that changes it

    `ref` (`String`): the pinned ref

    `fetch` (`String -> Derivation`): the fetch, given its hash
  */
  locked =
    lockFile: name: ref: fetch:
    let
      key = "${name}@${ref}";
      lock = if builtins.pathExists lockFile then lib.importJSON lockFile else { };
    in
    {
      inherit key;
      src = fetch (lock.${key} or (throw "${key} isn't in ${toString lockFile}, run lock-images"));
      unlocked = fetch "";
    };
}
