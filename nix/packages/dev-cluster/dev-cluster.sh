#!/usr/bin/env bash
# shellcheck disable=SC2154
set -eo pipefail; shopt -s inherit_errexit

DOC="A k3s cluster in nested user, mount, network, pid and cgroup namespaces
Usage:
  dev-cluster start [--memory=SIZE]
  dev-cluster stop
  dev-cluster status
  dev-cluster load [--node=NAME] TEST
  dev-cluster kubectl [ARG...]
  dev-cluster exec CMD [ARG...]

Runs k3s unprivileged, for working on modules with real pods: it needs a
writable cgroup2 at /sys/fs/cgroup with the cpuset, cpu, memory and pids
controllers, 65536 subordinate ids (newuidmap) and room for two cgroup levels
below the root. Images come from the k3s airgap archive and what is linked into
the image directory; the cluster has no way out to a registry.
start: starts k3s and waits for the node and the system pods.
stop: kills everything of the cluster and removes its state.
status: the node and the pods.
load: puts the payload of a NixOS test's node where k3s picks it up while it
  runs: its manifests in k3s' manifests directory, which k3s' deploy controller
  applies as on the node, and its image archives in the image directory. TEST
  is a flake reference with the test's attribute, as in .#nixosTests.grafana
  (looked up as given, then under legacyPackages, packages and checks of this
  system). The node is the one running k3s, unless --node names it.
kubectl: kubectl against the cluster.
exec: runs CMD in the cluster's namespaces, as their root, with KUBECONFIG set.

Options:
  --memory=SIZE  memory.max of the cluster's cgroup [default: 8G]
  --node=NAME    The test's node to take the payload from

