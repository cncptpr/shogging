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
  ];

  languages.javascript = {
    enable = true;
    directory = "${config.devenv.root}/server";
    npm = {
      enable = true;
      install.enable = true;
    };
  };

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

    "server:tailwindcss" = {
      description = "Build the tailwind css for the server";
      cwd = "${config.devenv.root}/server";
      exec = ''
        if [ ! -d node_modules ] || [ package-lock.json -nt node_modules ]; then
          npm ci
        fi
        ./node_modules/.bin/tailwindcss -i ./src/css/app.css -o ./priv/tailwind.css
      '';
    };

    "server:dev" = {
      description = "Run the dev server for shogging";
      cwd = "${config.devenv.root}/server";
      exec = "gleam run";
      after = [ "server:tailwindcss" ];
    };

    "shogg:test" = {
      description = "Run the tests for shogg";
      cwd = "${config.devenv.root}/shogg";
      exec = "gleam test";
    };
  };

  processes.radicale = {
    exec = ''bash "${config.devenv.root}/dev/radicale-start.sh"'';
  };
}
