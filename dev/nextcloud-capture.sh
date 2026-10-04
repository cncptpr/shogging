#!/usr/bin/env bash
# Capture real CalDAV responses from the local Nextcloud and store them as
# `local_*` fixtures in shogg/test/shogg/responses/nextcloud/.
#
# The request bodies are copied verbatim from shogg/src so the fixtures carry
# exactly the exchanges the library performs: discovery (well-known redirect,
# principal, home set), calendar listing, ctag checks, a task REPORT and the
# create/update/delete lifecycle. Run as the `nextcloud:capture` task; needs
# the server and the seeded calendars.
set -euo pipefail

: "${DEVENV_STATE:?run this script through devenv}"
: "${NEXTCLOUD_HOST:?NEXTCLOUD_HOST must be set, e.g. http://127.0.0.1:8081}"
: "${NEXTCLOUD_USERNAME:?NEXTCLOUD_USERNAME must be set}"
: "${NEXTCLOUD_PASSWORD:?NEXTCLOUD_PASSWORD must be set}"

script_dir="$(cd "$(dirname "$0")" && pwd)"
out="$script_dir/../shogg/test/shogg/responses/nextcloud"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

user="$NEXTCLOUD_USERNAME"
auth="$NEXTCLOUD_USERNAME:$NEXTCLOUD_PASSWORD"
dav="$NEXTCLOUD_HOST/remote.php/dav"
principal="$dav/principals/users/$user"
home="$dav/calendars/$user"
cal="$home/shogging-test"
empty="$home/shogging-empty"
xml_ct='Content-Type: application/xml; charset=utf-8'

# --- Request bodies, copied from shogg/src ---

user_info_body='<?xml version="1.0" encoding="utf-8" ?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:current-user-principal/>
  </D:prop>
</D:propfind>'

home_set_body='<?xml version="1.0" encoding="utf-8" ?>
<D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop>
    <C:calendar-home-set/>
  </D:prop>
</D:propfind>'

calendars_body='<d:propfind xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:apple="http://apple.com/ns:ical/">
        <d:prop>
          <d:resourcetype/>
          <d:displayname/>
          <cs:getctag/>
          <c:supported-calendar-component-set/>
          <apple:calendar-color/>
        </d:prop>
      </d:propfind>'

changed_body='<d:propfind xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/">
      <d:prop>
        <cs:getctag/>
      </d:prop>
    </d:propfind>'

tasks_body='<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
      <d:prop>
        <d:getetag/>
        <c:calendar-data/>
      </d:prop>
      <c:filter>
        <c:comp-filter name="VCALENDAR">
          <c:comp-filter name="VTODO"/>
        </c:comp-filter>
      </c:filter>
    </c:calendar-query>'

getetag_body='<?xml version="1.0" encoding="utf-8" ?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:getetag/>
  </D:prop>
</D:propfind>'

# --- Helpers ---

http_status() {
  # First line of a `curl -i` capture: "HTTP/1.1 204 No Content"
  head -n 1 "$1" | tr -d '\r' | awk '{print $2}'
}

fetch_raw() {
  local file="$1"
  shift
  curl -sS -u "$auth" -i -o "$file" "$@"
  echo "  $(basename "$file"): HTTP $(http_status "$file")"
}

fetch_body() {
  local file="$1"
  shift
  local code
  code=$(curl -sS -u "$auth" -o "$file" -w '%{http_code}' "$@")
  echo "  $(basename "$file"): HTTP $code"
  case "$code" in
    2* | 3*) ;;
    *)
      echo "unexpected HTTP $code for $file" >&2
      exit 1
      ;;
  esac
}

header_etag() {
  # ETag from a raw capture, e.g. `ETag: "6f8f..."` -> `"6f8f..."`
  tr -d '\r' <"$1" | sed -n 's/^[Ee][Tt][Aa][Gg]: *//p' | head -n 1
}

current_etag() {
  # Fallback: ask the server for the object's current getetag.
  curl -sS -u "$auth" -X PROPFIND -H 'Depth: 0' -H "$xml_ct" \
    --data "$getetag_body" "$1" |
    grep -io '<[^>]*getetag>[^<]*' | head -n 1 | sed 's/.*>//'
}

# --- Capture ---

for _ in $(seq 1 60); do
  curl -sf -o /dev/null "$NEXTCLOUD_HOST/status.php" && break
  sleep 1
done
if ! curl -sf -o /dev/null "$NEXTCLOUD_HOST/status.php"; then
  echo "Nextcloud is not reachable at $NEXTCLOUD_HOST" >&2
  exit 1
fi

mkdir -p "$out"
echo "Capturing Nextcloud CalDAV responses from $NEXTCLOUD_HOST"

