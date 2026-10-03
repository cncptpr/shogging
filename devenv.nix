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

    "shared:test" = {
      description = "Run the tests for the shared websocket protocol";
      cwd = "${config.devenv.root}/shared";
      exec = "gleam test";
    };
  };

  processes.radicale = {
    exec = ''bash "${config.devenv.root}/dev/radicale-start.sh"'';
  };
}
