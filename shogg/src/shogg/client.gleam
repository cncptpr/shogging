import gleam/bit_array
import gleam/dynamic/decode
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import parsed_it/xml
import shogg.{type ShoggError, DecodeError, ParseError, SendError}
import shogg/namespace.{DAV}

pub type Client(io) {
  Client(request: Request(String), io: io)
}

pub type IO(error) {
  IO(send: SendFn(error))
}

pub type SendFn(error) =
  fn(Request(String)) -> Result(Response(String), error)

pub opaque type NoIO {
  NoIO
}

pub type ServerInfo {
  ServerInfo(base_path: String)
}

pub type UserInfo {
  UserInfo(principal: String)
}

pub const http = http.Http

pub const https = http.Https

pub fn new_client(
  scheme scheme: http.Scheme,
  host host: String,
  username username: String,
  password password: String,
) -> Client(NoIO) {
  Client(
    request: request.new()
      |> request.set_scheme(scheme)
      |> request.set_host(host)
      |> request.set_header(
        "authorization",
        encode_basic_auth(username, password),
      ),
    io: NoIO,
  )
}

pub fn set_io(client: Client(_), send_fn: SendFn(e)) -> Client(IO(e)) {
  Client(..client, io: IO(send_fn))
}

pub fn fetch_server_info(
  client: Client(IO(e)),
) -> Result(ServerInfo, ShoggError(e)) {
  let response = server_info_request(client) |> client.io.send
  use response <- result.try(response |> result.map_error(SendError))
  parse_server_info(response)
}

pub fn server_info_request(client: Client(_)) -> Request(String) {
  client.request
  |> request.set_path("/.well-known/caldav")
  |> request.set_method(http.Get)
}

pub fn parse_server_info(
  response: Response(String),
) -> Result(ServerInfo, ShoggError(e)) {
  case response.status {
    301 | 302 | 307 | 308 -> {
      case list.key_find(response.headers, "location") {
        Ok(path) -> Ok(ServerInfo(path))
        Error(Nil) ->
          Error(ParseError("No Location header in redirect response"))
      }
    }
    _ ->
      Error(ParseError(
        "Expected redirect status (301/302/307/308), got "
        <> string.inspect(response.status),
      ))
  }
}

pub fn fetch_user_info(
  client: Client(IO(e)),
  server: ServerInfo,
) -> Result(UserInfo, ShoggError(e)) {
  let response = user_info_request(client, server) |> client.io.send
  use response <- result.try(response |> result.map_error(SendError))

  case parse_user_info(response) {
    Ok(o) -> Ok(o)
    Error(e) -> {
      io.println(response.body)
      Error(e)
    }
  }
}

pub fn user_info_request(
  client: Client(_),
  server: ServerInfo,
) -> Request(String) {
  let body =
    "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\">\n  <D:prop>\n    <D:current-user-principal/>\n  </D:prop>\n</D:propfind>"
  // Make library internal request builder
  client.request
  |> request.set_path(server.base_path)
  |> request.set_method(http.Other("PROPFIND"))
  |> request.set_header("Depth", "1")
  |> request.set_header("Content-Type", "application/xml; charset=utf-8")
  |> request.set_body(body)
}

pub fn parse_user_info(
  response: Response(String),
) -> Result(UserInfo, ShoggError(e)) {
  use parsed <- result.try(
    xml.parse(response.body, user_info_decoder())
    |> result.map_error(DecodeError),
  )
  case parsed {
    [] -> Error(ParseError("No responses found"))
    [HomePropfindResponse(current_user_principal:, ..), ..] ->
      Ok(UserInfo(current_user_principal))
  }
}

fn encode_basic_auth(username: String, password: String) -> String {
  "Basic "
  <> bit_array.base64_encode(<<username:utf8, ":":utf8, password:utf8>>, True)
}

type HomePropfindResponse {
  HomePropfindResponse(href: String, current_user_principal: String)
}

fn user_info_decoder() {
  use ns <- decode.then(namespace.decode_namespaces())
  decode.field(
    namespace.xmlns(ns, DAV, "response"),
    decode.list({
      use href <- decode.field(
        namespace.xmlns(ns, DAV, "href"),
        decode.field("$text", decode.string, decode.success),
      )
      use current_user_principal <- decode.field(
        namespace.xmlns(ns, DAV, "propstat"),
        decode.field(
          namespace.xmlns(ns, DAV, "prop"),
          decode.field(
            namespace.xmlns(ns, DAV, "current-user-principal"),
            decode.field(
              namespace.xmlns(ns, DAV, "href"),
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
