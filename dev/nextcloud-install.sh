#!/usr/bin/env bash
# Install the local Nextcloud instance (sqlite, no browser needed) into
# $DEVENV_STATE/nextcloud. Idempotent: exits early once config/config.php
# exists. Run through devenv as the `nextcloud:install` task.
set -euo pipefail

: "${DEVENV_STATE:?run this script through devenv}"
: "${NEXTCLOUD_ROOT:?NEXTCLOUD_ROOT must point at the nextcloud package}"
: "${NEXTCLOUD_USERNAME:?NEXTCLOUD_USERNAME must be set}"
: "${NEXTCLOUD_PASSWORD:?NEXTCLOUD_PASSWORD must be set}"

export NEXTCLOUD_CONFIG_DIR="$DEVENV_STATE/nextcloud/config"
data_dir="$DEVENV_STATE/nextcloud/data"

if [ -f "$NEXTCLOUD_CONFIG_DIR/config.php" ]; then
  echo "Nextcloud is already installed ($NEXTCLOUD_CONFIG_DIR/config.php exists)"
  exit 0
fi

mkdir -p "$NEXTCLOUD_CONFIG_DIR" "$data_dir"

php -d memory_limit=512M "$NEXTCLOUD_ROOT/occ" maintenance:install \
  --database sqlite \
  --data-dir "$data_dir" \
  --admin-user "$NEXTCLOUD_USERNAME" \
  --admin-pass "$NEXTCLOUD_PASSWORD"

# Nextcloud rejects requests to untrusted domains, so allow the listen
# address of the dev server.
host_port="${NEXTCLOUD_HOST#*://}"
php "$NEXTCLOUD_ROOT/occ" config:system:set trusted_domains 0 --value "$host_port"
php "$NEXTCLOUD_ROOT/occ" config:system:set overwrite.cli.url --value "$NEXTCLOUD_HOST"

echo "Nextcloud installed at $NEXTCLOUD_HOST"
