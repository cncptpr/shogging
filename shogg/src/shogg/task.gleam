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
import gleam/time/timestamp.{type Timestamp}
import parsed_it/xml
import shogg.{type ShoggError, ParseError, SendError, XmlDecodeError}
import shogg/calendar.{type Calendar}
import shogg/client.{type Client, type IO}
import shogg/namespace
import youid/uuid

pub type TaskMeta {
  TaskMeta(href: String, etag: String)
}

pub type Task {
  Task(
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
    meta: TaskMeta,
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

pub fn format_cal_date(now: Timestamp) {
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

pub fn is_competed(task) {
  case task {
    // Apple reads PERCENT-COMPLETE before it reads STATUS, so a task that is
    // fully counted is done as far as Reminders is concerned.
    Task(percent_complete: Some(100), ..) -> True
    Task(status: Some("COMPLETED"), ..) -> True
    Task(status: None, completed: Some(_), ..) -> True
    _ -> False
  }
}

pub fn tasks_request(client: Client(_), calendar: Calendar) -> Request(String) {
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

pub fn fetch_tasks(
  client: Client(IO(e)),
  calendar: Calendar,
) -> Result(List(Task), ShoggError(e)) {
  let response = tasks_request(client, calendar) |> client.io.send
  use response <- result.try(response |> result.map_error(SendError))
  parse_tasks(response)
}

pub fn parse_tasks(
  response: Response(String),
) -> Result(List(Task), ShoggError(e)) {
  use dyn <- result.try(
    xml.parse_dynamic(response.body) |> result.map_error(XmlDecodeError),
  )
  let stripped = namespace.strip_dynamic(dyn)
  use parsed <- result.try(
    decode.run(stripped, tasks_responses_decoder())
    |> result.map_error(xml.UnableToDecode)
    |> result.map_error(XmlDecodeError),
  )
  parsed
  |> list.filter_map(fn(t) { parse_ical(t) })
  |> Ok
}

fn tasks_responses_decoder() {
  use responses <- decode.optional_field(
    "response",
    [],
    decode_xml_list({
      use href <- decode.field(
        "href",
        decode.field("$text", decode.string, decode.success),
      )
      use props <- decode.field(
        "propstat",
        decode_xml_list(decode_tasks_propstat()),
      )
      case props |> option.values() |> list.first() {
        Ok(#(Some(etag), Some(data))) ->
          #(TaskMeta(href:, etag:), data)
          |> decode.success
        _ -> decode.failure(#(TaskMeta("", ""), ""), "No 200 OK propstat found")
      }
    }),
  )
  responses |> decode.success
}

fn decode_tasks_propstat() {
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
      "calendar-data",
      None,
      decode_text() |> decode.map(Some),
    )
    #(etag, calendar_data) |> decode.success
  })
  Some(prop) |> decode.success
}

pub fn parse_ical(t: #(TaskMeta, String)) -> Result(Task, String) {
  let #(meta, data) = t
  let lines = unfold(data)

  // TODO: Refactor entire ical parser
  //
  // The VTODO is looked for rather than expected in a fixed place: a server is
  // free to put other components in the same calendar, most often a VTIMEZONE
  // ahead of the todo.
  case list.find(lines, fn(l) { l == "BEGIN:VTODO" }) {
    Ok(_) ->
      case list.contains(lines, "BEGIN:VCALENDAR") {
        True -> {
          let task_lines =
            lines
            |> list.drop_while(fn(l) { l != "BEGIN:VTODO" })
            // The opening line is a delimiter rather than a property, so it is
            // dropped rather than collected as one named `BEGIN`.
            |> list.drop(1)
          parse_task(
            find_task_content(task_lines, 0),
            Task(..empty_task(), meta:),
          )
        }
        False -> Error("Expected BEGIN:VCALENDAR and BEGIN:VTODO")
      }
    Error(Nil) -> Error("Expected BEGIN:VCALENDAR and BEGIN:VTODO")
  }
}

/// Undo RFC 5545 line folding, so that the rest of the parser sees one line per
/// property.
///
/// A long line is broken by a newline followed by a single space or tab, and the
/// continuation is part of the value that was folded — not a property of its
/// own. This has to happen before anything splits on `:`, since a folded value
/// can contain one.
fn unfold(data: String) -> List(String) {
  data
  |> string.split("\n")
  |> list.fold([], fn(unfolded, line) {
    // A server sends CRLF, so the carriage return goes before anything else
    // looks at the line.
    let line = string.trim_end(line)
    case unfolded {
      [previous, ..rest] ->
        case is_continuation(line) {
          // The one space or tab that marks the fold is not part of the value.
          True -> [previous <> string.drop_start(line, 1), ..rest]
          False -> [line, ..unfolded]
        }

      [] -> [line]
    }
  })
  |> list.reverse
  |> list.filter(fn(l) { l != "" })
}

/// Whether a line carries on from the one before it, which RFC 5545 marks with
/// a single leading space or tab.
fn is_continuation(line: String) -> Bool {
  case line {
    "" -> False
    _ -> string.starts_with(line, " ") || string.starts_with(line, "\t")
  }
}

fn find_task_content(lines: List(String), idx: Int) -> List(String) {
  case lines {
    [] -> []
    ["END:VTODO", ..] -> ["END:VTODO"]
    [line, ..rest] -> [line, ..find_task_content(rest, idx + 1)]
  }
}

fn parse_ical_field(line: String) -> #(String, String) {
  case string.split_once(line, ":") {
    Ok(#(key, value)) -> #(property_name(key), value)
    Error(Nil) -> #(line, "")
  }
}

/// The name of a property, without any parameters.
///
/// A property may carry parameters, as in `SUMMARY;LANGUAGE=en:Buy milk`, so
/// what precedes the colon is not always the name on its own. The parameters are
/// of no interest here.
fn property_name(key: String) -> String {
  case string.split(key, ";") {
    [name, ..] -> name
    [] -> key
  }
}

fn empty_task() {
  Task(
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
    meta: TaskMeta("", ""),
  )
}

fn parse_task(lines: List(String), parsed: Task) -> Result(Task, String) {
  case lines {
    [] -> Error("Empty VTODO")
    ["END:VTODO"] -> Ok(parsed)
    ["END:VTODO", ..] -> Error("Extra content after END:VTODO")
    [line, ..rest] -> {
      use new_parsed <- result.try(parse_task(rest, parsed))
      case parse_ical_field(line) {
        #("VERSION", value) ->
          case value {
            "2.0" -> Ok(new_parsed)
            _ -> Error("Unsupported VERSION: " <> value)
          }
        #("UID", value) -> Ok(Task(..new_parsed, uid: value))
        #("DTSTAMP", value) -> Ok(Task(..new_parsed, dtstamp: value))
        #("CREATED", value) -> Ok(Task(..new_parsed, created: Some(value)))
        #("LAST-MODIFIED", value) ->
          Ok(Task(..new_parsed, last_modified: Some(value)))
        #("STATUS", value) -> Ok(Task(..new_parsed, status: Some(value)))
        #("SUMMARY", value) ->
          Ok(Task(..new_parsed, summary: Some(value |> remove_escape)))
        #("COMPLETED", value) -> Ok(Task(..new_parsed, completed: Some(value)))
        #("PERCENT-COMPLETE", value) ->
          case int.parse(value) {
            Ok(i) -> Ok(Task(..new_parsed, percent_complete: Some(i)))
            Error(_) -> Error("Invalid PERCENT-COMPLETE: " <> value)
          }
        #("X-APPLE-SORT-ORDER", value) ->
          case int.parse(value) {
            Ok(i) -> Ok(Task(..new_parsed, x_apple_sort_order: Some(i)))
            Error(_) -> Error("Invalid X-APPLE-SORT-ORDER: " <> value)
          }
        #(key, value) ->
          Ok(Task(..new_parsed, other: [#(key, value), ..new_parsed.other]))
      }
    }
  }
}

const chars_to_escape = ["\\", ",", ";"]

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

pub fn serialize_task(parsed: Task) -> String {
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

pub fn update_task_request(client: Client(_), task: Task) -> Request(String) {
  // TODO: update updated_last
  let body = serialize_task(task)
  client.request
  |> request.set_path(task.meta.href)
  |> request.set_method(http.Put)
  |> request.set_body(body)
  |> request.set_header("Content-Type", "text/calendar; charset=utf-8")
  |> request.set_header("If-Match", task.meta.etag)
}

pub fn send_update_task(
  client: Client(IO(e)),
  task: Task,
) -> Result(Task, ShoggError(e)) {
  let response = update_task_request(client, task) |> client.io.send
  use response <- result.try(response |> result.map_error(SendError))
  parse_update_task_response(response, task)
}

pub fn parse_update_task_response(
  response: Response(String),
  task: Task,
) -> Result(Task, ShoggError(e)) {
  case response.status, response.get_header(response, "etag") {
    204, Ok(etag) | 201, Ok(etag) ->
      Ok(Task(..task, meta: TaskMeta(..task.meta, etag:)))
    _, _ ->
      Error(ParseError(
        "Update failed with status: " <> int.to_string(response.status),
      ))
  }
}

pub fn create_task_request_with(
  client: Client(_),
  calendar: Calendar,
  summary: String,
  uid: String,
  created: Timestamp,
) -> Request(String) {
  let href = calendar.href <> uid <> ".ics"
  let created = created |> format_cal_date
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

pub fn create_task_request(
  client: Client(_),
  calendar: Calendar,
  summary: String,
) -> Request(String) {
  create_task_request_with(
    client,
    calendar,
    summary,
    uuid.v4_string(),
    timestamp.system_time(),
  )
}

pub fn send_create_task(
  client: Client(IO(e)),
  calendar: Calendar,
  summary: String,
) -> Result(String, ShoggError(e)) {
  let request = create_task_request(client, calendar, summary)
  let response = client.io.send(request)
  use response <- result.try(response |> result.map_error(SendError))
  parse_create_task(response, request)
}

pub fn delete_task_request(client: Client(_), task: Task) -> Request(String) {
  client.request
  |> request.set_path(task.meta.href)
  |> request.set_method(http.Delete)
  |> request.set_header("If-Match", task.meta.etag)
}

pub fn send_delete_task(
  client: Client(IO(e)),
  task: Task,
) -> Result(Nil, ShoggError(e)) {
  let response = delete_task_request(client, task) |> client.io.send
  use response <- result.try(response |> result.map_error(SendError))
  parse_delete_task_response(response)
}

pub fn parse_delete_task_response(
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

pub fn parse_create_task(
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
