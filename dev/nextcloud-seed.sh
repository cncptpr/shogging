#!/usr/bin/env bash
# Create the test calendars in the local Nextcloud and upload the sample
# VTODO files from dev/seed. Idempotent: existing calendars are reused and
# the uploads overwrite. Run as the `nextcloud:seed` task; needs the server
# from `processes.nextcloud` running.
set -euo pipefail

: "${DEVENV_STATE:?run this script through devenv}"
: "${NEXTCLOUD_HOST:?NEXTCLOUD_HOST must be set, e.g. http://127.0.0.1:8081}"
: "${NEXTCLOUD_USERNAME:?NEXTCLOUD_USERNAME must be set}"
: "${NEXTCLOUD_PASSWORD:?NEXTCLOUD_PASSWORD must be set}"

script_dir="$(cd "$(dirname "$0")" && pwd)"
seed_dir="$script_dir/seed/collection-root/shogging/shogging-test"
marker="$DEVENV_STATE/nextcloud/.seeded"
auth="$NEXTCLOUD_USERNAME:$NEXTCLOUD_PASSWORD"
home="$NEXTCLOUD_HOST/remote.php/dav/calendars/$NEXTCLOUD_USERNAME"

# devenv waits for /status.php before this task, but stay usable when the
# script is invoked on its own.
for _ in $(seq 1 60); do
  curl -sf -o /dev/null "$NEXTCLOUD_HOST/status.php" && break
  sleep 1
done
if ! curl -sf -o /dev/null "$NEXTCLOUD_HOST/status.php"; then
  echo "Nextcloud is not reachable at $NEXTCLOUD_HOST" >&2
  exit 1
fi

mkcalendar() {
  local url="$1" displayname="$2" code
  code=$(curl -s -o /dev/null -w '%{http_code}' -u "$auth" \
    -X MKCALENDAR "$url" \
    -H 'Content-Type: application/xml; charset=utf-8' \
    --data "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<C:mkcalendar xmlns:D=\"DAV:\" xmlns:C=\"urn:ietf:params:xml:ns:caldav\">
  <D:set>
    <D:prop>
      <D:displayname>$displayname</D:displayname>
      <C:supported-calendar-component-set>
        <C:comp name=\"VTODO\"/>
      </C:supported-calendar-component-set>
    </D:prop>
  </D:set>
</C:mkcalendar>")
  # 201: created, 405: the collection already exists (Sabre refuses to
  # MKCALENDAR twice).
  case "$code" in
    201 | 405) ;;
    *)
      echo "MKCALENDAR $url failed with HTTP $code" >&2
      exit 1
      ;;
  esac
}

mkcalendar "$home/shogging-test/" "Shogging Test"
mkcalendar "$home/shogging-empty/" "Shogging Empty"

for file in "$seed_dir"/*.ics; do
  curl -sf -u "$auth" -T "$file" \
    -H 'Content-Type: text/calendar; charset=utf-8' \
    "$home/shogging-test/$(basename "$file")" > /dev/null
done

touch "$marker"
echo "Seeded $(ls "$seed_dir" | wc -l) tasks into $home/shogging-test/"
