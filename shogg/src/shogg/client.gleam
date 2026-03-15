import gleam/bit_array
import gleam/dynamic/decode
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/result
import parsed_it/xml
import shogg.{type ShoggError, DecodeError, ParseError, SendError}

pub type SendFn(error) =
  fn(Request(String)) -> Result(Response(String), error)

pub type IO(error) {
  IO(send: SendFn(error))
}

pub type Client(user_path, io) {
  Client(
    request: Request(String),
    base_path: String,
    user_path: user_path,
    io: io,
  )
}

pub opaque type NoIO {
  NoIO
}

pub opaque type NoUserPath {
  NoUserPath
}

pub const http = http.Http

pub const https = http.Https

pub fn new_client(
  scheme scheme: http.Scheme,
  host host: String,
  username username: String,
  password password: String,
) -> Client(NoUserPath, NoIO) {
  Client(
    request: request.new()
      |> request.set_scheme(scheme)
      |> request.set_host(host)
      |> request.set_header(
        "authorization",
        encode_basic_auth(username, password),
      ),
    base_path: "/caldav/",
    user_path: NoUserPath,
    io: NoIO,
  )
}

pub fn set_io(client: Client(u, _), send_fn: SendFn(e)) -> Client(u, IO(e)) {
  Client(..client, io: IO(send_fn))
}

pub fn encode_basic_auth(username: String, password: String) -> String {
  "Basic "
  <> bit_array.base64_encode(<<username:utf8, ":":utf8, password:utf8>>, True)
}

pub fn user_info_request(client: Client(_, _)) -> Request(String) {
  // Make library internal request builder
  client.request
  |> request.set_path(client.base_path)
  |> request.set_method(http.Other("PROPFIND"))
  |> request.set_header("Depth", "1")
  |> request.set_header("Content-Type", "application/xml; charset=utf-8")
  |> request.set_body(user_info_propfind_body())
}

fn user_info_propfind_body() -> String {
  "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\">\n  <D:prop>\n    <D:current-user-principal/>\n  </D:prop>\n</D:propfind>"
}

pub fn fetch_user_info(
  client: Client(_, IO(e)),
) -> Result(Client(String, IO(e)), ShoggError(e)) {
  let response = user_info_request(client) |> client.io.send
  use response <- result.try(response |> result.map_error(SendError))
  parse_user_info(client, response)
}

pub fn parse_user_info(
  client: Client(_, _),
  response: Response(String),
) -> Result(Client(String, _), ShoggError(e)) {
  use parsed <- result.try(
    xml.parse(response.body, user_info_decoder())
    |> result.map_error(DecodeError),
  )
  case parsed {
    [] -> Error(ParseError("No responses found"))
    [HomePropfindResponse(current_user_principal:, ..), ..] ->
      Ok(set_user_path(client, current_user_principal))
  }
}

type HomePropfindResponse {
  HomePropfindResponse(href: String, current_user_principal: String)
}

fn user_info_decoder() {
  decode.field(
    "response",
    decode.list({
      use href <- decode.field(
        "href",
        decode.field("$text", decode.string, decode.success),
      )
      use current_user_principal <- decode.field(
        "propstat",
        decode.field(
          "prop",
          decode.field(
            "current-user-principal",
            decode.field(
              "href",
              decode.field("$text", decode.string, decode.success),
              decode.success,
            ),
            decode.success,
          ),
          decode.success,
        ),
      )
      HomePropfindResponse(href:, current_user_principal:) |> decode.success()
    }),
    decode.success,
  )
}

pub fn set_user_path(client, path: String) {
  Client(..client, user_path: path)
}
