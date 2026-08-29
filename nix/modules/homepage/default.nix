{ self, inputs, ... }:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.homepage;
  assets = pkgs.stdenvNoCC.mkDerivation {
    name = "assets";
    phases = [ "installPhase" ];
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/app/public/assets"
      ${lib.join "\n" (
        lib.mapAttrsToList (
          dest: src: "cp ${src} $out/app/public/assets/${lib.escapeShellArg dest}"
        ) cfg.assets
      )}
      runHook postInstall
    '';
  };
  image = pkgs.dockerTools.buildImage {
    name = "cluster.local/homepage";
    fromImage = pkgs.dockerTools.pullImage {
      imageName = "ghcr.io/gethomepage/homepage";
      imageDigest = "sha256:baffd41118d17202632c4c86d07bed10bd853115630dcbbe4907442742a594b8";
      sha256 = "sha256-VRkoBsahzKSNPdiBszWGeNq8ayfe6NEeuzFf9Fqgnbc=";
      os = "linux";
      arch = "x86_64";
    };
    copyToRoot = [
      pkgs.bash
      assets
    ]
    ++ lib.optionals cfg.debug ccfg.debugTools;
    runAsRoot = ''
      #!${pkgs.runtimeShell}
      cp -r /app/.next/server/pages /app/.next/server/pages-template
    '';
    config.WorkingDir = "/app";
    config.Entrypoint = [
      (pkgs.lib.getExe (
        pkgs.writeShellScriptBin "setup-pages" ''
          cp -r /app/.next/server/pages-template/. /app/.next/server/pages/.
          exec "$@"
        ''
      ))
    ];
    config.Cmd = [
      "node"
      "server.js"
    ];
  };
  toSortedList =
    attrs:
    (lib.sortOn ({ name, value }: if (lib.hasAttr "sort" value) then value.sort else 100) (
      lib.filter ({ name, value }: if (lib.hasAttr "show" value) then value.show else true) (
        lib.attrsToList attrs
      )
    ));
