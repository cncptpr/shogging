import dotenv
import envoy
import gleam/bool
import gleam/dict
import gleam/dynamic/decode
import gleam/fetch
import gleam/function
import gleam/hackney
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import parsed_it/xml
import shogg/caldav
import simplifile

const xml_ct = "application/xml; charset=utf-8"

fn decode_text_field(name name, cb cb) {
  decode.field(name, decode_text(), cb)
}

fn decode_text() {
  decode.field("$text", decode.string, decode.success)
}

fn decode_xml_list(element decoder) {
  decode.one_of(decode.list(decoder), or: [
    decoder |> decode.map(fn(v) { [v] }),
  ])
}

type ShoggError(send_error) {
  SendError(error: send_error)
  DecodeError(error: xml.XmlDecodeError)
}

type Client(send_fn) {
  Client(
    request: Request(String),
    base_path: String,
    user_path: Option(String),
    send_fn: send_fn,
  )
}

type NoSendFn {
  NoSendFn
}

fn new_client(scheme, host, username, password) {
  Client(
    request: request.new()
      |> request.set_scheme(scheme)
      |> request.set_host(host)
      |> request.set_header(
        "authorization",
        caldav.encode_basic_auth(username, password),
      ),
    base_path: "/caldav/",
    user_path: None,
    send_fn: NoSendFn,
  )
}

fn set_send_fn(client, send_fn: SendFn(e)) {
  Client(..client, send_fn:)
}

type ParsedCalendar {
  ParsedCalendar(href: String)
}

type ResourceType {
  Principal
  Collection
  CardDAVAdressbook
  CalDAVCalendar
  Other(tag: String)
}

type CalDAVComponent {
  VEvent
  VJournal
  VTodo
}

type GetCalendarsProp {
  GetCalendarsProp(
    resource_types: Option(List(ResourceType)),
    display_name: Option(String),
    ctag: Option(String),
    supported_components: Option(List(CalDAVComponent)),
    ical_calendar_color: Option(String),
  )
}

type GetCalendarsResponse {
  GetCalendarsResponse(href: String, prop: GetCalendarsProp)
}

type SendFn(error) =
  fn(Request(String)) -> Result(Response(String), error)

fn fetch_calendars(client: Client(SendFn(e))) {
  let request_body =
    "<d:propfind xmlns:d=\"DAV:\" xmlns:cs=\"http://calendarserver.org/ns/\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\" xmlns:apple=\"http://apple.com/ns:ical/\">
        <d:prop>
          <d:resourcetype/>
          <d:displayname/>
          <cs:getctag/>
          <c:supported-calendar-component-set/>
          <apple:calendar-color/>
        </d:prop>
      </d:propfind>"

  let assert Some(path) = client.user_path

  let response =
    client.request
    |> request.set_path(path)
    |> request.set_method(http.Other("PROPFIND"))
    |> request.set_body(request_body)
    |> request.set_header("Depth", "1")
    |> request.set_header("Content-Type", xml_ct)
    |> client.send_fn()
  use response <- result.try(response |> result.map_error(SendError))
  Ok(response.body)
}

fn fetch_todos(client: Client(SendFn(e)), calendar_href: String) {
  let request_body =
    "<c:calendar-query xmlns:d=\"DAV:\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\">
      <d:prop>
        <d:getetag/>
        <c:calendar-data/>
      </d:prop>
      <c:filter>
        <c:comp-filter name=\"VCALENDAR\">
          <c:comp-filter name=\"VTODO\"/>
        </c:comp-filter>
      </c:filter>
    </c:calendar-query>"

  let response =
    client.request
    |> request.set_path(calendar_href)
    |> request.set_method(http.Other("REPORT"))
    |> request.set_body(request_body)
    |> request.set_header("Depth", "1")
    |> request.set_header("Content-Type", xml_ct)
    |> client.send_fn()
  use response <- result.try(response |> result.map_error(SendError))
  Ok(response.body)
}

