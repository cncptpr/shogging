{
  pkgs,
  config,
  ...
}:

{
  packages = with pkgs; [
    gleam
    beamPackages.erlang
    rebar3
    git
    radicale
    curl
    # The frontend needs JS tooling: `bun` bundles the app, `tailwindcss_4`
    # builds its stylesheet, `nodejs` runs `gleam test` for the client package.
    bun
    tailwindcss_4
    nodejs
  ];

  # CalDAV backend for local development. `processes.radicale` serves this on
  # localhost:5233 (5232 is already taken by another project on this machine)
  # and is seeded with sample tasks by the `radicale:seed` task.
  env = {
    CALDAV_HOST = "http://localhost:5233";
    CALDAV_USERNAME = "shogging";
    CALDAV_PASSWORD = "shogging";
    CALDAV_CALENDAR = "Shogging Test";
    CHECK_CHANGE_DELAY = "30";
  };

  tasks = {
    "radicale:seed" = {
      description = "Seed the local Radicale storage with sample tasks";
      status = ''test -f "$DEVENV_STATE/radicale/storage/collection-root/shogging/shogging-test/.Radicale.props"'';
      exec = ''bash "${config.devenv.root}/dev/radicale-seed.sh"'';
      before = [ "devenv:processes:radicale" ];
    };

    "client:dev" = {
      description = "Run the frontend dev server for shogging";
      cwd = "${config.devenv.root}/client";
      exec = "gleam run -m lustre/dev start";
    };

    "server:dev" = {
      description = "Run the dev server for shogging";
      cwd = "${config.devenv.root}/server";
      exec = "gleam run";
    };

    "shogg:test" = {
      description = "Run the tests for shogg";
      cwd = "${config.devenv.root}/shogg";
      exec = "gleam test";
    };

    "shogg:integration-test" = {
      description = "Run shogg's integration tests against a local Radicale";
      exec = ''bash "${config.devenv.root}/dev/shogg-integration-test.sh"'';
    };

    "shared:test" = {
      description = "Run the tests for the shared websocket protocol";
      cwd = "${config.devenv.root}/shared";
      exec = "gleam test";
    };

    "shogxml:test" = {
      description = "Run the tests for the pure Gleam shogxml package";
      cwd = "${config.devenv.root}/shogxml";
      exec = "gleam test";
    };
  };

  processes.radicale = {
    exec = ''bash "${config.devenv.root}/dev/radicale-start.sh"'';
  };

  # A local Nextcloud for capturing real CalDAV responses into
  # shogg/test/shogg/responses/nextcloud/ (the `nextcloud:capture` task).
  # Activated separately with `devenv --profile nextcloud ...` so the default
  # shell keeps only Radicale. State (config, sqlite, data) lives in
  # $DEVENV_STATE/nextcloud; the server itself comes from the read-only store
  # and is served by PHP's built-in dev server with dev/nextcloud-router.php
  # standing in for the .htaccess URL rewriting.
  profiles.nextcloud.module =
    { pkgs, config, ... }:
    {
      packages = [
        pkgs.nextcloud34
        pkgs.php84
      ];

      env = {
        NEXTCLOUD_HOST = "http://127.0.0.1:8081";
        NEXTCLOUD_USERNAME = "shogging";
        NEXTCLOUD_PASSWORD = "shogging";
        NEXTCLOUD_CALENDAR = "Shogging Test";
        NEXTCLOUD_ROOT = "${pkgs.nextcloud34}";
      };

      tasks = {
        # Offline `occ maintenance:install`; runs before the server starts so
        # a fresh `devenv --profile nextcloud up` is usable out of the box.
        "nextcloud:install" = {
          description = "Install the local Nextcloud instance into $DEVENV_STATE";
          status = ''test -f "$DEVENV_STATE/nextcloud/config/config.php"'';
          exec = ''bash "${config.devenv.root}/dev/nextcloud-install.sh"'';
          before = [ "devenv:processes:nextcloud" ];
        };

        # Seed over HTTP, so it waits until the process reports ready. Only
        # runs when invoked directly (it is downstream of the process).
        "nextcloud:seed" = {
          description = "Create the test calendars and upload the sample tasks";
          status = ''test -f "$DEVENV_STATE/nextcloud/.seeded"'';
          exec = ''bash "${config.devenv.root}/dev/nextcloud-seed.sh"'';
          after = [ "devenv:processes:nextcloud" ];
        };

        # Pulls in the server (and install + seed) as dependencies, so
        # `devenv --profile nextcloud tasks run nextcloud:capture` captures
        # everything from a cold start.
        "nextcloud:capture" = {
          description = "Capture local_* CalDAV response fixtures for the shogg tests";
          exec = ''bash "${config.devenv.root}/dev/nextcloud-capture.sh"'';
          after = [ "nextcloud:seed" ];
        };
      };

      processes.nextcloud = {
        exec = ''bash "${config.devenv.root}/dev/nextcloud-start.sh"'';
        ready.http.get = {
          port = 8081;
          path = "/status.php";
        };
      };
    };
}
