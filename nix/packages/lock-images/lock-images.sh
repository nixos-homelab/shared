#!/usr/bin/env bash
# Writes images.lock next to every Dockerfile below the current directory: the Nix hash of each FROM line's image, as
# lib.images.pinned pulls it (tag suffixed with the digest's first 12 hex digits)
set -eo pipefail; shopt -s inherit_errexit

dockerfiles=$(find . -name Dockerfile -not -path './.git/*' -not -path './.worktrees/*')
for dockerfile in $dockerfiles; do
  lock='{}' refs=$(awk '$1 == "FROM" {print $2}' "$dockerfile")
  for ref in $refs; do
    [[ $ref =~ ^([^:@]+):([^@]+)@(sha256:([0-9a-f]{12})[0-9a-f]{52})$ ]] || continue
    hash=$(nix-prefetch-docker --quiet --json --image-name "${BASH_REMATCH[1]}" --image-digest "${BASH_REMATCH[3]}" \
      --final-image-tag "${BASH_REMATCH[2]}-${BASH_REMATCH[4]}" | jq -r .hash)
    lock=$(jq --arg ref "${BASH_REMATCH[1]}@${BASH_REMATCH[3]}" --arg hash "$hash" '.[$ref] = $hash' <<<"$lock")
  done
  jq -S . <<<"$lock" >"$(dirname "$dockerfile")/images.lock"
done
