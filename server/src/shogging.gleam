import envoy
import gleam/erlang/process
import gleam/hackney
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import lustre
import mist
import server_component
import setup
import shogg/calendar
import shogg/client
import shogg/task

pub fn main() {
  let assert Ok(raw_host) = envoy.get("CALDAV_HOST")
  let assert Ok(username) = envoy.get("CALDAV_USERNAME")
  let assert Ok(password) = envoy.get("CALDAV_PASSWORD")
  let assert Ok(calendar) = envoy.get("CALDAV_CALENDAR")
  let assert Ok(delay) =
    envoy.get("CHECK_CHANGE_DELAY") |> result.try(int.parse)

  // The scheme is inferred from CALDAV_HOST: an explicit "http://" prefix
  // selects plain HTTP (the local dev server), anything else is HTTPS.
  let #(scheme, host) = case string.split_once(raw_host, "://") {
    Ok(#("http", rest)) -> #(client.http, rest)
    Ok(#("https", rest)) -> #(client.https, rest)
    _ -> #(client.https, raw_host)
  }

  let client =
    client.new_client(scheme, host:, username:, password:)
    |> client.set_io(hackney.send)
  let assert Ok(server) = client.fetch_server_info(client)
  let assert Ok(user) = client.fetch_user_info(client, server)
  let assert Ok(home_set) = client.fetch_calendar_home_set(client, user)
  let assert Ok(calendars) = calendar.fetch_calendars(client, home_set)
  let assert Ok(calendar) = calendars |> list.find(fn(c) { c.name == calendar })
  let assert Ok(tasks) = task.fetch_tasks(client, calendar)
  let task_list = server_component.component()
  let assert Ok(component) =
    lustre.start_server_component(task_list, #(client, calendar, tasks, delay))

  let assert Ok(_) =
    setup.router(_, component)
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(1234)
    |> mist.start

  process.sleep_forever()
}
