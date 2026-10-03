import argv
import envoy
import gleam/hackney
import gleam/io
import gleam/list
import gleam/string
import shogg/calendar
import shogg/client
import shogg/task
import simplifile

const responses_path = "../test/shogg/responses/"

pub fn main() {
  case argv.load().arguments {
    [backend] -> run_example(backend)
    _ ->
      io.println("Usage: gleam run <backend>\n  backend: radicale or nextcloud")
  }
}

fn run_example(backend: String) {
  let assert Ok(raw_host) = envoy.get("CALDAV_HOST")
  let assert Ok(username) = envoy.get("CALDAV_USERNAME")
  let assert Ok(password) = envoy.get("CALDAV_PASSWORD")
  let assert Ok(calendar_name) = envoy.get("CALDAV_CALENDAR")

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

  let assert Ok(_) = simplifile.create_directory_all(responses_path <> backend)

  let assert Ok(server) = client.fetch_server_info(client)
  write_response(backend, "server_info.xml", "")

  let assert Ok(info) = client.fetch_user_info(client, server)
  let user_info_resp = client.user_info_request(client, server) |> hackney.send
  case user_info_resp {
    Ok(resp) -> write_response(backend, "user_info.xml", resp.body)
    _ -> Nil
  }

  let home_set_req = client.calendar_home_set_request(client, info)
  let assert Ok(home_set_resp) = home_set_req |> hackney.send
  write_response(backend, "calendar_home_set.xml", home_set_resp.body)

  let assert Ok(home_set) = client.parse_calendar_home_set(home_set_resp)

  let calendars_req = calendar.calendars_request(client, home_set)
  let assert Ok(calendars_resp) = calendars_req |> hackney.send
  write_response(backend, "calendars.xml", calendars_resp.body)

  let assert Ok(calendars) = calendar.parse_calendars(calendars_resp)
  let assert Ok(cal) = list.find(calendars, fn(c) { c.name == calendar_name })

  let changed_req = calendar.changed_request(client, cal)
  let assert Ok(changed_resp) = changed_req |> hackney.send
  write_response(backend, "calendar_changed.xml", changed_resp.body)

  let tasks_req = task.tasks_request(client, cal)
  let assert Ok(tasks_resp) = tasks_req |> hackney.send
  write_response(backend, "tasks.xml", tasks_resp.body)

  io.println("Responses saved to " <> responses_path <> backend <> "/")
}

fn write_response(backend: String, filename: String, body: String) {
  let path = responses_path <> backend <> "/" <> filename
  let assert Ok(_) = simplifile.write(to: path, contents: body)
  io.println("  Wrote: " <> filename)
}
