#!/usr/bin/env bash
# Run shogg's integration tests against a local Radicale instance.
#
# Seeds the storage, starts Radicale in the background (unless something is
# already listening on CALDAV_HOST), waits until it answers, runs the gated
# integration tests with SHOGG_INTEGRATION=1 and tears the server down again
# — but only if we started it.
set -euo pipefail

: "${DEVENV_STATE:?DEVENV_STATE is not set, run this through devenv}"
: "${CALDAV_HOST:?CALDAV_HOST is not set, run this through devenv}"

root="$(cd "$(dirname "$0")/.." && pwd)"
# e.g. http://localhost:5233 -> http://localhost:5233/
base="${CALDAV_HOST%/}"

started_pid=""
cleanup() {
  if [ -n "$started_pid" ]; then
    kill "$started_pid" 2>/dev/null || true
    wait "$started_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

up() {
  # Any HTTP answer (even a 404) means the server accepts connections.
  curl --silent --output /dev/null --max-time 2 "$base/.well-known/caldav"
}

echo "seeding radicale storage ..."
bash "$root/dev/radicale-seed.sh"

if up; then
  echo "reusing radicale already listening on $CALDAV_HOST"
else
  echo "starting radicale on $CALDAV_HOST ..."
  bash "$root/dev/radicale-start.sh" &
  started_pid=$!
  for _ in $(seq 1 50); do
    if up; then break; fi
    sleep 0.2
  done
  if ! up; then
    echo "radicale did not become ready on $CALDAV_HOST" >&2
    exit 1
  fi
fi

cd "$root/shogg"
SHOGG_INTEGRATION=1 gleam test
