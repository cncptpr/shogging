#!/usr/bin/env bash
# Start a local Radicale CalDAV server for development.
#
# The config file is generated into $DEVENV_STATE (gitignored) on every start
# so the storage path is absolute for this machine. Radicale only expands
# environment variables in config values on Windows, so committing a static
# config with $DEVENV_STATE in it would not work on Linux.
set -eu

: "${DEVENV_STATE:?DEVENV_STATE is not set, run this through devenv}"
: "${CALDAV_HOST:?CALDAV_HOST is not set, run this through devenv}"

state_dir="$DEVENV_STATE/radicale"
storage_dir="$state_dir/storage"
# e.g. http://localhost:5233 -> localhost:5233
listen="${CALDAV_HOST#*://}"

mkdir -p "$storage_dir"

cat > "$state_dir/config" <<EOF
[server]
hosts = $listen

[auth]
type = none

[rights]
type = owner_only

[web]
type = none

[storage]
filesystem_folder = $storage_dir
EOF

exec radicale -C "$state_dir/config"
