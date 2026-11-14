# The nixpkgs module links manifests, images and charts into the k3s data directory with tmpfiles `L+` rules and
# never removes them, and k3s neither deletes the objects of a manifest that is gone nor gives them owner references
# to the Addon it tracks the manifest with. This removes the links an earlier generation made, and then the objects
# and Addon of each manifest it removed. The files k3s writes there itself are regular files, which this never touches
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.homelab.k3s;
  # Where the nixpkgs module puts its links, through the link to the data directory
  rancherDir = "/var/lib/rancher/k3s";
  dirs = [
    "server/manifests"
    "agent/images"
    "server/static/charts"
  ];
  links = lib.attrNames config.systemd.tmpfiles.settings."10-k3s";
  keep =
    dir:
    map (lib.removePrefix "${rancherDir}/${dir}/") (lib.filter (lib.hasPrefix "${rancherDir}/${dir}/") links);
  manifests = "${cfg.dataDir}/server/manifests";
  pending = "/var/lib/k3s-prune/addons";
  kubectl = "${lib.getExe config.services.k3s.package} kubectl --request-timeout=30s";

  pruneLinks = pkgs.writeShellApplication {
    name = "k3s-prune-links";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
    ];
    text = ''
      mkdir -p ${pending}
      # DIR KEEP...: removes the links below DIR into the store or nowhere that aren't KEEP (relative to DIR)
      prune() {
        local dir=$1 link rel target name
        shift
        declare -A keep=()
        for rel in "$@"; do keep[$rel]=1; done
        [[ -d $dir ]] || return 0
        while IFS= read -r -d "" link; do
          rel=''${link#"$dir"/}
          [[ -z ''${keep[$rel]:-} ]] || continue
          target=$(readlink "$link")
          [[ $target = /nix/store/* || ! -e $link ]] || continue
          rm "$link"
          printf "Removed %s (%s)\n" "$link" "$target"
          # A manifest k3s applied: k3s names its Addon after the file, up to the first dot
          if [[ $dir = "${manifests}" && $rel =~ \.(yaml|yml|json)$ && ''${link##*/} != .* ]]; then
            name=''${link##*/}
            printf "%s\n" "$link" >"${pending}/''${name%%.*}"
          fi
        done < <(find "$dir" -type l -print0)
      }
      ${lib.concatMapStrings (dir: ''
        prune ${lib.escapeShellArgs ([ "${cfg.dataDir}/${dir}" ] ++ keep dir)}
      '') dirs}
    '';
  };

  pruneAddons = pkgs.writeShellApplication {
    name = "k3s-prune-addons";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.jq
      pkgs.yq-go
    ];
    text = ''
      shopt -s nullglob
      records=(${pending}/*)
      (( ''${#records[@]} )) || exit 0
      until ${kubectl} get --raw /readyz >/dev/null 2>&1; do sleep 5; done
      # The group versions the API server serves
      core=$(${kubectl} get --raw /api)
      groups=$(${kubectl} get --raw /apis)
      served=$(jq -s '[.[0].versions[], .[1].groups[].versions[].groupVersion]' <<<"$core$groups")
      # group/kind/namespace/name of each object the remaining manifests (those of k3s included) declare, read from
      # the files, as kinds the API server doesn't serve yet or no more have nothing to look up. One without a
      # namespace counts for none and for default, as k3s puts namespaced objects in default. One that moved from a
      # removed manifest to a remaining one may still carry the Addon of the removed one until k3s applies the
      # remaining one again
      declared=$(find -L ${manifests} -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" \) ! -name ".*" -print0 \
        | xargs -0 -r yq eval -o=json -I=0 . | jq -s '
          [.[] | select(type == "object") | if .kind == "List" then .items[] else . end
            | select(type == "object" and .kind != null and .metadata.name != null)
            | "\(.apiVersion | if contains("/") then split("/")[0] else "" end)/\(.kind)/" as $kind
            | (.metadata.namespace // ("", "default")) as $namespace
            | "\($kind)\($namespace)/\(.metadata.name)"]
        ')
      for record in "''${records[@]}"; do
        name=''${record##*/}
        source=$(<"$record")
        # Another file under the name of the Addon: k3s applies it to the same Addon, which prunes what it no longer
        # declares
        if find ${manifests} -name "$name.*" -print -quit | grep -q .; then
          printf "Kept Addon %s: a remaining manifest has its name\n" "$name"
          rm "$record"
          continue
        fi
        addon=$(${kubectl} -n kube-system get addon "$name" --ignore-not-found -o json)
        if [[ -z $addon ]]; then
          rm "$record"
          continue
        fi
        if [[ $(jq -r .spec.source <<<"$addon") != "$source" ]]; then
          printf "Kept Addon %s: its source isn't %s\n" "$name" "$source"
          rm "$record"
          continue
        fi
        # What k3s applied with the Addon as owner (the objectset labels and annotations of wrangler) in the kinds it
        # recorded, as k3s itself prunes them, but none that a remaining manifest declares
        hash=$(printf "%s" "k3s.cattle.io/v1, Kind=Addon''${name}kube-system" | sha1sum | cut -d" " -f1)
        objects=()
        IFS=";" read -ra gvks <<<"$(jq -r '.metadata.annotations["addon.k3s.cattle.io/gvks"] // ""' <<<"$addon")"
        for gvk in "''${gvks[@]}"; do
          # GROUP/VERSION, Kind=KIND, with an empty group for the core API
          gv=''${gvk%%, Kind=*} kind=''${gvk#*, Kind=}
          group=''${gv%%/*} gv=''${gv#/}
          api=/apis/$gv
          [[ -n $group ]] || api=/api/$gv
          # Kinds the API server no longer serves have nothing left to delete, as for k3s
          jq -e --arg gv "$gv" 'any(.[]; . == $gv)' <<<"$served" >/dev/null || continue
          resource=$(${kubectl} get --raw "$api" | jq -r --arg kind "$kind" '
            first(.resources[] | select(.kind == $kind and (.name | contains("/") | not)) | .name) // empty
          ')
          [[ -n $resource ]] || continue
          list=$(${kubectl} get --raw "$api/$resource?labelSelector=objectset.rio.cattle.io/hash=$hash")
          # The items of a list carry no apiVersion and kind
          found=$(jq -c --arg name "$name" --arg group "$group" --arg gv "$gv" --arg kind "$kind" \
            --argjson declared "$declared" '
            .items[]
            | select(.metadata.labels["objectset.rio.cattle.io/prune"] != "false")
            | select(.metadata.annotations as $a | $a["objectset.rio.cattle.io/owner-gvk"] == "k3s.cattle.io/v1, Kind=Addon"
                and $a["objectset.rio.cattle.io/owner-name"] == $name
                and $a["objectset.rio.cattle.io/owner-namespace"] == "kube-system")
            | select("\($group)/\($kind)/\(.metadata.namespace // "")/\(.metadata.name)" as $key | any($declared[]; . == $key) | not)
            | {apiVersion: $gv, $kind, metadata: (.metadata | {name, namespace} | with_entries(select(.value != null)))}
          ' <<<"$list")
          [[ -z $found ]] || mapfile -t -O "''${#objects[@]}" objects <<<"$found"
        done
        if (( ''${#objects[@]} )); then
          printf "%s\n" "''${objects[@]}" | jq -s '{apiVersion: "v1", kind: "List", items: .}' \
            | ${kubectl} delete -f - --cascade=background --ignore-not-found --wait=false
        fi
        ${kubectl} -n kube-system delete addon "$name" --ignore-not-found
        rm "$record"
      done
    '';
  };
in
{
  config = lib.mkIf cfg.enable {
    # Before k3s, so that it never applies a removed manifest again when it starts
    systemd.services.k3s-prune-links = {
      description = "Remove what an earlier generation linked into the k3s data directory";
      before = [ "k3s.service" ];
      wantedBy = [ "multi-user.target" ];
      unitConfig.RequiresMountsFor = [ cfg.dataDir ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "k3s-prune";
        ExecStart = lib.getExe pruneLinks;
      };
    };
    # Restarted with the other on a deploy that changes the links, ordered after it in the same transaction
    systemd.services.k3s-prune-addons = {
      description = "Delete the Addons and objects of the manifests removed from the k3s data directory";
      after = [
        "k3s.service"
        "k3s-prune-links.service"
      ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ pruneLinks ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "k3s-prune";
        ExecStart = lib.getExe pruneAddons;
        # The wait for the API server, which can come up well after k3s started
        TimeoutStartSec = "10min";
      };
    };
  };
}
