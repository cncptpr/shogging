import envoy
import gleam/bytes_tree
import gleam/erlang/process
import gleam/hackney
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/list
import gleam/result
import lustre
import mist.{type Connection, type ResponseData}
import setup
import shogg/calendar
import shogg/client
import shogg/vtodo
import todo_view

pub fn main() {
  let assert Ok(host) = envoy.get("CALDAV_HOST")
  let assert Ok(username) = envoy.get("CALDAV_USERNAME")
  let assert Ok(password) = envoy.get("CALDAV_PASSWORD")
  let assert Ok(calendar) = envoy.get("CALDAV_CALENDAR")
  let assert Ok(delay) =
    envoy.get("CHECK_CHANGE_DELAY") |> result.try(int.parse)

  let client =
    client.new_client(client.https, host:, username:, password:)
    |> client.set_io(hackney.send)
  let assert Ok(server) = client.fetch_server_info(client) |> echo
  let assert Ok(user) = client.fetch_user_info(client, server) |> echo
  let assert Ok(calendars) = calendar.fetch_calendars(client, user) |> echo
  let assert Ok(calendar) =
    calendars |> list.find(fn(c) { c.name == calendar }) |> echo
  let assert Ok(todos) = vtodo.fetch_todos(client, calendar) |> echo

  let todo_list = todo_view.component()
  let assert Ok(component) =
    lustre.start_server_component(todo_list, #(client, calendar, todos, delay))

  let assert Ok(_) =
    fn(request: Request(Connection)) -> Response(ResponseData) {
      case request.path_segments(request) {
        [] -> setup.serve_html()
        ["lustre", "runtime.mjs"] -> setup.serve_runtime()
        ["ws"] -> setup.serve_component(request, component)
        _ ->
          response.new(404) |> response.set_body(mist.Bytes(bytes_tree.new()))
      }
    }
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(1234)
    |> mist.start

  process.sleep_forever()
}
