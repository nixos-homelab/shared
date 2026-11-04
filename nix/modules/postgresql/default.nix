{ inputs, self, ... }:
{
  lib,
  pkgs,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.postgresql;
  dbBackups = lib.filterAttrs (serviceName: spec: spec.backup.enable) cfg.databases;
  passwordSource = username: "POSTGRESQL_PASSWORD_${lib.toUpper username}";
  passwordRef = username: {
    valueFrom.secretKeyRef = {
      name = "${username}-password";
      key = "password";
    };
  };
  entrypoint = pkgs.stdenvNoCC.mkDerivation {
    name = "docker-entrypoint";
    phases = [ "installPhase" ];
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin"
      cat ${cfg.image.entrypoint} > "$out/bin/docker-entrypoint.sh"
      chmod +x "$out/bin/docker-entrypoint.sh"
      runHook postInstall
    '';
    meta.mainProgram = "docker-entrypoint.sh";
  };
  pgdatadir = "/var/lib/postgresql/${builtins.elemAt (builtins.splitVersion cfg.image.package.version) 0}/docker";
  image = pkgs.dockerTools.buildImage {
    name = "cluster.local/postgresql";
    copyToRoot = [
      pkgs.dockerTools.usrBinEnv
      pkgs.bash
      pkgs.coreutils
      pkgs.gosu
      pkgs.glibcLocalesUtf8
      pkgs.findutils
      (cfg.image.package.withPackages (p: (map (e: p.${e}) cfg.image.extensions)))
      entrypoint
    ]
    ++ lib.optionals cfg.debug ccfg.debugTools;
    runAsRoot = ''
      #!${pkgs.runtimeShell}
      ${pkgs.dockerTools.shadowSetup}
      groupadd -r -g ${toString config.kubetree.workload-macros.securityContext.runAsUser} postgres
      useradd -r -u ${toString config.kubetree.workload-macros.securityContext.runAsGroup} -g postgres -d ${pgdatadir} postgres
      mkdir -p /docker-entrypoint-initdb.d
      mkdir -p /etc/postgresql
      mkdir -p /run/postgresql
      mkdir -p /var
      ln -s ../run /var/run
    '';
    config.Env = [
      "PATH=/bin:/usr/bin:/usr/local/bin"
      "PGDATA=${pgdatadir}"
      "LOCALE_ARCHIVE=${pkgs.glibcLocalesUtf8}/lib/locale/locale-archive"
    ];
    config.Entrypoint = [ (lib.getExe entrypoint) ];
    config.Cmd = [ "postgres" ];
  };
in
{
  key = "${toString __curPos.file}#modules.nixos.postgresql";
  options.homelab.postgresql = {
    enable = lib.mkEnableOption "PostgreSQL";
    debug = lib.mkEnableOption "debug mode";
    dumpsVolume = lib.mkOption {
      description = "Volume source (as specificed on the pod spec) to place database dumps in";
      type = lib.types.attrsOf lib.types.anything;
    };
    databases = lib.mkOption {
      description = "Databases to create and backup, indexed by serviceName";
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }@module:
          {
            options = {
              dbName = lib.mkOption {
                description = "Name of the database";
                type = lib.types.nullOr lib.types.str;
                defaultText = "`<serviceName>`";
                default = name;
              };
              username = lib.mkOption {
                description = "Database username";
                type = lib.types.nullOr lib.types.str;
                defaultText = "`<dbName>`";
                default = module.config.dbName;
              };
              backup = {
                enable = lib.mkEnableOption "backup of the database";
                schedule = lib.mkOption {
                  description = "Cronjob notation of when the database should be dumped";
                  type = lib.types.nullOr lib.types.str;
                  default = "10 3 * * *";
                  example = "10 3 * * *";
                };
              };
              setupCommands = lib.mkOption {
                description = "Commands to run as a superuser in the database right after it has been created";
                type = lib.types.listOf lib.types.str;
                default = [ ];
              };
            };
          }
        )
      );
    };
    extraSettings = lib.mkOption {
      description = "Additional postgresql.conf settings";
      type = lib.types.lines;
      default = [ ];
    };
    image.entrypoint = lib.mkOption {
      description = "The docker-entrypoint to install";
      type = lib.types.package;
      default = pkgs.fetchurl {
        name = "docker-entrypoint.sh";
        url = "https://raw.githubusercontent.com/docker-library/postgres/62a714f93cc32220de46fd12235c9d509e3b1ad6/18/trixie/docker-entrypoint.sh";
        hash = "sha256-nEQCma4EoKedVbi/AzBwNtiQpAl50vtpgHPJBQ1LIKU=";
      };
      defaultText = "The entrypoint from the official image";
    };
    image.package = lib.mkPackageOption pkgs "postgresql_18" { };
    image.extensions = lib.mkOption {
      description = "List of postgresql extensions to include in the image";
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
  };
  imports = [ inputs.setup-secrets.nixosModules.default ];
  config = lib.mkIf cfg.enable {
    services.k3s.images = [ image ];
    # A password is generated only when its Secret is missing, never when the API call fails
    setup-secrets.sources = lib.listToAttrs (
      map (
        username:
        lib.nameValuePair (passwordSource username) {
          description = "PostgreSQL password of ${username}";
          cmd = self.lib.setup-secrets.mkScript pkgs ''
            if [[ -n $(kubectl -n postgresql get secret ${username}-password --ignore-not-found -oname) ]]; then
              getKubeSecret postgresql ${username}-password password
            else
              head -c 1024 /dev/urandom | tr -dc A-Za-z0-9 | head -c 32
            fi
          '';
        }
      ) ([ "postgres" ] ++ lib.mapAttrsToList (serviceName: spec: spec.username) cfg.databases)
    );
    # The consumer reads its password from a Secret in its own namespace, named after the serviceName
    setup-secrets.destinations = [
      {
        logPrefix = "PostgreSQL password of postgres";
        requires = [ (passwordSource "postgres") ];
        cmd = self.lib.setup-secrets.mkScript pkgs ''
          setKubeSecret postgresql postgres-password password "''${${passwordSource "postgres"}:?}"
        '';
      }
    ]
    ++ lib.mapAttrsToList (serviceName: spec: {
      logPrefix = "PostgreSQL password of ${spec.username}";
      requires = [ (passwordSource spec.username) ];
      cmd = self.lib.setup-secrets.mkScript pkgs ''
        setKubeSecret postgresql ${spec.username}-password password "''${${passwordSource spec.username}:?}"
        setKubeSecret ${serviceName} postgresql-password password "''${${passwordSource spec.username}:?}"
      '';
    }) cfg.databases;
    homelab.cluster.backup.volumes.postgresql.database-dumps = lib.mapAttrsToList (
      serviceName: spec: "/${spec.dbName}.pgdump"
    ) dbBackups;

    kubetree.resources.postgresql = {
      config = {
        apiVersion = "v1";
        kind = "ConfigMap";
        metadata.name = "postgresql";
        metadata.namespace = "postgresql";
        # The include in POSTGRES_INITDB_ARGS fails initdb's probes, which then fall back to 20 connections and
        # 400kB of buffers; it comes after them in postgresql.conf, so these are what initdb picks otherwise
        data."postgresql.conf" = ''
          listen_addresses = '*'
          max_connections = 100
          shared_buffers = 128MB
          ${cfg.extraSettings}
        '';
      };
      workload = {
        apiVersion = "cluster.local";
        kind = "WorkloadMacro";
        metadata.name = "postgresql";
        spec = {
          dataPath = "/var/lib/postgresql";
          podSpecMacro = {
            mainContainer = {
              image = "${image.buildArgs.name}:${image.imageTag}";
              imagePullPolicy = "Never";
              lifecycle.stopSignal = "SIGINT";
              # POSTGRES_PASSWORD only applies at initdb, so the Secret's password is set on every start too.
              # The temporary server initdb starts takes it as well, and the loop outlasts its shutdown.
              lifecycle.postStart.exec.command = [
                "bash"
                "-c"
                ''
                  until psql --no-psqlrc -qh /run/postgresql -U postgres -v ON_ERROR_STOP=1 >/dev/null <<'EOF'
                  \getenv pw POSTGRES_PASSWORD
                  ALTER USER postgres PASSWORD :'pw'
                  EOF
                  do sleep 1; done
                ''
              ];
              envByName.POSTGRES_PASSWORD = passwordRef "postgres";
              envByName.POSTGRES_INITDB_ARGS = "-c include='/etc/postgresql/postgresql.conf'";
              portsByName.postgresql = 5432;
              volumeMountsByPath = {
                "/etc/postgresql" = "config";
                "/run/postgresql" = "run";
                "/tmp" = "tmp";
              };
              livenessProbe.tcpSocket.port = "postgresql";
              readinessProbe.tcpSocket.port = "postgresql";
            };
            volumesByName = {
              config.configMap.name = "postgresql";
              run.emptyDir = { };
              tmp.emptyDir = { };
            };
          };
        };
      };
    };
    kubetree.resources.postgresql-databases =
      (lib.mapAttrs' (
        serviceName: spec:
        let
          jobName = "create-${spec.dbName}-db";
        in
        {
          name = jobName;
          value = {
            apiVersion = "cluster.local";
            kind = "JobMacro";
            metadata.namespace = "postgresql";
            metadata.name = jobName;
            spec.allowEgress = [ "postgresql" ];
            spec.podSpecMacro = {
              restartPolicy = "OnFailure";
              mainContainer = {
                image = "${image.buildArgs.name}:${image.imageTag}";
                imagePullPolicy = "Never";
                command = [
                  "bash"
                  "-ec"
                ];
                args = [
                  (lib.join "\n" (
                    map (cmd: ''psql --no-psqlrc --set ON_ERROR_STOP=1 --pset pager=off -f <(printf "%s" "${cmd}")'') ([
                      "SELECT 'CREATE USER ${spec.username}' WHERE NOT EXISTS (SELECT FROM pg_user WHERE usename = '${spec.username}')\\gexec"
                      "\\getenv pw USER_PASSWORD\nALTER USER ${spec.username} PASSWORD :'pw'"
                      "SELECT 'CREATE DATABASE ${spec.dbName}' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${spec.dbName}')\\gexec"
                      "ALTER DATABASE ${spec.dbName} OWNER TO ${spec.username}"
                    ])
                    ++ map (
                      cmd:
                      ''psql --no-psqlrc --set ON_ERROR_STOP=1 --pset pager=off -d ${spec.dbName} -f <(printf "%s" "${cmd}")''
                    ) (spec.setupCommands)
                  ))
                ];
                envByName = {
                  PGHOST = "postgresql.postgresql";
                  PGUSER = "postgres";
                  PGPASSWORD = passwordRef "postgres";
                  USER_PASSWORD = passwordRef spec.username;
                };
              };
            };
          };
        }
      ) cfg.databases)
      // (lib.mapAttrs' (
        serviceName: spec:
        let
          jobName = "backup-${spec.dbName}-db";
        in
        {
          name = jobName;
          value = {
            apiVersion = "cluster.local";
            kind = "CronJobMacro";
            metadata.namespace = "postgresql";
            metadata.name = jobName;
            spec.schedule = spec.backup.schedule;
            spec = {
              allowEgress = [ "postgresql" ];
              podSpecMacro.mainContainer = {
                image = "${image.buildArgs.name}:${image.imageTag}";
                command = [ "pg_dump" ];
                args = [
                  "--username=postgres"
                  "--dbname=${spec.dbName}"
                  "--blobs"
                  "--quote-all-identifiers"
                  "--format=custom"
                  "--file=/dumps/${spec.dbName}.pgdump"
                ];
                envByName = {
                  PGHOST = "postgresql.postgresql";
                  PGUSER = "postgres";
                  PGPASSWORD = passwordRef "postgres";
                };
                volumeMountsByPath."/dumps" = "data";
              };
              podSpecMacro.volumesByName.data.persistentVolumeClaim.claimName = "database-dumps";
            };
          };
        }
      ) dbBackups)
      // {
        data = {
          apiVersion = "v1";
          kind = "PersistentVolumeClaim";
          metadata.namespace = "postgresql";
          metadata.name = "database-dumps";
          spec = {
            accessModes = [ "ReadWriteOnce" ];
            resources.requests.storage = "1Gi";
            volumeMode = "Filesystem";
          };
        };
      };
  };
}
