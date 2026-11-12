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
  # Attribute names can't carry the store path's string context
  backgroundAsset = "background.${builtins.unsafeDiscardStringContext (lib.last (lib.splitString "." "${cfg.backgroundImage}"))}";
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
    copyToRoot = [ assets ]
    ++ lib.optionals cfg.debug ccfg.debugTools;
    runAsRoot = ''
      #!${pkgs.runtimeShell}
      cp -r /app/.next/server/pages /app/.next/server/pages-template
    '';
    config.WorkingDir = "/app";
    config.Entrypoint = [
      # The base image's /bin/sh, so the layer carries no bash and glibc
      "${pkgs.writeScript "setup-pages" ''
        #!/bin/sh
        cp -r /app/.next/server/pages-template/. /app/.next/server/pages/.
        exec "$@"
      ''}"
    ];
    config.Cmd = [
      "node"
      "server.js"
    ];
  };
  toSortedList =
    attrs:
    map
      (
        elem:
        lib.removeAttrs elem [
          "enable"
          "sort"
        ]
      )
      (
        lib.sortOn ({ name, value }: value.sort) (
          lib.filter ({ name, value }: value.enable) (lib.attrsToList attrs)
        )
      );
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
      type = lib.types.path;
      # "Stars over the Dunes and Mount Herard" by NPS/Patrick Myers, public domain:
      # https://commons.wikimedia.org/wiki/File:Stars_over_the_Dunes_and_Mount_Herard_(52548424900).jpg
      default = ./background.jpg;
      defaultText = lib.literalExpression "./background.jpg";
    };
    assets = lib.mkOption {
      description = "Assets to embed in the homepage image, <EMBEDDED-NAME> -> <PATH>";
      type = lib.types.attrsOf lib.types.path;
      default = { };
    };
    widgets = lib.mkOption {
      description = "Information widgets to add to homepage, <TYPE> -> <SETTINGS>";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "the widget";
            sort = lib.mkOption {
              description = "Sorting key of the widget";
              type = lib.types.int;
              default = 100;
            };
            settings = lib.mkOption {
              description = "Widget settings";
              type = lib.types.attrsOf lib.types.anything;
              default = { };
            };
          };
        }
      );
      default = { };
    };
    services = lib.mkOption {
      description = "Services to add to homepage. The structure is <SECTION>.<NAME>.{SETTINGS}";
      type = lib.types.attrsOf (
        lib.types.attrsOf (
          lib.types.submodule {
            options = {
              enable = lib.mkEnableOption "the service";
              sort = lib.mkOption {
                description = "Sorting key of the service";
                type = lib.types.int;
                default = 100;
              };
              description = lib.mkOption {
                description = "Description of the service";
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
              href = lib.mkOption {
                description = "Link to the service";
                type = lib.types.str;
              };
              icon = lib.mkOption {
                description = "Reference to an icon";
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
              widgets = lib.mkOption {
                description = "Widget configurations";
                type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
                default = [ ];
              };
            };
          }
        )
      );
      default = { };
    };
    bookmarks = lib.mkOption {
      description = "Bookmarks to add to homepage. The structure is <SECTION>.<NAME>.{SETTINGS}";
      type = lib.types.attrsOf (
        lib.types.attrsOf (
          lib.types.submodule {
            options = {
              enable = lib.mkEnableOption "the bookmark";
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
                description = "Reference to an icon";
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
    homelab.homepage.assets.${backgroundAsset} = cfg.backgroundImage;
    services.k3s.images = [ image ];
    services.k3s.manifests.homepage-static.source = ./homepage.yaml;
    homelab.kubernetes.submodules.instances.homepage = {
      submodule = "workload";
      args = {
        allowEgress = [ "apiserver" ] ++ cfg.allowEgress;
        ingressPort = 3000;
        gateway.subdomain = null;
        ports.web = 3000;
        container = {
          image = "${image.buildArgs.name}:${image.imageTag}";
          imagePullPolicy = "Never";
          # Make all referenced env vars optional. Homepage can handle some values not being present
          env =
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
              else if lib.isAttrs spec then
                spec
              else
                { value = spec; }
            ) cfg.envByName)
            // {
              HOMEPAGE_ALLOWED_HOSTS.value = ccfg.domain;
              PUID.value = "1000";
              PGID.value = "1000";
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
          livenessProbe.httpGet.port = "web";
          readinessProbe.httpGet.port = "web";
          volumeMounts =
            lib.genAttrs' [
              "custom.js"
              "custom.css"
              "bookmarks.yaml"
              "docker.yaml"
              "kubernetes.yaml"
              "proxmox.yaml"
              "services.yaml"
              "settings.yaml"
              "widgets.yaml"
            ] (filename: lib.nameValuePair "/app/config/${filename}" {
              name = "config";
              subPath = filename;
            })
            // {
              "/app/.next/server/pages".name = "pages";
              "/app/config/logs".name = "logs";
            };
        };
      };
      config.kubernetes.resources = {
        configMaps.homepage.data = {
          "kubernetes.yaml" = builtins.toJSON { mode = "cluster"; };
          "bookmarks.yaml" = builtins.toJSON (
            lib.mapAttrsToList (category: contents: {
              "${category}" = map ({ name, value }: { "${name}" = [ value ]; }) (toSortedList contents);
            }) cfg.bookmarks
          );
          "services.yaml" = builtins.toJSON (
            lib.mapAttrsToList (category: contents: {
              "${category}" = map ({ name, value }: {
                ${name} = value;
              }) (toSortedList contents);
            }) cfg.services
          );
          "widgets.yaml" = builtins.toJSON (
            map (
              { name, value }:
              {
                ${name} = value.settings;
              }
            ) (toSortedList cfg.widgets)
          );
          "docker.yaml" = "";
          "settings.yaml" = builtins.toJSON {
            disableUpdateCheck = true;
            background = "/assets/${backgroundAsset}";
            cardBlur = "xs";
            # The module repos declare the sections, so with none of them there are none
            layout = map (
              { name, value }:
              {
                ${name} =
                  if value ? layout then
                    (lib.removeAttrs value.layout [ "additionalSettings" ]) // value.layout.additionalSettings or { }
                  else
                    { };
              }
            ) (toSortedList (cfg.sections or { }));
          };
          "proxmox.yaml" = "";
          "custom.css" = "";
          "custom.js" = "";
        };
        deployments.homepage.spec.template.spec = {
          serviceAccountName = "homepage";
          volumes = {
            config.configMap.name = "homepage";
            logs.emptyDir = { };
            pages.emptyDir = { };
          };
        };
      };
    };
  };
}