The state is in \$DEV_CLUSTER_DIR, by default \${TMPDIR:-/tmp}/dev-cluster.
"
# docopt parser below, refresh this parser with `docopt.sh dev-cluster.sh`
# shellcheck disable=2016,2086,2329,1075,2154
docopt() { parse() { if ${DOCOPT_DOC_CHECK:-true}; then local doc_hash;if \
doc_hash=$(printf "%s" "$DOC" | (sha256sum 2>/dev/null || shasum -a 256)); then
if [[ ${doc_hash:0:5} != "$digest" ]]; then stderr "The current usage doc \
(${doc_hash:0:5}) does not match what the parser was generated with (${digest})
Run \`docopt.sh\` to refresh the parser.";_return 70;fi;fi;fi;local root_idx=$1
shift;params=();testdepth=0;local argv=("$@") arg i o;while [[ ${#argv[@]} -gt \
0 ]]; do if [[ ${argv[0]} = "--" ]]; then for arg in "${argv[@]}"; do
params+=("a:$arg");done;break;elif [[ ${argv[0]} = --* ]]; then local \
long=${argv[0]%%=*};if ${DOCOPT_ADD_HELP:-true} && [[ $long = "--help" ]]; then
stdout "$trimmed_doc";_return 0;elif [[ ${DOCOPT_PROGRAM_VERSION:-false} != 'f'\
'alse' && $long = "--version" ]]; then stdout "$DOCOPT_PROGRAM_VERSION"
_return 0;fi;local similar=() match=false;i=0;for o in "${options[@]}"; do if \
[[ $o = *" $long "? ]]; then similar+=("$long");match=$i;break;fi;: $((i++))
done;if [[ $match = false ]]; then i=0;for o in "${options[@]}"; do if [[ $o = \
*" $long"*? ]]; then local long_match=${o#* };similar+=("${long_match% *}")
match=$i;fi;: $((i++));done;fi;if [[ ${#similar[@]} -gt 1 ]]; then error \
"${long} is not a unique prefix: ${similar[*]}?";elif [[ ${#similar[@]} -lt 1 \
]]; then error;else if [[ ${options[$match]} = *0 ]]; then if [[ ${argv[0]} = \
*=* ]]; then local long_match=${o#* };error "${long_match% *} must not have an \
argument";else params+=("$match:true");argv=("${argv[@]:1}");fi;else if [[ \
${argv[0]} = *=* ]]; then params+=("$match:${argv[0]#*=}");argv=("${argv[@]:1}")
else if [[ ${#argv[@]} -le 1 || ${argv[1]} = '--' ]]; then error "${long} \
requires argument";fi;params+=("$match:${argv[1]}");argv=("${argv[@]:2}");fi;fi
fi;elif [[ ${argv[0]} = -* && ${argv[0]} != "-" ]]; then local \
remaining=${argv[0]#-};while [[ -n $remaining ]]; do local \
short="-${remaining:0:1}";if ${DOCOPT_ADD_HELP:-true} && [[ $short = "-h" ]]; \
then stdout "$trimmed_doc";_return 0;fi;local matched=false
remaining="${remaining:1}";i=0;for o in "${options[@]}"; do if [[ $o = "$short \
"* ]]; then if [[ $o = *1 ]]; then if [[ $remaining = '' ]]; then if [[ \
${#argv[@]} -le 1 || ${argv[1]} = '--' ]]; then error "${short} requires \
argument";fi;params+=("$i:${argv[1]}");argv=("${argv[@]:1}");break 2;else
params+=("$i:$remaining");break 2;fi;else params+=("$i:true");matched=true;break
fi;fi;: $((i++));done;$matched || error;done;argv=("${argv[@]:1}");elif \
${DOCOPT_OPTIONS_FIRST:-false}; then for arg in "${argv[@]}"; do
params+=("a:$arg");done;break;else params+=("a:${argv[0]}")
argv=("${argv[@]:1}");fi;done;if ! "node_$root_idx" || [ ${#params[@]} -gt 0 \
]; then error;fi;return 0;};sequence() { local initial_params=("${params[@]}") \
node_idx;: $((testdepth++));for node_idx in "$@"; do if ! "node_$node_idx"; then
params=("${initial_params[@]}");: $((testdepth--));return 1;fi;done;if [[ \
$((--testdepth)) -eq 0 ]]; then params=("${initial_params[@]}");for node_idx \
in "$@"; do "node_$node_idx";done;fi;return 0;};choice() { local \
initial_params=("${params[@]}") best_match_idx unmatched_count node_idx;: \
$((testdepth++));for node_idx in "$@"; do if "node_$node_idx"; then if [[ -z \
$unmatched_count || ${#params[@]} -lt $unmatched_count ]]; then
best_match_idx=$node_idx;unmatched_count=${#params[@]};fi;fi
params=("${initial_params[@]}");done;: $((testdepth--));if [[ -n \
$best_match_idx ]]; then "node_$best_match_idx";return 0;fi;return 1;}
optional() { local node_idx;for node_idx in "$@"; do "node_$node_idx";done
return 0;};repeatable() { local matched=false remaining=${#params[@]};while \
"node_$1"; do matched=true;[[ $remaining -eq ${#params[@]} ]] && break
remaining=${#params[@]};done;if $matched; then return 0;fi;return 1;};switch() {
local i param;for i in "${!params[@]}"; do local param=${params[$i]};if [[ \
$param = "$2" || $param = "$2":* ]]; then params=("${params[@]:0:$i}" \
"${params[@]:((i+1))}");[[ $testdepth -gt 0 ]] && return 0;if [[ $3 = true ]]; \
then eval "((var_$1++))" || true;else eval "var_$1=true";fi;return 0;elif [[ \
$param = a:* && $2 = a:* ]]; then return 1;fi;done;return 1;};value() { local \
i param;for i in "${!params[@]}"; do local param=${params[$i]};if [[ $param = \
"$2":* ]]; then params=("${params[@]:0:$i}" "${params[@]:((i+1))}");[[ \
$testdepth -gt 0 ]] && return 0;if [[ $3 = true ]]; then eval \
"var_$1+="'("${param#*:}")';else eval "var_$1="'${param#*:}';fi;return 0;fi;done
return 1;};stdout() { printf -- "cat <<'EOM'\n%s\nEOM\n" "$1";};stderr() {
printf -- "cat <<'EOM' >&2\n%s\nEOM\n" "$1";};error() { [[ -n $1 ]] && stderr \
"$1";stderr "$usage";_return 1;};_return() { printf -- "exit %d\n" "$1";exit \
"$1";};set -e;trimmed_doc=${DOC:0:1562};usage=${DOC:72:183};digest=173c3
options=(' --memory 1' ' --node 1');node_0(){ value __memory 0;};node_1(){
value __node 1;};node_2(){ value TEST a;};node_3(){ value ARG a true;};node_4(){
value CMD a;};node_5(){ switch start a:start;};node_6(){ switch stop a:stop;}
node_7(){ switch status a:status;};node_8(){ switch load a:load;};node_9(){
switch kubectl a:kubectl;};node_10(){ switch exec a:exec;};node_11(){ sequence \
5 12;};node_12(){ optional 0;};node_13(){ sequence 8 14 2;};node_14(){
optional 1;};node_15(){ sequence 9 16;};node_16(){ optional 17;};node_17(){
repeatable 3;};node_18(){ sequence 10 4 16;};node_19(){ choice 11 6 7 13 15 18;}
cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" "$1" >&2;printf "%s\n" \
"${DOC:72:183}" >&2;exit 1;}';local varnames=(__memory __node TEST ARG CMD \
start stop status load kubectl exec) varname;for varname in "${varnames[@]}"; do
unset "var_$varname";done;parse 19 "$@";local p=${DOCOPT_PREFIX:-''};for \
varname in "${varnames[@]}"; do unset "$p$varname";done;if declare -p var_ARG \
>/dev/null 2>&1; then eval $p'ARG=("${var_ARG[@]}")';else eval $p'ARG=()';fi
eval $p'__memory=${var___memory:-8G};'$p'__node=${var___node:-};'$p'TEST=${var'\
'_TEST:-};'$p'CMD=${var_CMD:-};'$p'start=${var_start:-false};'$p'stop=${var_st'\
'op:-false};'$p'status=${var_status:-false};'$p'load=${var_load:-false};'$p'ku'\
'bectl=${var_kubectl:-false};'$p'exec=${var_exec:-false};';local docopt_i=1;[[ \
$BASH_VERSION =~ ^4.3 ]] && docopt_i=2;for ((;docopt_i>0;docopt_i--)); do for \
varname in "${varnames[@]}"; do declare -p "$p$varname";done;done;}
# docopt parser above, complete command for generating this parser is `docopt.sh dev-cluster.sh`

dir=${DEV_CLUSTER_DIR:-${TMPDIR:-/tmp}/dev-cluster}
cg=/sys/fs/cgroup/dev-cluster
kubeconfig=$dir/kubeconfig

# Inner 0 is the caller's uid, the other 65535 ids of the caller's namespace follow. Every id an image may run as needs
# a mapping: pause runs as 65535, and runc fails its setgroups without it
idmap() {
  local kind=$1 id=$2
  printf -- "--map-%s=0:%d:1 --map-%s=1:1:%d --map-%s=%d:0:1 --map-%s=%d:%d:%d" \
    "$kind" "$id" "$kind" $((id - 1)) "$kind" "$id" "$kind" $((id + 1)) $((id + 1)) $((65535 - id))
}

# A process in the cluster's namespaces: k3s, in the cgroup the inner shell moved itself to
k3s_pid() {
  local pid
  pid=$(head -n1 "$cg/ns/init/cgroup.procs" 2>/dev/null) || true
  [[ -n $pid ]] || { printf "dev-cluster: not running\n" >&2; return 1; }
  printf "%s\n" "$pid"
}

in_cluster() {
  local pid
  pid=$(k3s_pid)
  KUBECONFIG=$kubeconfig nsenter -t "$pid" -U -n -m -p --preserve-credentials -- "$@"
}

kubectl_() { in_cluster kubectl --kubeconfig "$kubeconfig" "$@"; }

as_nested_root() {
  # shellcheck disable=SC2046
  unshare $(idmap users "$(id -u)") $(idmap groups "$(id -g)") --setuid 0 --setgid 0 -- "$@"
}

start() {
  [[ ! -e $cg ]] || { printf "dev-cluster: already running (%s exists)\n" "$cg" >&2; return 1; }
  local controllers
  controllers=$(cat /sys/fs/cgroup/cgroup.controllers)
  for c in cpuset cpu memory pids; do
    [[ " $controllers " = *" $c "* ]] || { printf "dev-cluster: no %s controller at /sys/fs/cgroup\n" "$c" >&2; return 1; }
  done
  mkdir -p "$dir"
  # The store paths k3s uses outlive a garbage collection while it runs
  nix-store --add-root "$dir/gcroot" --realise "${self%/bin/*}" >/dev/null
  local started=$SECONDS
  setsid "$self" __outer "$__memory" >"$dir/k3s.log" 2>&1 </dev/null &
  local outer=$!
  printf "dev-cluster: starting, log in %s\n" "$dir/k3s.log" >&2
  until [[ -s $kubeconfig ]] && [[ -n $(kubectl_ get node -o name 2>/dev/null) ]]; do
    kill -0 "$outer" 2>/dev/null || { tail -n 20 "$dir/k3s.log" >&2; return 1; }
    sleep 1
  done
  kubectl_ wait --for=condition=Ready node --all --timeout=120s >/dev/null
  printf "dev-cluster: node Ready after %ds\n" $((SECONDS - started)) >&2
  until [[ -n $(kubectl_ get pods -n kube-system -l k8s-app=kube-dns -o name 2>/dev/null) ]]; do sleep 1; done
  kubectl_ wait --for=condition=Ready pods --all -n kube-system --timeout=180s >/dev/null
  printf "dev-cluster: system pods up after %ds\n" $((SECONDS - started)) >&2
}

# The cgroup namespace's root may hold no process, or its controllers can't be enabled for the pods' cgroups: unshare
# itself waits in sv/, the cluster runs in ns/. kubelet gets no QoS levels, so the pods' and containers' cgroups sit 3
# and 4 levels below /sys/fs/cgroup
outer() {
  local memory=$1
  mkdir -p "$cg"
  printf "%s\n" "$memory" >"$cg/memory.max"
  printf "0\n" >"$cg/memory.swap.max" || true
  printf "50\n" >"$cg/cpu.weight"
  mkdir -p "$cg/sv" "$cg/ns"
  printf "+cpuset +cpu +memory +pids\n" >"$cg/cgroup.subtree_control"
  printf "%d\n" $$ >"$cg/sv/cgroup.procs"
  # shellcheck disable=SC2046,SC2016
  exec unshare $(idmap users "$(id -u)") $(idmap groups "$(id -g)") --setuid 0 --setgid 0 \
    --net --mount --pid --fork --uts --ipc -- \
    bash -c 'printf "%d\n" $$ >/sys/fs/cgroup/dev-cluster/ns/cgroup.procs && exec unshare --cgroup -- "$0" __inner' "$self"
}

# Root of the nested namespaces, in the cgroup namespace rooted at ns/
inner() {
  mount --make-rprivate /
  mount -t tmpfs run /run
  # This pid namespace's processes, for containerd and runc
  mount -t proc proc /proc
  mkdir -p "$dir/var" "$dir/etc"
  mount --bind "$dir/var" /var
  # k3s writes /etc/rancher; /etc may be read-only and refuse to be an overlay's lower layer
  cp -rL /etc/. "$dir/etc/" 2>/dev/null || true
  mount --bind "$dir/etc" /etc
  mount -t cgroup2 cgroup2 /sys/fs/cgroup
  mkdir -p /sys/fs/cgroup/init
  printf "%d\n" $$ >/sys/fs/cgroup/init/cgroup.procs
  printf "+cpuset +cpu +memory +pids\n" >/sys/fs/cgroup/cgroup.subtree_control
  ip link set lo up
  ip link add eth0 type veth peer name gw0
  ip addr add 10.99.0.2/24 dev eth0
  ip addr add 10.99.0.1/24 dev gw0
  ip link set eth0 up
  ip link set gw0 up
  ip route add default via 10.99.0.1 dev eth0
  mkdir -p "$dir/data/agent/images"
  ln -sfn "$AIRGAP_IMAGES" "$dir/data/agent/images/k3s-airgap-images.tar.zst"
  # k3s' CNI plugins are one binary, called by the plugin's name
  mkdir -p "$dir/cni"
  for plugin in bandwidth bridge firewall flannel host-local loopback portmap; do
    ln -sfn "$CNI_PLUGINS/bin/cni" "$dir/cni/$plugin"
  done
  PATH=$dir/cni:$PATH
  local gate=feature-gates=KubeletInUserNamespace=true
  exec k3s server --data-dir "$dir/data" --node-ip 10.99.0.2 --flannel-iface eth0 \
    --disable traefik --disable servicelb \
    --write-kubeconfig "$kubeconfig" --write-kubeconfig-mode 644 \
    --kubelet-arg="$gate" --kube-apiserver-arg="$gate" --kube-controller-manager-arg="$gate" \
    --kubelet-arg=cgroups-per-qos=false --kubelet-arg=enforce-node-allocatable= \
    --kube-proxy-arg=conntrack-max-per-core=0 --kube-proxy-arg=conntrack-tcp-timeout-established=0 \
    --kube-proxy-arg=conntrack-tcp-timeout-close-wait=0
}

stop() {
  if [[ -e $cg ]]; then
    printf "1\n" >"$cg/cgroup.kill"
    while [[ -s $cg/cgroup.procs ]] || grep -qx "populated 1" "$cg/cgroup.events"; do sleep 0.2; done
    find "$cg" -depth -type d -exec rmdir {} +
  fi
  # What k3s and the pods wrote belongs to the nested ids
  [[ ! -e $dir ]] || as_nested_root rm -rf -- "${dir:?}"
}

load() {
  local ref=$1 node=$2 flake attr url payload
  [[ -e $cg ]] || { printf "dev-cluster: not running\n" >&2; return 1; }
  [[ $ref = *#* ]] || { printf "dev-cluster: %s names no attribute (FLAKE#ATTR)\n" "$ref" >&2; return 1; }
  flake=${ref%%#*} attr=${ref#*#}
  url=$(nix flake metadata --json "${flake:-.}" | jq -r .resolvedUrl)
  payload=$dir/payload-${attr//\//-}
  nix build --impure --out-link "$payload" --file "$PAYLOAD_NIX" \
    --argstr url "$url" --argstr attr "$attr" --argstr node "$node"
  local f n=0 m=0
  mkdir -p "$dir/data/agent/images" "$dir/data/server/manifests"
  for f in "$payload"/images/*; do
    ln -sfn "$(readlink "$f")" "$dir/data/agent/images/$(basename "$f")"
    n=$((n + 1))
  done
  for f in "$payload"/manifests/*; do
    ln -sfn "$(readlink "$f")" "$dir/data/server/manifests/$(basename "$f")"
    m=$((m + 1))
  done
  printf "dev-cluster: %d manifests and %d image archives of %s linked in\n" "$m" "$n" "$ref" >&2
}

status() {
  kubectl_ get node -o wide
  kubectl_ get pods -A
}

main() {
  self=$(realpath "${BASH_SOURCE[0]}")
  export AIRGAP_IMAGES CNI_PLUGINS PAYLOAD_NIX
  # kubectl's and CMD's arguments are theirs, options included
  case $1 in
    __outer) outer "$2"; return;;
    __inner) inner; return;;
    kubectl) shift; kubectl_ "$@"; return;;
    exec) shift; [[ $# -gt 0 ]] || set -- --help; [[ $1 = --help ]] || { in_cluster "$@"; return; };;
  esac
  eval "$(docopt "$@")"
  if $start; then start
  elif $stop; then stop
  elif $status; then status
  elif $load; then load "$TEST" "$__node"
  fi
}

main "$@"
