import config
import envoy
import gleam/erlang/process
import gleam/hackney
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleam/time/duration
import html
import hub
import mist
import router
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
    client.new_client(scheme:, host:, username:, password:)
    |> client.set_io(hackney.send)

  let assert Ok(server) = client.fetch_server_info(client)
  let assert Ok(user) = client.fetch_user_info(client, server)
  let assert Ok(home_set) = client.fetch_calendar_home_set(client, user)
  let assert Ok(calendars) = calendar.fetch_calendars(client, home_set)
  let assert Ok(calendar) = calendars |> list.find(fn(c) { c.name == calendar })
  let assert Ok(tasks) = task.fetch_tasks(client, calendar)

  // The hub holds the todos and translates what the frontend asks for into
  // CalDAV requests. Everything else the web server does is serve the bundle
  // and shuttle WebSocket frames to and from it.
  let assert Ok(hub_subject) =
    hub.start(client, calendar, tasks, duration.seconds(delay))

  // The configuration is read once, here, rather than per request: the page is
  // the host document for a static bundle and the port belongs to the listener,
  // so both are fixed for the lifetime of the process. Named `cfg` rather than
  // `config` so that it does not shadow the module.
  let cfg = config.from_env()
  let page = html.render(cfg)

  let assert Ok(_) =
    router.router(_, hub_subject, page)
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(cfg.port)
    |> mist.start

  process.sleep_forever()
}
