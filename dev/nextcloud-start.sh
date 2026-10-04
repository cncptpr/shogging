#!/usr/bin/env bash
# Serve Nextcloud from the nix store with PHP's built-in server on
# NEXTCLOUD_HOST, using state directories under $DEVENV_STATE for the config
# and data (the store is read-only). Run through devenv so DEVENV_STATE and
# the NEXTCLOUD_* variables are set.
set -euo pipefail

: "${DEVENV_STATE:?run this script through devenv}"
: "${NEXTCLOUD_ROOT:?NEXTCLOUD_ROOT must point at the nextcloud package}"
: "${NEXTCLOUD_HOST:?NEXTCLOUD_HOST must be set, e.g. http://localhost:8081}"

listen="${NEXTCLOUD_HOST#*://}" # http://127.0.0.1:8081 -> 127.0.0.1:8081
script_dir="$(cd "$(dirname "$0")" && pwd)"

export NEXTCLOUD_CONFIG_DIR="$DEVENV_STATE/nextcloud/config"
export NEXTCLOUD_DATA_DIR="$DEVENV_STATE/nextcloud/data"
mkdir -p "$NEXTCLOUD_CONFIG_DIR" "$NEXTCLOUD_DATA_DIR"

exec php \
  -d memory_limit=512M \
  -d date.timezone=UTC \
  -S "$listen" \
  -t "$NEXTCLOUD_ROOT" \
  "$script_dir/nextcloud-router.php"
