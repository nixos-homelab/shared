#!/usr/bin/env bash
# shellcheck disable=SC2154
set -eo pipefail; shopt -s inherit_errexit

DOC="Lock the images that lib.images pulls
Usage:
  lock-images
  lock-images --lock FILE REF...

Without arguments: writes images.lock next to every Dockerfile below the
current directory, the Nix hash of each FROM line's image (lib.images.pinned),
and re-locks every lock file of the flake there that its manifests check
names (homelab.cluster.imageLocks).
--lock: writes FILE with the digest and Nix hash of each REF, a tag resolved
to its digest now (lib.images.locked and lib.images.chart).
"
# docopt parser below, refresh this parser with `docopt.sh lock-images.sh`
# shellcheck disable=2016,1004,2086,2329,2034,1075,2154
docopt() { parse() { if ${DOCOPT_DOC_CHECK:-true}; then local doc_hash;if \
doc_hash=$(printf "%s" "$DOC" | (sha256sum 2>/dev/null || shasum -a 256)); then
if [[ ${doc_hash:0:5} != "$digest" ]]; then stderr "The current usage doc \
(${doc_hash:0:5}) does not match what the parser was generated with (${digest})
Run \`docopt.sh\` to refresh the parser.";_return 70;fi;fi;fi;local root_idx=$1
shift;params=();continuation=();assignments=();values=();local argv=("$@") arg \
i o;while [[ ${#argv[@]} -gt 0 ]]; do if [[ ${argv[0]} = "--" ]]; then for arg \
in "${argv[@]}"; do params+=("a:$arg");done;break;elif [[ ${argv[0]} = --* ]]; \
then local long=${argv[0]%%=*};if ${DOCOPT_ADD_HELP:-true} && [[ $long = \
"--help" ]]; then stdout "$trimmed_doc";_return 0;elif [[ \
${DOCOPT_PROGRAM_VERSION:-false} != 'false' && $long = "--version" ]]; then
stdout "$DOCOPT_PROGRAM_VERSION";_return 0;fi;local similar=() match=false;i=0
for o in "${options[@]}"; do if [[ $o = *" $long "? ]]; then similar+=("$long")
match=$i;break;fi;: $((i++));done;if [[ $match = false ]]; then i=0;for o in \
"${options[@]}"; do if [[ $o = *" $long"*? ]]; then local long_match=${o#* }
similar+=("${long_match% *}");match=$i;fi;: $((i++));done;fi;if [[ \
${#similar[@]} -gt 1 ]]; then error "${long} is not a unique prefix: \
${similar[*]}?";elif [[ ${#similar[@]} -lt 1 ]]; then error;else if [[ \
${options[$match]} = *0 ]]; then if [[ ${argv[0]} = *=* ]]; then local \
long_match=${o#* };error "${long_match% *} must not have an argument";else
params+=("$match:true");argv=("${argv[@]:1}");fi;else if [[ ${argv[0]} = *=* \
]]; then params+=("$match:${argv[0]#*=}");argv=("${argv[@]:1}");else if [[ \
${#argv[@]} -le 1 || ${argv[1]} = '--' ]]; then error "${long} requires \
argument";fi;params+=("$match:${argv[1]}");argv=("${argv[@]:2}");fi;fi;fi;elif \
[[ ${argv[0]} = -* && ${argv[0]} != "-" ]]; then local remaining=${argv[0]#-}
while [[ -n $remaining ]]; do local short="-${remaining:0:1}";if \
${DOCOPT_ADD_HELP:-true} && [[ $short = "-h" ]]; then stdout "$trimmed_doc"
_return 0;fi;local matched=false;remaining="${remaining:1}";i=0;for o in \
"${options[@]}"; do if [[ $o = "$short "* ]]; then if [[ $o = *1 ]]; then if \
[[ $remaining = '' ]]; then if [[ ${#argv[@]} -le 1 || ${argv[1]} = '--' ]]; \
then error "${short} requires argument";fi;params+=("$i:${argv[1]}")
argv=("${argv[@]:1}");break 2;else params+=("$i:$remaining");break 2;fi;else
params+=("$i:true");matched=true;break;fi;fi;: $((i++));done;$matched || error
done;argv=("${argv[@]:1}");elif ${DOCOPT_OPTIONS_FIRST:-false}; then for arg \
in "${argv[@]}"; do params+=("a:$arg");done;break;else params+=("a:${argv[0]}")
argv=("${argv[@]:1}");fi;done;if ! "node_$root_idx" || [ ${#params[@]} -gt 0 \
]; then error;fi;for ((i=0; i<${#assignments[@]}; i++)); do eval \
"${assignments[$i]}";done;return 0;};match_continuation() { if [[ \
${continuation[0]} = '!' ]]; then return 0;elif [[ ${#continuation[@]} -eq 0 \
]]; then [[ ${#params[@]} -eq 0 ]];return $?;fi;local \
node_idx=${continuation[0]} rest=("${continuation[@]:1}");if [[ $node_idx = \
\?* ]]; then continuation=("${node_idx#?}" "${rest[@]}");match_continuation && \
return 0;continuation=("${rest[@]}");match_continuation && return 0;else
continuation=("${rest[@]}");"node_$node_idx" && return 0;fi
continuation=("$node_idx" "${rest[@]}");return 1;};sequence() { local \
initial_continuation=("${continuation[@]}");continuation=("$@" \
"${continuation[@]}");match_continuation && return 0
continuation=("${initial_continuation[@]}");return 1;};optional() { local \
initial_continuation=("${continuation[@]}") optionals=() node_idx;for node_idx \
in "$@"; do optionals+=("?$node_idx");done;continuation=("${optionals[@]}" \
"${continuation[@]}");match_continuation && return 0
continuation=("${initial_continuation[@]}");return 1;};repeatable() { local \
initial_continuation=("${continuation[@]}");local \
initial_params=("${params[@]}") initial_count=${#assignments[@]};local \
before_params before_count last_params=() last_count count=0 i;while true; do
before_params=("${params[@]}");before_count=${#assignments[@]}
continuation=("$1" '!');match_continuation || break;: $((count++))
last_params=("${before_params[@]}");last_count=$before_count;[[ \
${#before_params[@]} -eq ${#params[@]} ]] && break;done;while [[ $count -gt 0 \
]]; do params=("${last_params[@]}")
assignments=("${assignments[@]:0:$last_count}")
values=("${values[@]:0:$last_count}");continuation=("$1" \
"${initial_continuation[@]}");match_continuation && return 0;: $((count--))
params=("${initial_params[@]}")
assignments=("${assignments[@]:0:$initial_count}")
values=("${values[@]:0:$initial_count}");for ((i=1; i<count; i++)); do
continuation=("$1" '!');match_continuation;done;last_params=("${params[@]}")
last_count=${#assignments[@]};done;params=("${initial_params[@]}")
assignments=("${assignments[@]:0:$initial_count}")
values=("${values[@]:0:$initial_count}")
continuation=("${initial_continuation[@]}");return 1;};consume() { local \
initial_params=("${params[@]}") initial_count=${#assignments[@]}
params=("${params[@]:0:$1}" "${params[@]:(($1+1))}");assignments+=("$2")
values+=("$3");match_continuation && return 0;params=("${initial_params[@]}")
assignments=("${assignments[@]:0:$initial_count}")
values=("${values[@]:0:$initial_count}");return 1;};switch() { local i param
for i in "${!params[@]}"; do local param=${params[$i]};if [[ $param = "$2" || \
$param = "$2":* ]]; then if [[ $3 = true ]]; then consume "$i" \
"var_$1=\$((var_$1+1))" && return 0;else consume "$i" "var_$1=true" && return 0
fi;return 1;elif [[ $param = a:* && $2 = a:* ]]; then return 1;fi;done;return 1
};value() { local i param;for i in "${!params[@]}"; do local param=${params[$i]}
if [[ $param = "$2":* ]]; then local value_ref="\${values[${#values[@]}]}";if \
[[ $3 = true ]]; then consume "$i" "var_$1+=(\"$value_ref\")" "${param#*:}" && \
return 0;else consume "$i" "var_$1=$value_ref" "${param#*:}" && return 0;fi
return 1;fi;done;return 1;};stdout() { printf -- "cat <<'EOM'\n%s\nEOM\n" "$1";}
stderr() { printf -- "cat <<'EOM' >&2\n%s\nEOM\n" "$1";};error() { [[ -n $1 ]] \
&& stderr "$1";stderr "$usage";_return 1;};_return() { printf -- "exit %d\n" \
"$1";exit "$1";};set -e;trimmed_doc=${DOC:0:490};usage=${DOC:38:53};digest=d81c6
options=(' --lock 0');node_0(){ switch __lock 0;};node_1(){ value FILE a;}
node_2(){ value REF a true;};node_3(){ sequence 0 1 4;};node_4(){ repeatable 2;}
node_5(){ optional 3;};cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" \
"$1" >&2;printf "%s\n" "${DOC:38:53}" >&2;exit 1;}';local varnames=(__lock \
FILE REF) varname;for varname in "${varnames[@]}"; do unset "var_$varname";done
parse 5 "$@";local p=${DOCOPT_PREFIX:-''};for varname in "${varnames[@]}"; do
unset "$p$varname";done;if declare -p var_REF >/dev/null 2>&1; then eval $p'RE'\
'F=("${var_REF[@]}")';else eval $p'REF=()';fi;eval $p'__lock=${var___lock:-fal'\
'se};'$p'FILE=${var_FILE:-};';if false; then __lock="" FILE="" REF=""; fi
local docopt_i=1;[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2;for \
((;docopt_i>0;docopt_i--)); do for varname in "${varnames[@]}"; do declare -p \
"$p$varname";done;done;}
# docopt parser above, complete command for generating this parser is `docopt.sh lock-images.sh`

# The archive's Nix hash, tagged as lib.images tags it: TAG-<the digest's first 12 hex digits>
prefetch() {
  local name=$1 tag=$2 digest=$3
  nix-prefetch-docker --quiet --json --image-name "$name" --image-digest "$digest" \
    --final-image-tag "$tag-${digest:7:12}" | jq -r .hash
}

# Writes FILE with the digest and Nix hash of each REF
lock() {
  local path=$1 lock='{}' ref name tag digest hash
  shift
  for ref in "$@"; do
    [[ $ref =~ ^([^@]+):([^:@/]+)(@(sha256:[0-9a-f]{64}))?$ ]] || { printf "Not a name:tag[@digest]: %s\n" "$ref" >&2; return 1; }
    name=${BASH_REMATCH[1]} tag=${BASH_REMATCH[2]} digest=${BASH_REMATCH[4]}
    if [[ -z $digest ]]; then
      digest=sha256:$(skopeo inspect --raw "docker://$name:$tag" | sha256sum | cut -c1-64)
    fi
    hash=$(prefetch "$name" "$tag" "$digest")
    lock=$(jq --arg ref "$ref" --arg digest "$digest" --arg hash "$hash" '.[$ref] = {digest: $digest, hash: $hash}' <<<"$lock")
  done
  jq -S . <<<"$lock" >"$path"
}
main() {
  eval "$(docopt "$@")"
  if $__lock; then
    lock "$FILE" "${REF[@]}"
    return
  fi
  local dockerfiles dockerfile refs ref
  dockerfiles=$(find . -name Dockerfile -not -path './.git/*' -not -path './.worktrees/*')
  for dockerfile in $dockerfiles; do
    lock='{}' refs=$(awk '$1 == "FROM" {print $2}' "$dockerfile")
    for ref in $refs; do
      [[ $ref =~ ^([^:@]+):([^@]+)@(sha256:[0-9a-f]{64})$ ]] || continue
      hash=$(prefetch "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}")
      lock=$(jq --arg ref "${BASH_REMATCH[1]}@${BASH_REMATCH[3]}" --arg hash "$hash" '.[$ref] = $hash' <<<"$lock")
    done
    jq -S . <<<"$lock" >"$(dirname "$dockerfile")/images.lock"
  done
  # The flake's own lock files that its check names, keyed by their store path. Their refs come from what the flake
  # pins (a chart, a module's defaults), so a flake.lock bump can change them
  local system source locks lockfile refs
  system=$(nix eval --raw --impure --expr builtins.currentSystem)
  [[ $(nix eval ".#checks.$system" --apply 'checks: checks ? manifests') = true ]] || return 0
  source=$(nix flake metadata --json . | jq -r .path)
  locks=$(nix eval --json ".#checks.$system.manifests.imageLocks")
  for lockfile in $(jq -r --arg source "$source/" 'keys[] | select(startswith($source))' <<<"$locks"); do
    mapfile -t refs < <(jq -r --arg lockfile "$lockfile" '.[$lockfile][]' <<<"$locks")
    lock "${lockfile#"$source/"}" "${refs[@]}"
  done
}

main "$@"
