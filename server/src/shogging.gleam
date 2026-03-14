import envoy
import gleam/bytes_tree
import gleam/erlang/process
import gleam/hackney
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import lustre
import mist.{type Connection, type ResponseData}
import setup
import shogg/client
import todo_view

// MAIN ------------------------------------------------------------------------

pub fn main() {
  let assert Ok(host) = envoy.get("CALDAV_HOST")
  let assert Ok(username) = envoy.get("CALDAV_USERNAME")
  let assert Ok(password) = envoy.get("CALDAV_PASSWORD")
  let assert Ok(calendar) = envoy.get("CALDAV_CALENDAR")

  let assert Ok(client) =
    client.new_client(client.https, host:, username:, password:)
    |> client.set_io(hackney.send)
    |> client.fetch_user_info()

  let todo_list = todo_view.component()
  let assert Ok(component) =
    lustre.start_server_component(todo_list, #(client, calendar))

  let assert Ok(_) =
    fn(request: Request(Connection)) -> Response(ResponseData) {
      // In order to get started with server components, we'll need to handle at
      // least three things:
      case request.path_segments(request) {
        [] -> setup.serve_html()
        ["lustre", "runtime.mjs"] -> setup.serve_runtime()
        ["ws"] -> setup.serve_component(request, component)
        _ -> response.set_body(response.new(404), mist.Bytes(bytes_tree.new()))
      }
    }
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(1234)
    |> mist.start

  process.sleep_forever()
}
// asd
