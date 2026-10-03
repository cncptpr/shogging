//// Static files for the built frontend.
////
//// `gleam run -m lustre/dev build` writes the bundle into priv/static, this
//// serves it: index.html for the page itself, everything else by path.

import gleam/bytes_tree
import gleam/erlang/application
import gleam/http/response.{type Response}
import gleam/list
import gleam/option.{None}
import gleam/string
import mist

const content_types = [
  #(".html", "text/html; charset=utf-8"),
  #(".css", "text/css; charset=utf-8"),
  #(".mjs", "text/javascript; charset=utf-8"),
  #(".js", "text/javascript; charset=utf-8"),
  #(".json", "application/json"),
  #(".map", "application/json"),
  #(".svg", "image/svg+xml"),
  #(".png", "image/png"),
  #(".ico", "image/x-icon"),
  #(".txt", "text/plain; charset=utf-8"),
  #(".woff2", "font/woff2"),
]

pub fn serve(path: List(String)) -> Response(mist.ResponseData) {
  case is_safe(path) {
    False -> not_found()
    True -> {
      let file = case path {
        [] -> "index.html"
        _ -> string.join(path, "/")
      }
      let assert Ok(priv_directory) =
        application.priv_directory("shogging")

      case mist.send_file(priv_directory <> "/static/" <> file, offset: 0, limit: None) {
        Ok(body) ->
          response.new(200)
          |> response.prepend_header("content-type", content_type(file))
          |> response.set_body(body)

        Error(_) -> not_found()
      }
    }
  }
}

/// Nothing may climb out of priv/static.
fn is_safe(path: List(String)) -> Bool {
  list.all(path, fn(segment) {
    segment != "" && segment != "." && segment != ".."
  })
}

fn content_type(file: String) -> String {
  case list.find(
    content_types,
    fn(entry) { string.ends_with(file, entry.0) },
  ) {
    Ok(entry) -> entry.1
    Error(Nil) -> "application/octet-stream"
  }
}

fn not_found() -> Response(mist.ResponseData) {
  response.new(404)
  |> response.set_body(mist.Bytes(bytes_tree.new()))
}