in
{
  # https://github.com/hercules-ci/flake-parts/pull/251
  key = "${toString __curPos.file}#modules.nixos.homepage";
  options.homelab.homepage = {
    enable = lib.mkEnableOption "homepage";
    debug = lib.mkEnableOption "debug mode";
    allowEgress = lib.mkOption {
      description = "Which services homepage should be allowed access to";
      type = lib.types.listOf lib.types.str;
    };
    envByName = lib.mkOption {
      description = "Additional environment options to add to the homepage container";
      type = lib.types.attrsOf lib.types.anything;
      default = { };
    };
    envFrom = lib.mkOption {
      description = "Additional environment options to add to the homepage container";
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      default = [ ];
    };
    backgroundImage = lib.mkOption {
      description = "Background image";
      type = lib.types.package;
      default = pkgs.fetchurl {
        name = "backgroundImage.png";
        url = "https://images.unsplash.com/photo-1502790671504-542ad42d5189?auto=format&fit=crop&w=2560&q=80";
        hash = "sha256-ixg2MEbI/0tvJXAQ9V2JB9yyiUrOPgIE5QNtpahIIQE=";
      };
      defaultText = "https://images.unsplash.com/photo-1502790671504-542ad42d5189?auto=format&fit=crop&w=2560&q=80";
    };
    assets = lib.mkOption {
      description = "Assets to embed in the homepage image, <EMBEDDED-NAME> -> <PATH>";
      type = lib.types.attrsOf lib.types.path;
      default = { };
    };
    widgets = lib.mkOption {
      description = "Widgets to add to homepage";
      type = lib.types.attrsOf lib.types.anything;
      default = { };
    };
    services = lib.mkOption {
      description = "Services to add to homepage";
      type = lib.types.attrsOf (
        lib.types.attrsOf (lib.types.either (lib.types.int) (lib.types.attrsOf lib.types.anything))
      );
      default = { };
    };
    bookmarks = lib.mkOption {
      description = "Bookmarks to add to homepage. The structure is <CATEGORY>.<NAME>.{SETTINGS}";
      type = lib.types.attrsOf (
        lib.types.attrsOf (
          lib.types.submodule {
            options = {
              description = lib.mkOption {
                description = "Description of the link";
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
              href = lib.mkOption {
                description = "Link for the bookmark";
                type = lib.types.str;
              };
              icon = lib.mkOption {
                description = "Path to an icon image";
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
            };
          }
        )
      );
      default = { };
    };
  };
  imports = [ self.nixosModules.cluster ];
  config = lib.mkIf cfg.enable {
    homelab.homepage.assets."background.${lib.last (lib.split "." "${cfg.backgroundImage}")}" =
      cfg.backgroundImage;
    homelab.homepage.services.Media = {
      sort = lib.mkDefault 50;
      layout = lib.mkDefault {
        header = false;
        style = "row";
        columns = 3;
      };
    };
    homelab.homepage.services.Managers = {
      sort = lib.mkDefault 100;
      layout = lib.mkDefault {
        header = false;
        style = "row";
        columns = 3;
      };
    };
    homelab.homepage.services.Download = {
      sort = lib.mkDefault 150;
      layout = lib.mkDefault {
        header = false;
        style = "row";
        columns = 3;
      };
    };
    homelab.homepage.services.Finance = {
      sort = lib.mkDefault 150;
      layout = lib.mkDefault {
        header = false;
        style = "row";
        columns = 3;
      };
    };
    homelab.homepage.services.Monitoring = {
      sort = lib.mkDefault 150;
      layout = lib.mkDefault {
        header = false;
        style = "row";
        columns = 3;
      };
    };
    homelab.homepage.services.Networking = {
      sort = lib.mkDefault 150;
      layout = lib.mkDefault {
        header = false;
        style = "row";
        columns = 3;
      };
    };
    services.k3s.images = [ image ];
    services.k3s.manifests.homepage-static.source = ./homepage.yaml;
    kubetree.resources.homepage = {
      config = {
        apiVersion = "v1";
        kind = "ConfigMap";
        metadata.name = "homepage";
        metadata.namespace = "homepage";
        data = {
          "kubernetes.yaml" = builtins.toJSON { mode = "cluster"; };
          "bookmarks.yaml" = builtins.toJSON (
            lib.mapAttrsToList (category: contents: {
              "${category}" = lib.mapAttrsToList (name: settings: { "${name}" = [ settings ]; }) contents;
            }) cfg.bookmarks
          );
          "services.yaml" = builtins.toJSON (
            map (
              { name, value }:
              {
                ${name} =
                  map
                    (
                      { name, value }:
                      {
                        ${name} = lib.removeAttrs value [ "sort" ];
                      }
                    )
                    (
                      toSortedList (
                        lib.removeAttrs value [
                          "sort"
                          "layout"
                        ]
                      )
                    );
              }
            ) (toSortedList cfg.services)
          );
          "widgets.yaml" = builtins.toJSON (
            map (
              { name, value }:
              {
                ${name} = lib.removeAttrs value [ "sort" ];
              }
            ) (toSortedList cfg.widgets)
          );
          "docker.yaml" = "";
          "settings.yaml" = builtins.toJSON {
            disableUpdateCheck = true;
            background = "/assets/background.${lib.last (lib.split "." "${cfg.backgroundImage}")}";
            cardBlur = "xs";
            layout = map (
              { name, value }:
              {
                ${name} = value.layout or { };
              }
            ) (toSortedList cfg.services);
          };
          "proxmox.yaml" = "";
          "custom.css" = "";
          "custom.js" = "";
        };
      };
      workload = {
        apiVersion = "cluster.local";
        kind = "WorkloadMacro";
        metadata.name = "homepage";
        spec = {
          allowIngress = [ "gateway" ];
          allowEgress = [
            "apiserver"
          ]
          ++ cfg.allowEgress;
          ingressPort = null;
          podSpecMacro.serviceAccountName = "homepage";
          podSpecMacro.mainContainer = {
            image = "${image.buildArgs.name}:${image.imageTag}";
            imagePullPolicy = "Never";
            # Make all referenced env vars optional. Homepage can handle some values not being present
            envByName =
              (lib.mapAttrs (
                name: spec:
                if lib.isAttrs spec && spec ? valueFrom then
                  (
                    if spec.valueFrom ? configMapKeyRef then
                      lib.recursiveUpdate spec { valueFrom.configMapKeyRef.optional = true; }
                    else
                      (
                        if spec.valueFrom ? secretKeyRef then
                          lib.recursiveUpdate spec { valueFrom.secretKeyRef.optional = true; }
                        else
                          spec
                      )
                  )
                else
                  spec
              ) cfg.envByName)
              // {
                HOMEPAGE_ALLOWED_HOSTS = ccfg.domain;
                PUID = "1000";
                PGID = "1000";
              };
            envFrom = map (
              spec:
              if lib.isAttrs spec then
                (
                  if spec ? configMapRef then
                    lib.recursiveUpdate spec { configMapRef.optional = true; }
                  else
                    (if spec ? secretRef then lib.recursiveUpdate spec { secretRef.optional = true; } else spec)
                )
              else
                spec
            ) cfg.envFrom;
            portsByName.web = 3000;
            livenessProbe.httpGet.port = "web";
            readinessProbe.httpGet.port = "web";
            volumeMountsByPath =
              (lib.mergeAttrsList (
                map
                  (filename: {
                    "/app/config/${filename}" = {
                      name = "config";
                      subPath = filename;
                    };
                  })
                  [
                    "custom.js"
                    "custom.css"
                    "bookmarks.yaml"
                    "docker.yaml"
                    "kubernetes.yaml"
                    "proxmox.yaml"
                    "services.yaml"
                    "settings.yaml"
                    "widgets.yaml"
                  ]
              ))
              // {
                "/app/.next/server/pages" = "pages";
                "/app/config/logs" = "logs";
              };
          };
          podSpecMacro.volumesByName = {
            config.configMap.name = "homepage";
            logs.emptyDir = { };
            pages.emptyDir = { };
          };
        };
      };
      gateway = {
        apiVersion = "cluster.local";
        kind = "GatewayMacro";
        metadata.name = "homepage";
        spec.port = 3000;
        spec.subdomain = null;
      };
    };
  };
}
