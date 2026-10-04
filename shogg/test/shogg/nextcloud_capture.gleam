//// Reading the CalDAV responses captured from this project's own Nextcloud
//// instance (see `dev/nextcloud-capture.sh`, re-run with
//// `devenv --profile nextcloud tasks run nextcloud:capture`).
////
//// Two shapes of capture live in `test/shogg/responses/nextcloud/`, all of
//// them prefixed `local_` to tell them apart from the fixtures recorded
//// against a remote Nextcloud:
////
//// - `local_*.xml` files hold nothing but the response body, for the parsers
////   that only ever look at the body.
//// - `local_*.txt` files hold the raw response as `curl -i` received it: a
////   status line, the headers, an empty line, then the body. These are the
////   responses where the status code or a header matters (redirects, PUT,
////   DELETE).
////
//// Header names are lowercased while parsing, the same normalisation the
//// app's HTTP client does (`gleam_hackney` lowercases every response header)
//// and that `gleam_http` requires of `Response` headers.

import gleam/http/response.{type Response}
import gleam/int
import gleam/list
import gleam/string
import simplifile

const directory = "test/shogg/responses/nextcloud/"

/// A response whose body is the whole captured file, for the XML parsers that
/// ignore the status and the headers.
pub fn body(file: String) -> Response(String) {
  let assert Ok(raw) = simplifile.read(directory <> file)
  response.Response(status: 0, headers: [], body: raw)
}

/// A response parsed out of a raw capture: status line, headers, body.
pub fn raw(file: String) -> Response(String) {
  let assert Ok(captured) = simplifile.read(directory <> file)
  let lines = string.split(captured, "\n")
  let #(head, rest) = take_until_blank_line(lines)
  let assert [status_line, ..header_lines] = head
  response.Response(
    status: status_code(status_line),
    headers: list.filter_map(header_lines, header),
    body: string.join(rest, "\n"),
  )
}

/// `"HTTP/1.1 301 Moved Permanently"` -> `301`
fn status_code(status_line: String) -> Int {
  case string.split(status_line, " ") {
    [_, code, ..] ->
      case int.parse(code) {
        Ok(status) -> status
        Error(_) -> 0
      }
    _ -> 0
  }
}

fn take_until_blank_line(lines: List(String)) -> #(List(String), List(String)) {
  case lines {
    [] -> #([], [])
    [line, ..rest] ->
      case string.trim(line) {
        "" -> #([], rest)
        _ -> {
          let #(head, tail) = take_until_blank_line(rest)
          #([line, ..head], tail)
        }
      }
  }
}

/// `"etag: \"abc\""` -> `#("etag", "\"abc\"")`, or `Error(Nil)` for the
/// status line or a line that is not a header.
fn header(line: String) -> Result(#(String, String), Nil) {
  case string.split_once(line, ":") {
    Ok(#(name, value)) -> Ok(#(string.lowercase(name), string.trim(value)))
    Error(_) -> Error(Nil)
  }
}
