#!/usr/bin/env bash
# Copy the committed sample CalDAV data into the local Radicale storage.
set -eu

: "${DEVENV_STATE:?DEVENV_STATE is not set, run this through devenv}"

script_dir="$(cd "$(dirname "$0")" && pwd)"
dest="$DEVENV_STATE/radicale/storage/collection-root"

mkdir -p "$dest"
cp -R "$script_dir/seed/collection-root/." "$dest/"
