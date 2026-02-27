import dotenv
import envoy
import gleam/httpc
import gleam/int
import gleam/io
import gleam/list
import shogg/caldav

pub fn main() {
  let assert Ok(Nil) = dotenv.config()

  let assert Ok(url) = envoy.get("CALDAV_URL")
  let assert Ok(username) = envoy.get("CALDAV_USERNAME")
  let assert Ok(password) = envoy.get("CALDAV_PASSWORD")

  io.println("Connecting to CalDAV server...")

  let config =
    caldav.ConnectionConfig(url: url, username: username, password: password)

  let assert Ok(req) = caldav.new_client(config)

  io.println("Sending initial PROPFIND request...")

  let assert Ok(resp) = httpc.send(req)
  io.println("Got response, status: " <> int.to_string(resp.status))

  let assert Ok(client) = caldav.handle_new_client_response(config, resp)
  io.println("Principal URL: " <> client.principal_url)

  let req = caldav.get_calendars_request(client)

  io.println("Sending calendar-query request...")

  let assert Ok(resp) = httpc.send(req)
  io.println("Got response, status: " <> int.to_string(resp.status))

  let assert Ok(calendars) = caldav.handle_get_calendars_response(resp)

  io.println("Found " <> int.to_string(list.length(calendars)) <> " calendars:")

  list.each(calendars, fn(cal) {
    io.println("  - " <> cal.display_name <> " (" <> cal.href <> ")")
  })
}
