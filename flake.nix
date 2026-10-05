{
  description = "shogging — a shogg client over CalDAV";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Generic builder for Gleam applications. It reads `gleam.toml` and
    # `manifest.toml` out of `src` and fetches the Hex and git dependencies
    # itself, so the build never reaches for the network.
    #
    # The `fix/local-packages` branch, which is this repository rebased onto
    # upstream `main` with fixes for local and git dependencies. Upstream alone
    # stages neither, so a package with a path dependency or a git dependency
    # fails to build: Gleam decides the dependency was never downloaded and
    # reaches for the network, which the sandbox does not have.
    nix-gleam = {
      url = "github:cncptpr/nix-gleam?ref=fix/local-packages";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-gleam,
    }:
    let
      systems = lib.systems.flakeExposed;
      lib = nixpkgs.lib;
      forAllSystems = f: lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (
        system: pkgs:
        let
          inherit (nix-gleam.packages.${system}) buildGleamApplication;

          frontend = buildGleamApplication {
            src = ./client;
            localPackages = [ ./shared ];

            nativeBuildInputs = with pkgs; [
              nodejs
              beamPackages.erlang
              beamPackages.rebar3
              bun
              tailwindcss_4
            ];

            buildPhase = ''
              runHook preBuild

              gleam run -m lustre/dev build --minify=true --outdir=dist

              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall

              mkdir -p $out
              cp -r dist/. $out/

              runHook postInstall
            '';

            meta = {
              description = "Shogging web interface";
              platforms = lib.platforms.unix;
            };
          };

          # The server, with the frontend bundle baked into it.
          pkg = buildGleamApplication {
            src = ./server;

            localPackages = [
              ./shogg
              ./shared
              ./shogxml
            ];

            nativeBuildInputs = [ frontend ];

            buildPhase = ''
              runHook preBuild

              export REBAR_CACHE_DIR="$TMP/.rebar-cache"

              mkdir -p priv/static
              cp -r ${frontend}/. priv/static/

              gleam export erlang-shipment

              runHook postBuild
            '';

            meta = {
              description = "Todo list over CalDAV, with a Lustre web interface";
              longDescription = ''
                Shogging keeps a CalDAV calendar in sync with a web interface that
                talks to the server over a WebSocket. The server reads its CalDAV
                credentials and the port it listens on from the environment; see
                `config.gleam`.
              '';

              mainProgram = "shogging";
              platforms = lib.platforms.unix;
            };
          };
        in
        {
          default = pkg;
          shogging = pkg;
          shogging-frontend = frontend;
        }
      );

      nixosModules = rec {
        default = shogging;
        shogging =
          {
            config,
            lib,
            pkgs,
            ...
          }:
          let
            cfg = config.services.shogging;
          in
          {
            options.services.shogging = {
              enable = lib.mkEnableOption "the shogging service";

              package = lib.mkOption {
                type = lib.types.package;
                default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
                defaultText = lib.literalExpression "self.packages.\${pkgs.stdenv.hostPlatform.system}.default";
                description = "The shogging package to run.";
              };

              user = lib.mkOption {
                type = lib.types.str;
                default = "shogging";
                description = "User account under which the service runs.";
              };

              group = lib.mkOption {
                type = lib.types.str;
                default = "shogging";
                description = "Group owning the files of the service.";
              };

              port = lib.mkOption {
                type = lib.types.port;
                default = 1234;
                description = ''
                  Port the server listens on, passed as `SHOGGING_PORT`. The
                  server binds all addresses, so this is also the port to
                  reach it on.
                '';
              };

              openFirewall = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Whether to open the port in the firewall.";
              };

              caldav = {
                host = lib.mkOption {
                  type = lib.types.str;
                  description = ''
                    Base URL of the CalDAV server, passed as `CALDAV_HOST`. An
                    explicit `http://` selects plain HTTP, anything else is
                    taken as HTTPS.

                    If server supports `.well-known` convention, then the host
                    does not need to contain the full path.
                  '';
                  example = "https://cloud.example.com/remote.php/dav";
                };

                username = lib.mkOption {
                  type = lib.types.str;
                  description = "CalDAV account name, passed as `CALDAV_USERNAME`.";
                  example = "alice";
                };

                passwordFile = lib.mkOption {
                  type = lib.types.path;
                  description = ''
                    Path to a file holding the CalDAV account password, handed
                    to the service as `CALDAV_PASSWORD`.

                    It holds one `KEY=value` line:

                        CALDAV_PASSWORD=hunter2

                    Note that this is a systemd `EnvironmentFile`, so the value
                    follows systemd's rules for quoting rather than the shell's.
                  '';
                  example = "/etc/shogging/password";
                };

                calendar = lib.mkOption {
                  type = lib.types.str;
                  description = ''
                    Name of the calendar to show, passed as `CALDAV_CALENDAR`.
                    It is matched against the calendars the server reports, so
                    it is the display name rather than a URL.
                  '';
                  example = "Todos";
                };
              };

              checkChangeDelay = lib.mkOption {
                type = lib.types.ints.positive;
                default = 30;
                description = ''
                  How many seconds to wait between polls of the CalDAV server,
                  passed as `CHECK_CHANGE_DELAY`.
                '';
              };

              motto = lib.mkOption {
                type = lib.types.str;
                default = "Kaufe das Zeug!!!";
                description = ''
                  The line under the title, passed as `SHOGGING_MOTTO`. It is
                  baked into the page when the server starts, so changing it
                  needs a restart rather than a frontend rebuild.
                '';
              };

              extraEnvironment = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = { };
                description = ''
                  Additional environment variables for the service, for
                  anything this module does not model.
                '';
              };
            };

            config = lib.mkIf cfg.enable {
              users.users.${cfg.user} = {
                isSystemUser = true;
                group = cfg.group;
                description = "shogging service user";
              };
              users.groups.${cfg.group} = { };

              systemd.services.shogging = {
                description = "shogging todo service";
                wantedBy = [ "multi-user.target" ];
                after = [ "network-online.target" ];
                wants = [ "network-online.target" ];

                serviceConfig = {
                  Type = "simple";
                  ExecStart = lib.getExe cfg.package;
                  User = cfg.user;
                  Group = cfg.group;
                  Restart = "on-failure";
                  RestartSec = "5s";
                  StateDirectory = cfg.user;

                  EnvironmentFile = cfg.caldav.passwordFile;

                  # Hardening.
                  NoNewPrivileges = true;
                  PrivateTmp = true;
                  PrivateDevices = true;
                  ProtectSystem = "strict";
                  ProtectHome = true;
                  ProtectProc = "invisible";
                  ProcSubset = "pid";
                  ProtectClock = true;
                  ProtectHostname = true;
                  ProtectKernelLogs = true;
                  ProtectKernelModules = true;
                  ProtectKernelTunables = true;
                  ProtectControlGroups = true;
                  RestrictAddressFamilies = [
                    "AF_UNIX"
                    "AF_INET"
                    "AF_INET6"
                  ];
                  RestrictNamespaces = true;
                  RestrictRealtime = true;
                  RestrictSUIDSGID = true;
                  LockPersonality = true;
                  MemoryDenyWriteExecute = true;
                  SystemCallArchitectures = "native";
                  SystemCallFilter = [
                    "@system-service"
                    "~@privileged"
                    "~@resources"
                  ];
                };

                environment = {
                  SHOGGING_PORT = toString cfg.port;
                  CHECK_CHANGE_DELAY = toString cfg.checkChangeDelay;
                  SHOGGING_MOTTO = cfg.motto;
                  CALDAV_HOST = cfg.caldav.host;
                  CALDAV_USERNAME = cfg.caldav.username;
                  CALDAV_CALENDAR = cfg.caldav.calendar;
                }
                // cfg.extraEnvironment;

              };

              networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
            };
          };
      };
    };
}
