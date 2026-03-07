import dotenv
import envoy
import gleam/bool
import gleam/hackney
import gleam/http
import gleam/list
import shogg/calendar
import shogg/client
import shogg/vtodo

pub fn main() {
  let assert Ok(_) = dotenv.config()

  let assert Ok(host) = envoy.get("CALDAV_HOST")
  let assert Ok(username) = envoy.get("CALDAV_USERNAME")
  let assert Ok(password) = envoy.get("CALDAV_PASSWORD")
  let assert Ok(calendar) = envoy.get("CALDAV_CALENDAR")

  let assert Ok(client) =
    client.new_client(http.Https, host:, username:, password:)
    |> client.set_io(hackney.send)
    |> client.fetch_user_info()

  let assert Ok(calendars) = calendar.fetch_calendars(client)
  echo calendars
  let assert Ok(calendar) = list.find(calendars, fn(c) { c.name == calendar })

  // let assert Ok(e) = echo vtodo.send_create_todo(client, calendar, "Summary")
  // echo e

  // use <- bool.guard(True, Nil)
  let assert Ok(todos) = vtodo.fetch_todos(client, calendar)
  list.each(todos, fn(t) { echo t })
}
// TODO:
// 
// Later:
// - Sync todos
// - Make radicale add the VTODO component to a calendar
// - Porper discovery of caldav base path (don't assume /caldav/)
