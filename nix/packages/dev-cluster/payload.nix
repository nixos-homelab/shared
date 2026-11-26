# The payload of a NixOS test's node as k3s finds it on the node: the manifests by their names in k3s' manifests
# directory, and the image archives linked into its image directory, collected in one directory
{
  url,
  attr,
  node ? "",
  system ? builtins.currentSystem,
}:
let
  flake = builtins.getFlake url;
  path = builtins.filter builtins.isString (builtins.split "\\." attr);
  candidates = [
    path
    (
      [
        "legacyPackages"
        system
      ]
      ++ path
    )
    (
      [
        "packages"
        system
      ]
      ++ path
    )
    (
      [
        "checks"
        system
      ]
      ++ path
    )
  ];
  lookup =
    ps:
    if ps == [ ] then
      throw "dev-cluster: ${url} has no ${attr}"
    else
      let
        p = builtins.head ps;
        get = builtins.foldl' (
          a: n: if a != null && builtins.isAttrs a && a ? ${n} then a.${n} else null
        ) flake p;
      in
      if get != null then get else lookup (builtins.tail ps);
  test = lookup candidates;
  nodes = test.nodes;
  k3sNodes = builtins.filter (n: nodes.${n}.services.k3s.enable or false) (builtins.attrNames nodes);
  name =
    if node != "" then
      node
    else if builtins.length k3sNodes == 1 then
      builtins.head k3sNodes
    else
      throw "dev-cluster: ${attr} has ${toString (builtins.length k3sNodes)} nodes running k3s, pick one with --node";
  config = nodes.${name};
  # linkFarm from the nixpkgs the flake follows
  pkgs = flake.inputs.nixpkgs.legacyPackages.${system};
  inherit (pkgs) lib;
  manifests = lib.mapAttrsToList (_: m: {
    name = "manifests/${m.target}";
    path = m.source;
  }) (lib.filterAttrs (_: m: m.enable) config.services.k3s.manifests);
  # The image links the k3s module puts in its image directory
  images = lib.concatMap (
    settings:
    lib.mapAttrsToList (p: v: {
      name = "images/${baseNameOf p}";
      path = v."L+".argument;
    }) (lib.filterAttrs (p: v: lib.hasSuffix "/agent/images/${baseNameOf p}" p && v ? "L+") settings)
  ) (lib.attrValues config.systemd.tmpfiles.settings);
in
pkgs.linkFarm "dev-cluster-payload-${name}" (manifests ++ images)