fn serialize_parsed_todo(
  parsed: ParsedTodo,
  href: String,
  etag: String,
) -> String {
  let base =
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nCALSCALE:GREGORIAN\r\nPRODID:-//Gleam CalDAV//EN\r\nBEGIN:VTODO\r\n"
  let base = base <> "UID:" <> parsed.uid <> "\r\n"
  let base = base <> "DTSTAMP:" <> parsed.dtstamp <> "\r\n"
  let base = case parsed.created {
    Some(v) -> base <> "CREATED:" <> v <> "\r\n"
    None -> base
  }
  let base = case parsed.last_modified {
    Some(v) -> base <> "LAST-MODIFIED:" <> v <> "\r\n"
    None -> base
  }
  let base = case parsed.status {
    Some(v) -> base <> "STATUS:" <> v <> "\r\n"
    None -> base
  }
  let base = case parsed.summary {
    Some(v) -> base <> "SUMMARY:" <> v <> "\r\n"
    None -> base
  }
  let base = case parsed.completed {
    Some(v) -> base <> "COMPLETED:" <> v <> "\r\n"
    None -> base
  }
  let base = case parsed.percent_complete {
    Some(v) -> base <> "PERCENT-COMPLETE:" <> int.to_string(v) <> "\r\n"
    None -> base
  }
  let base = case parsed.x_apple_sort_order {
    Some(v) -> base <> "X-APPLE-SORT-ORDER:" <> int.to_string(v) <> "\r\n"
    None -> base
  }
  let other_fields =
    parsed.other
    |> list.filter(fn(o) {
      o.0 != "BEGIN"
      && o.0 != "END"
      && o.0 != "VERSION"
      && o.0 != "UID"
      && o.0 != "DTSTAMP"
    })
  let base =
    other_fields
    |> list.fold(base, fn(acc, o) { acc <> o.0 <> ":" <> o.1 <> "\r\n" })
  base <> "END:VTODO\r\nEND:VCALENDAR\r\n"
}

fn update_todo(
  client: Client(SendFn(e)),
  href: String,
  etag: String,
  ical_body: String,
) -> Result(Nil, ShoggError(e)) {
  let response =
    client.request
    |> request.set_path(href)
    |> request.set_method(http.Put)
    |> request.set_body(ical_body)
    |> request.set_header("Content-Type", "text/calendar; charset=utf-8")
    |> request.set_header("If-Match", etag)
    |> client.send_fn()
  use response <- result.try(response |> result.map_error(SendError))
  io.println("Update response status: " <> int.to_string(response.status))
  case response.status {
    204 | 201 -> Ok(Nil)
    status -> {
      let _ = io.println("Update failed with status: " <> int.to_string(status))
      panic
    }
  }
}

type TodoResponse {
  TodoResponse(href: String, etag: String, calendar_data: String)
}

