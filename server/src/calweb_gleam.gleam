import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import lustre
import mist.{type Connection, type ResponseData}
import setup
import todo_list

// MAIN ------------------------------------------------------------------------

pub fn main() {
  let todo_list = todo_list.component()
  let assert Ok(component) = lustre.start_server_component(todo_list, Nil)

  let assert Ok(_) =
    fn(request: Request(Connection)) -> Response(ResponseData) {
      // In order to get started with server components, we'll need to handle at
      // least three things:
      case request.path_segments(request) {
        // 1. Serving the HTML document that will render the `<lustre-server-component />`
        //    custom element.
        [] -> setup.serve_html()
        // 2. Serving the pre-build JavaScript runtime that registers the custom
        //    element and handles communication and rendering.
        ["lustre", "runtime.mjs"] -> setup.serve_runtime()
        // 3. The websocket connection that the client runtime will connect to
        //    and the server runtime can push messages to.
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
