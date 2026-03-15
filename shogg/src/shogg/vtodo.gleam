import gleam/bool
import gleam/dynamic/decode
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/time/calendar as dt
import gleam/time/timestamp
import parsed_it/xml
import shogg.{type ShoggError, DecodeError, ParseError, SendError}
import shogg/calendar.{type Calendar}
import shogg/client.{type Client, type IO}
import youid/uuid

pub type VTodoMeta {
  VTodoMeta(href: String, etag: String)
}

pub type VTodo {
  VTodo(
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
    meta: VTodoMeta,
  )
}

fn decode_text() {
  decode.field("$text", decode.string, decode.success)
}

fn decode_xml_list(element decoder) {
  decode.one_of(decode.list(decoder), or: [
    decoder |> decode.map(fn(v) { [v] }),
  ])
}

pub fn get_now_formatted() {
  timestamp.system_time() |> formal_cal_date()
}

pub fn formal_cal_date(now: timestamp.Timestamp) {
  let #(dt.Date(year, month, day), dt.TimeOfDay(hours, minutes, seconds, _)) =
    now |> timestamp.to_calendar(dt.utc_offset)

  let pad = fn(num, padding) {
    string.pad_start(int.to_string(num), to: padding, with: "0")
  }

  pad(year, 4)
  <> pad(dt.month_to_int(month), 2)
  <> pad(day, 2)
  <> "T"
  <> pad(hours, 2)
  <> pad(minutes, 2)
  <> pad(seconds, 2)
  <> "Z"
}

pub fn is_competed(vtodo) {
  case vtodo {
    VTodo(status: Some("COMPLETED"), ..) -> True
    VTodo(status: None, completed: Some(_), ..) -> True
    _ -> False
  }
}

pub fn todos_request(
  client: Client(_, _),
  calendar: Calendar,
) -> Request(String) {
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

  client.request
  |> request.set_path(calendar.href)
  |> request.set_method(http.Other("REPORT"))
  |> request.set_body(request_body)
  |> request.set_header("Depth", "1")
  |> request.set_header("Content-Type", "application/xml; charset=utf-8")
}

pub fn fetch_todos(
  client: Client(_, IO(e)),
  calendar: Calendar,
) -> Result(List(VTodo), ShoggError(e)) {
  let response = todos_request(client, calendar) |> client.io.send
  use response <- result.try(response |> result.map_error(SendError))
  parse_todos(response)
}

pub fn parse_todos(
  response: Response(String),
) -> Result(List(VTodo), ShoggError(e)) {
  use parsed <- result.try(
    xml.parse(response.body, get_todo_responses_decoder())
    |> result.map_error(DecodeError),
  )
  parsed
  |> list.filter_map(fn(t) { parse_ical(t) })
  |> Ok
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
        Ok(#(Some(etag), Some(data))) ->
          #(VTodoMeta(href:, etag:), data)
          |> decode.success
        _ ->
          decode.failure(#(VTodoMeta("", ""), ""), "No 200 OK propstat found")
      }
    }),
  )
  responses |> decode.success
}

