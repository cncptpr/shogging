import gleam/bit_array
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/option
import gleam/string
import gleam/uri

pub type ConnectionConfig {
  ConnectionConfig(url: String, username: String, password: String)
}

pub type CalDAVClient {
  CalDAVClient(url: String, principal_url: String)
}

pub type Calendar {
  Calendar(
    href: String,
    display_name: String,
    description: option.Option(String),
    timezone: option.Option(String),
    sync_token: option.Option(String),
  )
}

pub type Error {
  ParseError(String)
  InvalidUrl
  NoPrincipalUrl
  NoCalendars
}

fn encode_basic_auth(username: String, password: String) -> String {
  let credentials = username <> ":" <> password
  let encoded =
    bit_array.base64_encode(bit_array.from_string(credentials), False)
  "Basic " <> encoded
}

pub fn new_client(
  config: ConnectionConfig,
) -> Result(request.Request(String), Error) {
  case uri.parse(config.url) {
    Ok(uri) -> {
      let scheme = case uri.scheme {
        option.Some("https") -> http.Https
        option.Some("http") -> http.Http
        _ -> http.Http
      }

      case uri.host {
        option.None -> Error(InvalidUrl)
        option.Some(host) -> {
          let port = case uri.port {
            option.Some(p) -> p
            option.None ->
              case scheme {
                http.Https -> 443
                http.Http -> 80
              }
          }

          let path = case string.is_empty(uri.path) {
            True -> "/"
            False -> uri.path
          }

          let req =
            request.new()
            |> request.set_method(http.Get)
            |> request.set_scheme(scheme)
            |> request.set_host(host)
            |> request.set_port(port)
            |> request.set_path(path)
            |> request.set_header(
              "authorization",
              encode_basic_auth(config.username, config.password),
            )
            |> request.set_header(
              "content-type",
              "application/xml; charset=utf-8",
            )
            |> request.set_body(initial_propfind_body())

          Ok(req)
        }
      }
    }
    Error(_) -> Error(InvalidUrl)
  }
}

fn initial_propfind_body() -> String {
  "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\" xmlns:C=\"urn:ietf:params:xml:ns:caldav\">\n  <D:prop>\n    <D:current-user-principal/>\n  </D:prop>\n</D:propfind>"
}

pub fn handle_new_client_response(
  config: ConnectionConfig,
  resp: response.Response(String),
) -> Result(CalDAVClient, Error) {
  case parse_principal_url(resp.body) {
    Ok(principal_url) -> {
      Ok(CalDAVClient(url: config.url, principal_url: principal_url))
    }
    Error(_) -> Error(NoPrincipalUrl)
  }
}

fn parse_principal_url(body: String) -> Result(String, Error) {
  case string.contains(body, "<D:current-user-principal>") {
    True -> {
      let parts = string.split(body, "<D:current-user-principal>")
      case parts {
        [_, rest, ..] -> {
          case string.split(rest, "</D:current-user-principal>") {
            [url_part, ..] -> {
              let cleaned = string.trim(url_part)
              case string.contains(cleaned, "<D:href>") {
                True -> {
                  let href_parts = string.split(cleaned, "<D:href>")
                  case href_parts {
                    [_, href_rest, ..] -> {
                      case string.split(href_rest, "</D:href>") {
                        [final_url, ..] -> Ok(string.trim(final_url))
                        _ -> Error(NoPrincipalUrl)
                      }
                    }
                    _ -> Error(NoPrincipalUrl)
                  }
                }
                False -> Ok(cleaned)
              }
            }
            _ -> Error(NoPrincipalUrl)
          }
        }
        _ -> Error(NoPrincipalUrl)
      }
    }
    False -> Error(NoPrincipalUrl)
  }
}

pub fn get_calendars_request(client: CalDAVClient) -> request.Request(String) {
  let url_parts = string.split(client.url, "/")
  let host = case url_parts {
    [_, _, h, ..] -> h
    _ -> ""
  }
  let scheme = case string.starts_with(client.url, "https") {
    True -> http.Https
    False -> http.Http
  }
  let port = case string.contains(client.url, ":443") {
    True -> 443
    False ->
      case string.contains(client.url, ":80") {
        True -> 80
        False ->
          case scheme {
            http.Https -> 443
            http.Http -> 80
          }
      }
  }

  request.new()
  |> request.set_method(http.Other("REPORT"))
  |> request.set_scheme(scheme)
  |> request.set_host(host)
  |> request.set_port(port)
  |> request.set_path(client.principal_url)
  |> request.set_header("content-type", "application/xml; charset=utf-8")
  |> request.set_body(calendar_query_body())
}

fn calendar_query_body() -> String {
  "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<C:calendar-query xmlns:D=\"DAV:\" xmlns:C=\"urn:ietf:params:xml:ns:caldav\">\n  <D:prop>\n    <D:href/>\n    <C:display-name/>\n    <C:description/>\n    <C:timezone/>\n    <D:sync-token/>\n  </D:prop>\n  <C:filter>\n    <C:comp-filter name=\"VCALENDAR\"/>\n  </C:filter>\n</C:calendar-query>"
}

pub fn handle_get_calendars_response(
  resp: response.Response(String),
) -> Result(List(Calendar), Error) {
  parse_calendars(resp.body)
}

fn get_nth_opt(list: List(a), n: Int) -> option.Option(a) {
  case n {
    0 ->
      case list {
        [first, ..] -> option.Some(first)
        [] -> option.None
      }
    _ ->
      case list {
        [_, ..rest] -> get_nth_opt(rest, n - 1)
        [] -> option.None
      }
  }
}

fn find_index(list: List(a), pred: fn(a) -> Bool) -> option.Option(Int) {
  list.index_fold(list, option.None, fn(acc, item, i) {
    case acc {
      option.Some(_) -> acc
      option.None ->
        case pred(item) {
          True -> option.Some(i)
          False -> option.None
        }
    }
  })
}

fn parse_calendars(body: String) -> Result(List(Calendar), Error) {
  let hrefs = extract_xml_values(body, "<D:href>", "</D:href>")
  let display_names =
    extract_xml_values(body, "<C:display-name>", "</C:display-name>")
  let descriptions =
    extract_xml_values(body, "<C:description>", "</C:description>")
  let timezones = extract_xml_values(body, "<C:timezone>", "</C:timezone>")
  let sync_tokens =
    extract_xml_values(body, "<D:sync-token>", "</D:sync-token>")

  let calendars =
    list.map2(hrefs, display_names, fn(href, display_name) {
      let idx = find_index(display_names, fn(d) { d == display_name })
      let desc = case idx {
        option.Some(i) -> get_nth_opt(descriptions, i)
        option.None -> option.None
      }
      let tz = case idx {
        option.Some(i) -> get_nth_opt(timezones, i)
        option.None -> option.None
      }
      let sync = case idx {
        option.Some(i) -> get_nth_opt(sync_tokens, i)
        option.None -> option.None
      }

      Calendar(
        href: href,
        display_name: display_name,
        description: desc,
        timezone: tz,
        sync_token: sync,
      )
    })

  case calendars {
    [] -> Error(NoCalendars)
    _ -> Ok(calendars)
  }
}

fn extract_xml_values(
  body: String,
  open_tag: String,
  close_tag: String,
) -> List(String) {
  string.split(body, open_tag)
  |> list.drop(1)
  |> list.map(fn(part) {
    case string.split(part, close_tag) {
      [value, ..] -> string.trim(value)
      [] -> ""
    }
  })
  |> list.filter(fn(s) { s != "" })
}