type ParsedTodo {
  ParsedTodo(
    uid: String,
    dtstamp: String,
    created: Option(String),
    last_modified: Option(String),
    status: Option(String),
    summary: Option(String),
    completed: Option(String),
    percent_complete: Option(Int),
    x_apple_sort_order: Option(Int),
    other: List(#(String, String)),
  )
}

fn empty_parsed_todo() {
  ParsedTodo(
    uid: "",
    dtstamp: "",
    created: None,
    last_modified: None,
    status: None,
    summary: None,
    completed: None,
    percent_complete: None,
    x_apple_sort_order: None,
    other: [],
  )
}

fn parse_icalendar(ical_data: String) -> Result(ParsedTodo, String) {
  let lines =
    ical_data
    |> echo
    |> string.split("\n")
    |> list.map(string.trim)
    |> list.filter(fn(l) { l != "" })
    |> echo

  case list.filter(lines, fn(l) { string.starts_with(l, "BEGIN:") }) {
    ["BEGIN:VCALENDAR", "BEGIN:VTODO", ..] -> {
      let vtodo_lines = lines |> list.drop_while(fn(l) { l != "BEGIN:VTODO" })
      let vtodo_content = find_vtodo_content(vtodo_lines, 0)
      parse_vtodo(vtodo_content, empty_parsed_todo())
    }
    _ -> Error("Expected BEGIN:VCALENDAR and BEGIN:VTODO")
  }
}

fn find_vtodo_content(lines: List(String), idx: Int) -> List(String) {
  case lines {
    [] -> []
    ["END:VTODO", ..] -> ["END:VTODO"]
    [line, ..rest] -> [line, ..find_vtodo_content(rest, idx + 1)]
  }
}

fn split_vtodo(
  lines: List(String),
) -> Result(#(List(String), List(String)), String) {
  case lines {
    [] -> Error("No END:VTODO found")
    ["END:VTODO", ..rest] -> Ok(#([], rest))
    [line, ..rest] -> {
      use inner <- result.try(split_vtodo(rest))
      Ok(#([line, ..inner.0], inner.1))
    }
  }
}

fn parse_ical_field(line: String) -> #(String, String) {
  case string.split_once(line, ":") {
    Ok(#(key, value)) -> #(key, value)
    Error(Nil) -> #(line, "")
  }
}

fn parse_vtodo(
  lines: List(String),
  parsed: ParsedTodo,
) -> Result(ParsedTodo, String) {
  case lines {
    [] -> Error("Empty VTODO")
    ["END:VTODO"] -> Ok(parsed)
    ["END:VTODO", ..] -> Error("Extra content after END:VTODO")
    [line, ..rest] -> {
      use new_parsed <- result.try(parse_vtodo(rest, parsed))
      case parse_ical_field(line) {
        #("VERSION", _) -> {
          let assert "2.0" = line |> string.replace("VERSION:", "")
          Ok(new_parsed)
        }
        #("UID", value) -> Ok(ParsedTodo(..new_parsed, uid: value))
        #("DTSTAMP", value) -> Ok(ParsedTodo(..new_parsed, dtstamp: value))
        #("CREATED", value) ->
          Ok(ParsedTodo(..new_parsed, created: Some(value)))
        #("LAST-MODIFIED", value) ->
          Ok(ParsedTodo(..new_parsed, last_modified: Some(value)))
        #("STATUS", value) -> Ok(ParsedTodo(..new_parsed, status: Some(value)))
        #("SUMMARY", value) ->
          Ok(ParsedTodo(..new_parsed, summary: Some(value)))
        #("COMPLETED", value) ->
          Ok(ParsedTodo(..new_parsed, completed: Some(value)))
        #("PERCENT-COMPLETE", value) ->
          case int.parse(value) {
            Ok(i) -> Ok(ParsedTodo(..new_parsed, percent_complete: Some(i)))
            Error(_) -> Error("Invalid PERCENT-COMPLETE: " <> value)
          }
        #("X-APPLE-SORT-ORDER", value) ->
          case int.parse(value) {
            Ok(i) -> Ok(ParsedTodo(..new_parsed, x_apple_sort_order: Some(i)))
            Error(_) -> Error("Invalid X-APPLE-SORT-ORDER: " <> value)
          }
        #(key, value) ->
          Ok(
            ParsedTodo(..new_parsed, other: [#(key, value), ..new_parsed.other]),
          )
      }
    }
  }
}

fn get_todo_responses_decoder() {
  use root_tag <- decode.field("$tag", decode.string)
  let expected_root_tag = "multistatus"
  use <- bool.guard(
    when: root_tag != expected_root_tag,
    return: decode.failure(
      [],
      "Expected '"
        <> expected_root_tag
        <> "' as the root tag, found '"
        <> root_tag
        <> "'.",
    ),
  )
  use responses <- decode.field(
    "response",
    decode_xml_list({
      use href <- decode.field(
        "href",
        decode.field("$text", decode.string, decode.success),
      )
      use props <- decode.field(
        "propstat",
        decode_xml_list(decode_get_todo_propstat()),
      )
      case props |> option.values() |> list.first() {
        Ok(#(Some(etag), Some(calendar_data))) ->
          TodoResponse(href:, etag:, calendar_data:)
          |> decode.success
        _ ->
          decode.failure(TodoResponse("", "", ""), "No 200 OK propstat found")
      }
    }),
  )
  responses |> decode.success
}

fn decode_get_todo_propstat() {
  use status <- decode_text_field("status")
  use <- bool.guard(
    when: string.contains(status, "404 Not Found"),
    return: decode.success(None),
  )
  use <- bool.guard(
    when: !string.contains(status, "200 OK"),
    return: decode.failure(
      None,
      "Expected propstat status to be '200 OK'. Got '" <> status <> "'.",
    ),
  )
  use prop <- decode.field("prop", {
    use etag <- decode.optional_field(
      "getetag",
      None,
      decode_text() |> decode.map(Some),
    )
    use calendar_data <- decode.optional_field(
      "C:calendar-data",
      None,
      decode_text() |> decode.map(Some),
    )
    #(etag, calendar_data) |> decode.success
  })
  Some(prop) |> decode.success
}

fn make_info_request(client: Client(e)) {
  client.request
  |> request.set_path(client.base_path)
  |> request.set_method(http.Other("PROPFIND"))
  |> request.set_header("Depth", "1")
  |> request.set_header("Content-Type", xml_ct)
}

fn handle_info_response(client: Client(e), response: Response(String)) {
  use parsed <- result.try(
    xml.parse(response.body, home_propfined_responses_decoder())
    |> result.map_error(DecodeError),
  )
  case parsed {
    [] -> panic
    [first, ..] ->
      Ok(
        Client(
          ..client,
          base_path: first.href,
          user_path: Some(first.current_user_principal),
        ),
      )
  }
}

fn fetch_info(client: Client(SendFn(e))) {
  // TODO: proper discovery
  let response =
    make_info_request(client)
    |> client.send_fn()
  use response <- result.try(response |> result.map_error(SendError))
  handle_info_response(client, response)
}

type HomePropfindResponse {
  HomePropfindResponse(href: String, current_user_principal: String)
}

fn home_propfined_responses_decoder() {
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

fn guarl_ns(
  found namespace,
  expected expected,
  attr_name attr,
  ns_name name,
  cb cb,
) {
  use <- bool.guard(
    when: namespace != expected && namespace != "",
    return: decode.failure(
      Nil,
      "Expected '"
        <> expected
        <> "' as the "
        <> name
        <> " ("
        <> attr
        <> ") namespace, found '"
        <> namespace
        <> "'.",
    ),
  )
  cb()
}

fn assert_namespaces_decoder() {
  use xmlns <- decode.field("xmlns", decode.string)
  use <- guarl_ns(
    found: xmlns,
    expected: "DAV:",
    attr_name: "xmlns",
    ns_name: "default",
  )
  use xmlns_c <- decode.field("xmlns:C", decode.string)
  use <- guarl_ns(
    found: xmlns_c,
    expected: "urn:ietf:params:xml:ns:caldav",
    attr_name: "xmlns:C",
    ns_name: "CalDAV",
  )
  decode.success(Nil)
}

fn decode_get_calendars_propstat() {
  // use tag <- decode.field("$tag", decode.string)
  // use <- bool.guard(
  // tag == "propstat",
  // decode.failure(None, "Expected to be inside of a propstat tag."),
  // )
  use status <- decode_text_field("status")
  use <- bool.guard(
    when: string.contains(status, "404 Not Found"),
    return: decode.success(None),
  )
  use <- bool.guard(
    when: !string.contains(status, "200 OK"),
    return: decode.failure(
      None,
      "Expected propstat status to either be '200 OK' or '404 Not Found'. Got '"
        <> status
        <> "'.",
    ),
  )
  use prop <- decode.field("prop", {
    use display_name <- decode.optional_field(
      "displayname",
      None,
      decode_text() |> decode.map(Some),
    )
    use ctag <- decode.optional_field(
      "CS:getctag",
      None,
      decode_text() |> decode.map(Some),
    )
    use ical_calendar_color <- decode.optional_field(
      "ICAL:calendar-color",
      None,
      decode_text() |> decode.map(Some),
    )
    use resource_types <- decode.optional_field(
      "resourcetype",
      None,
      decode.dict(decode.string, decode.dynamic)
        |> decode.map(fn(dict) {
          dict.keys(dict)
          |> list.filter_map(fn(tag) {
            case tag {
              // Filter out meta tags (not an error)
              "$tag" -> Error(Nil)
              // TODO: proper error handling
              "$text" | "$attr" -> panic
              "CR:addressbook" -> Ok(CardDAVAdressbook)
              "collection" -> Ok(Collection)
              "C:calendar" -> Ok(CalDAVCalendar)
              "principal" -> Ok(Principal)
              tag -> Ok(Other(tag))
            }
          })
          |> Some
        }),
    )
    use supported_components <- decode.optional_field(
      "C:supported-calendar-component-set",
      None,
      decode.field(
        "C:comp",
        decode_xml_list(decode.field(
          "$attrs",
          decode.field("name", decode.string, decode.success)
            |> decode.map(fn(name) {
              case name {
                "VTODO" -> VTodo
                "VEVENT" -> VEvent
                "VJOURNAL" -> VJournal
                // TODO: proper error handling
                _ -> panic
              }
            }),
          decode.success,
        )),
        decode.success,
      )
        |> decode.map(Some),
    )
    GetCalendarsProp(
      resource_types:,
      display_name:,
      ctag:,
      supported_components:,
      ical_calendar_color:,
    )
    |> decode.success
  })
  Some(prop) |> decode.success
}

type Calendar {
  Calendar(
    href: String,
    name: String,
    ctag: String,
    components: List(CalDAVComponent),
    color: Option(String),
  )
}

fn decode_get_calendars_response() {
  use href <- decode.field(
    "href",
    decode.field("$text", decode.string, decode.success),
  )
  use props <- decode.field(
    "propstat",
    decode_xml_list(decode_get_calendars_propstat()),
  )
  // Assumtion: There should only ever be one '200 Ok' prop (aka Some(prop)) in a reponse
  // TODO: validate assumtion
  case props |> option.values() |> list.first() {
    Ok(prop) -> GetCalendarsResponse(href, prop) |> decode.success
    Error(Nil) ->
      GetCalendarsResponse(href, GetCalendarsProp(None, None, None, None, None))
      |> decode.success
  }
}

fn get_calendars_responses_decoder() {
  // TODO: properly handle root tag and namespaces
  use root_tag <- decode.field("$tag", decode.string)
  let expected_root_tag = "multistatus"
  use <- bool.guard(
    when: root_tag != expected_root_tag,
    return: decode.failure(
      [],
      "Expected '"
        <> expected_root_tag
        <> "' as the root tag, found '"
        <> root_tag
        <> "'.",
    ),
  )
  use Nil <- decode.field("$attrs", assert_namespaces_decoder())

  use responses <- decode.field(
    "response",
    decode_xml_list(decode_get_calendars_response()),
  )
  responses |> decode.success
}

fn responses_to_calendar(responses: List(GetCalendarsResponse)) {
  responses
  |> list.filter_map(fn(res) {
    case res.prop {
      GetCalendarsProp(
        supported_components: Some(components),
        resource_types: Some(resource_types),
        display_name: Some(name),
        ctag: Some(ctag),
        ical_calendar_color: color,
      ) ->
        case list.contains(resource_types, CalDAVCalendar) {
          True ->
            Ok(Calendar(href: res.href, name:, ctag:, components:, color:))
          False -> Error(Nil)
        }
      _ -> Error(Nil)
    }
  })
}

pub fn main() {
  let assert Ok(Nil) = dotenv.config()

  let assert Ok(host) = envoy.get("CALDAV_HOST")
  let assert Ok(username) = envoy.get("CALDAV_USERNAME")
  let assert Ok(password) = envoy.get("CALDAV_PASSWORD")

  io.println("Connecting to CalDAV server...")

  // let config =
  //   caldav.ConnectionConfig(url: url, username: username, password: password)

  // let assert Ok(req) = caldav.new_client(config)
  //

  let _ =
    "<test>Some
New
Lines</test>"
    |> xml.parse_dynamic
    |> echo

  let client =
    new_client(http.Https, host, username, password)
    |> set_send_fn(hackney.send)

  io.println("Running client discovery...")
  let assert Ok(client) = fetch_info(client)

  io.println("Fetching calendars...")
  let assert Ok(calendars_xml) = fetch_calendars(client)
  let assert Ok(calendars) =
    xml.parse(calendars_xml, get_calendars_responses_decoder())
  let calendars = responses_to_calendar(calendars)

  io.println("Fetching todos...")
  let assert Ok(calendar) =
    list.find(calendars, fn(c) { list.contains(c.components, VTodo) })
  let assert Ok(todos_xml) = fetch_todos(client, calendar.href)
  let assert Ok(todo_responses) =
    echo xml.parse(todos_xml, get_todo_responses_decoder())
  let parsed_todos =
    todo_responses
    |> list.filter_map(fn(todo_resp) {
      case parse_icalendar(todo_resp.calendar_data) {
        Ok(parsed) -> {
          io.println("---")
          io.println("UID: " <> parsed.uid)
          io.println("DTSTAMP: " <> parsed.dtstamp)
          io.println("STATUS: " <> parsed.status |> option.unwrap("N/A"))
          io.println("SUMMARY: " <> parsed.summary |> option.unwrap("N/A"))
          io.println("COMPLETED: " <> parsed.completed |> option.unwrap("N/A"))
          io.println("CREATED: " <> parsed.created |> option.unwrap("N/A"))
          io.println(
            "LAST-MODIFIED: " <> parsed.last_modified |> option.unwrap("N/A"),
          )
          io.println(
            "PERCENT: "
            <> parsed.percent_complete
            |> option.map(int.to_string)
            |> option.unwrap("N/A"),
          )
          io.println(
            "X-APPLE-SORT-ORDER: "
            <> parsed.x_apple_sort_order
            |> option.map(int.to_string)
            |> option.unwrap("N/A"),
          )
          io.println(
            "OTHER FIELDS: " <> int.to_string(list.length(parsed.other)),
          )
          parsed.other
          |> list.each(fn(o) { io.println("  OTHER: " <> o.0 <> " = " <> o.1) })
          Ok(parsed)
        }
        Error(e) -> {
          io.println("Error parsing todo: " <> e)
          Error(Nil)
        }
      }
    })
  io.println("Parsed " <> int.to_string(list.length(parsed_todos)) <> " todos")

  io.println("\n=== Testing update ===")
  case list.first(parsed_todos) {
    Ok(first_todo) -> {
      let todo_resp = case list.first(todo_responses) {
        Ok(r) -> r
        Error(Nil) -> TodoResponse("", "", "")
      }
      io.println("Updating todo: " <> first_todo.uid)
      let updated_todo =
        ParsedTodo(
          ..first_todo,
          summary: Some("UPDATED: " <> first_todo.summary |> option.unwrap("")),
        )
      let serialized =
        serialize_parsed_todo(updated_todo, todo_resp.href, todo_resp.etag)
      io.println("Serialized iCalendar:\n" <> serialized)
      let assert Ok(_) =
        update_todo(client, todo_resp.href, todo_resp.etag, serialized)
      io.println("Update successful!")
    }
    Error(Nil) -> io.println("No todos to update")
  }

  Nil
}
// TODO:
// - Get all todos
// - Update todo
// 
// Later:
// - Sync todos
// - Make radicale add the VTODO component to a calendar
// - Porper discovery of caldav base path (don't assume /caldav/)
