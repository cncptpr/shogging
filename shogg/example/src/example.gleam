import envoy
import gleam/hackney
import gleam/http
import gleam/list
import shogg/calendar
import shogg/client
import simplifile

pub fn main() {
  let assert Ok(host) = envoy.get("CALDAV_HOST")
  let assert Ok(username) = envoy.get("CALDAV_USERNAME")
  let assert Ok(password) = envoy.get("CALDAV_PASSWORD")
  let assert Ok(calendar_name) = envoy.get("CALDAV_CALENDAR")

  let client =
    client.new_client(http.Https, host:, username:, password:)
    |> client.set_io(hackney.send)
  let assert Ok(server) = client.fetch_server_info(client)
  let assert Ok(info) = client.fetch_user_info(client, server)

  let assert Ok(calendars) = calendar.fetch_calendars(client, info)
  let assert Ok(cal) = list.find(calendars, fn(c) { c.name == calendar_name })

  let assert Ok(changed_response) =
    calendar.changed_request(client, cal)
    |> hackney.send

  let assert Ok(_) =
    simplifile.write(
      to: "../test/shogg/responses/calendar_changed.xml",
      contents: changed_response.body,
    )

  let assert Ok(unchanged_response) =
    calendar.changed_request(client, cal)
    |> hackney.send

  let assert Ok(_) =
    simplifile.write(
      to: "../test/shogg/responses/calendar_unchanged.xml",
      contents: unchanged_response.body,
    )
}