# Discovery: shogg follows this redirect to learn the DAV base path.
fetch_raw "$out/local_server_info.txt" "$NEXTCLOUD_HOST/.well-known/caldav"

fetch_body "$out/local_user_info.xml" -X PROPFIND -H 'Depth: 1' \
  -H "$xml_ct" --data "$user_info_body" "$dav/"

fetch_body "$out/local_calendar_home_set.xml" -X PROPFIND -H 'Depth: 0' \
  -H "$xml_ct" --data "$home_set_body" "$principal"

fetch_body "$out/local_calendars.xml" -X PROPFIND -H 'Depth: 1' \
  -H "$xml_ct" --data "$calendars_body" "$home"

# Same ctag the calendars listing reports: `parse_changed` must see no change.
fetch_body "$out/local_calendar_unchanged.xml" -X PROPFIND -H 'Depth: 0' \
  -H "$xml_ct" --data "$changed_body" "$cal"

fetch_body "$out/local_tasks.xml" -X REPORT -H 'Depth: 1' \
  -H "$xml_ct" --data "$tasks_body" "$cal"

fetch_raw "$out/local_report_empty.txt" -X REPORT -H 'Depth: 1' \
  -H "$xml_ct" --data "$tasks_body" "$empty"

# Create a scratch task, update it, refuse a stale update, then delete it.
printf '%s\r\n' \
  'BEGIN:VCALENDAR' \
  'VERSION:2.0' \
  'CALSCALE:GREGORIAN' \
  'PRODID:-//Shogg//EN' \
  'BEGIN:VTODO' \
  'UID:local-capture-task' \
  'DTSTAMP:20261004T120000Z' \
  'CREATED:20261004T120000Z' \
  'STATUS:NEEDS-ACTION' \
  'SUMMARY:Local capture task' \
  'END:VTODO' \
  'END:VCALENDAR' >"$tmp/create.ics"

printf '%s\r\n' \
  'BEGIN:VCALENDAR' \
  'VERSION:2.0' \
  'CALSCALE:GREGORIAN' \
  'PRODID:-//Shogg//EN' \
  'BEGIN:VTODO' \
  'UID:local-capture-task' \
  'DTSTAMP:20261004T120000Z' \
  'CREATED:20261004T120000Z' \
  'LAST-MODIFIED:20261004T120500Z' \
  'STATUS:IN-PROCESS' \
  'SUMMARY:Local capture task (updated)' \
  'END:VTODO' \
  'END:VCALENDAR' >"$tmp/update.ics"

fetch_raw "$out/local_create_task.txt" -X PUT \
  -H 'Content-Type: text/calendar; charset=utf-8' \
  -H 'If-None-Match: *' \
  --data-binary "@$tmp/create.ics" \
  "$cal/local-capture-task.ics"

etag="$(header_etag "$out/local_create_task.txt")"
if [ -z "$etag" ]; then
  etag="$(current_etag "$cal/local-capture-task.ics")"
fi
if [ -z "$etag" ]; then
  echo "could not determine the ETag of the created task" >&2
  exit 1
fi

fetch_raw "$out/local_update_task.txt" -X PUT \
  -H 'Content-Type: text/calendar; charset=utf-8' \
  -H "If-Match: $etag" \
  --data-binary "@$tmp/update.ics" \
  "$cal/local-capture-task.ics"

new_etag="$(header_etag "$out/local_update_task.txt")"
if [ -z "$new_etag" ]; then
  new_etag="$(current_etag "$cal/local-capture-task.ics")"
fi
if [ -z "$new_etag" ]; then
  echo "could not determine the ETag after the update" >&2
  exit 1
fi

fetch_raw "$out/local_update_stale_etag.txt" -X PUT \
  -H 'Content-Type: text/calendar; charset=utf-8' \
  -H 'If-Match: "stale-etag-00000000"' \
  --data-binary "@$tmp/update.ics" \
  "$cal/local-capture-task.ics"

fetch_raw "$out/local_delete_task.txt" -X DELETE \
  -H "If-Match: $new_etag" \
  "$cal/local-capture-task.ics"

fetch_raw "$out/local_delete_missing.txt" -X DELETE \
  -H 'If-Match: "missing-etag-00000000"' \
  "$cal/local-capture-missing.ics"

fetch_raw "$out/local_propfind_missing.txt" -X PROPFIND -H 'Depth: 0' \
  -H "$xml_ct" --data "$changed_body" \
  "$home/nonexistent-calendar/"

# Captured after the mutations above, so its ctag differs from the one in
# local_calendars.xml and `parse_changed` must report a change.
fetch_body "$out/local_calendar_changed.xml" -X PROPFIND -H 'Depth: 0' \
  -H "$xml_ct" --data "$changed_body" "$cal"

echo "Fixtures written to $out"