fn decode_get_todo_propstat() {
  use status <- decode.field("status", decode_text())
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

pub fn parse_ical(t: #(VTodoMeta, String)) -> Result(VTodo, String) {
  let #(meta, data) = t
  let lines =
    data
    |> string.split("\n")
    |> list.map(string.trim)
    |> list.filter(fn(l) { l != "" })

  // TODO: Refactor entire ical parser
  case list.filter(lines, fn(l) { string.starts_with(l, "BEGIN:") }) {
    ["BEGIN:VCALENDAR", "BEGIN:VTODO", ..] -> {
      let vtodo_lines = lines |> list.drop_while(fn(l) { l != "BEGIN:VTODO" })
      let vtodo_content = find_vtodo_content(vtodo_lines, 0)
      parse_vtodo(vtodo_content, VTodo(..empty_todo(), meta:))
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

fn parse_ical_field(line: String) -> #(String, String) {
  case string.split_once(line, ":") {
    Ok(#(key, value)) -> #(key, value)
    Error(Nil) -> #(line, "")
  }
}

fn empty_todo() {
  VTodo(
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
    meta: VTodoMeta("", ""),
  )
}

fn parse_vtodo(lines: List(String), parsed: VTodo) -> Result(VTodo, String) {
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
        #("UID", value) -> Ok(VTodo(..new_parsed, uid: value))
        #("DTSTAMP", value) -> Ok(VTodo(..new_parsed, dtstamp: value))
        #("CREATED", value) -> Ok(VTodo(..new_parsed, created: Some(value)))
        #("LAST-MODIFIED", value) ->
          Ok(VTodo(..new_parsed, last_modified: Some(value)))
        #("STATUS", value) -> Ok(VTodo(..new_parsed, status: Some(value)))
        #("SUMMARY", value) ->
          Ok(VTodo(..new_parsed, summary: Some(value |> remove_escape)))
        #("COMPLETED", value) -> Ok(VTodo(..new_parsed, completed: Some(value)))
        #("PERCENT-COMPLETE", value) ->
          case int.parse(value) {
            Ok(i) -> Ok(VTodo(..new_parsed, percent_complete: Some(i)))
            Error(_) -> Error("Invalid PERCENT-COMPLETE: " <> value)
          }
        #("X-APPLE-SORT-ORDER", value) ->
          case int.parse(value) {
            Ok(i) -> Ok(VTodo(..new_parsed, x_apple_sort_order: Some(i)))
            Error(_) -> Error("Invalid X-APPLE-SORT-ORDER: " <> value)
          }
        #(key, value) ->
          Ok(VTodo(..new_parsed, other: [#(key, value), ..new_parsed.other]))
      }
    }
  }
}

const chars_to_escape = [",", ";", "\\"]

fn remove_escape(text) {
  list.fold(chars_to_escape, text, fn(text, char) {
    text
    |> string.split("\\" <> char)
    |> string.join(char)
  })
}

fn escape(text) {
  list.fold(chars_to_escape, text, fn(text, char) {
    text
    |> string.split(char)
    |> string.join("\\" <> char)
  })
}

pub fn serialize_vtodo(parsed: VTodo) -> String {
  let base =
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nCALSCALE:GREGORIAN\r\nPRODID:-//Shogg//EN\r\nBEGIN:VTODO\r\n"
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
    Some(v) -> base <> "SUMMARY:" <> v |> escape <> "\r\n"
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
    |> list.fold(base, fn(acc, o) {
      acc <> o.0 <> ":" <> o.1 |> escape <> "\r\n"
    })
  base <> "END:VTODO\r\nEND:VCALENDAR\r\n"
}

pub fn update_todo_request(
  client: Client(_, _),
  vtodo: VTodo,
) -> Request(String) {
  // TODO: update updated_last
  let body = serialize_vtodo(vtodo)
  client.request
  |> request.set_path(vtodo.meta.href)
  |> request.set_method(http.Put)
  |> request.set_body(body)
  |> request.set_header("Content-Type", "text/calendar; charset=utf-8")
  |> request.set_header("If-Match", vtodo.meta.etag)
}

pub fn send_update_todo(
  client: Client(_, IO(e)),
  vtodo: VTodo,
) -> Result(Nil, ShoggError(e)) {
  let response = update_todo_request(client, vtodo) |> client.io.send
  use response <- result.try(response |> result.map_error(SendError))
  parse_update_todo_response(response)
}

pub fn parse_update_todo_response(
  response: Response(String),
) -> Result(Nil, ShoggError(e)) {
  case response.status {
    204 | 201 -> Ok(Nil)
    _ ->
      Error(ParseError(
        "Update failed with status: " <> int.to_string(response.status),
      ))
  }
}

pub fn create_todo_request_with(
  client: Client(_, _),
  calendar: Calendar,
  summary: String,
  uid: String,
  created: String,
) -> Request(String) {
  let href = calendar.href <> uid <> ".ics"
  let ical_body =
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nCALSCALE:GREGORIAN\r\nPRODID:-//Shogg//EN\r\nBEGIN:VTODO\r\nUID:"
    <> uid
    <> "\r\nDTSTAMP:"
    <> created
    <> "\r\nCREATED:"
    <> created
    <> "\r\nSTATUS:NEEDS-ACTION\r\nSUMMARY:"
    <> summary |> escape
    <> "\r\nEND:VTODO\r\nEND:VCALENDAR\r\n"

  client.request
  |> request.set_path(href)
  |> request.set_method(http.Put)
  |> request.set_body(ical_body)
  |> request.set_header("Content-Type", "text/calendar; charset=utf-8")
  |> request.set_header("If-None-Match", "*")
}

pub fn create_todo_request(
  client: Client(_, _),
  calendar: Calendar,
  summary: String,
) -> Request(String) {
  let uid = uuid.v4_string()
  let created = timestamp.system_time() |> formal_cal_date()
  create_todo_request_with(client, calendar, summary, uid, created)
}

pub fn send_create_todo(
  client: Client(_, IO(e)),
  calendar: Calendar,
  summary: String,
) -> Result(String, ShoggError(e)) {
  let request = create_todo_request(client, calendar, summary)
  let response = client.io.send(request)
  use response <- result.try(response |> result.map_error(SendError))
  parse_create_todo(response, request)
}

pub fn delete_todo_request(
  client: Client(_, _),
  vtodo: VTodo,
) -> Request(String) {
  client.request
  |> request.set_path(vtodo.meta.href)
  |> request.set_method(http.Delete)
  |> request.set_header("If-Match", vtodo.meta.etag)
}

pub fn send_delete_todo(
  client: Client(_, IO(e)),
  vtodo: VTodo,
) -> Result(Nil, ShoggError(e)) {
  let response = delete_todo_request(client, vtodo) |> client.io.send
  use response <- result.try(response |> result.map_error(SendError))
  parse_delete_todo_response(response)
}

pub fn parse_delete_todo_response(
  response: Response(String),
) -> Result(Nil, ShoggError(e)) {
  case response.status {
    204 | 200 -> Ok(Nil)
    _ ->
      Error(ParseError(
        "Delete failed with status: " <> int.to_string(response.status),
      ))
  }
}

pub fn parse_create_todo(
  response: Response(String),
  request: Request(String),
) -> Result(String, ShoggError(e)) {
  case response.status {
    201 -> Ok(request.path)
    _ ->
      Error(ParseError(
        "Create failed with status: " <> int.to_string(response.status),
      ))
  }
}
