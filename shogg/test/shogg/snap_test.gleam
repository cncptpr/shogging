import birdie
import gleam/http
import gleam/http/request
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam/time/timestamp
import shogg/calendar
import shogg/capture
import shogg/client
import shogg/task

pub fn main() {
  birdie.main()
}

fn setup_client() {
  let host = "calendar.example"
  let username = "Username"
  let password = "Password"

  client.new_client(client.https, host:, username:, password:)
}

fn format_request(req: request.Request(String)) {
  let port = case req.port {
    Some(port) -> ":" <> int.to_string(port)
    None -> ""
  }
  "> "
  <> req.scheme |> http.scheme_to_string
  <> "://"
  <> req.host
  <> port
  <> "/\n\n"
  <> req.method |> http.method_to_string
  <> " "
  <> req.path
  <> "\n"
  |> list.fold(over: req.headers, from: _, with: fn(acc, h) {
    acc <> h.0 <> ": " <> h.1 <> "\n"
  })
  <> "\n"
  <> req.body
}

fn test_calendar() {
  calendar.Calendar(
    href: "/caldav/7b8a9e3b-6655-40b8-8080-b89f75a5272a/calendars/work/",
    name: "Work",
    ctag: "12345",
    components: [calendar.VTask, calendar.VEvent],
    color: None,
  )
}

fn test_task() {
  task.Task(
    uid: "test-uid-12345",
    dtstamp: "20240315T120000Z",
    created: Some("20240315T120000Z"),
    last_modified: None,
    status: Some("NEEDS-ACTION"),
    summary: Some("Test Todo"),
    completed: None,
    percent_complete: None,
    x_apple_sort_order: None,
    other: [],
    meta: task.TaskMeta(
      href: "/caldav/7b8a9e3b-6655-40b8-8080-b89f75a5272a/calendars/work/test-uid-12345.ics",
      etag: "\"abc123\"",
    ),
  )
}

pub fn user_info_request_test() {
  let server = client.ServerInfo(base_path: "/caldav/")
  setup_client()
  |> client.user_info_request(server)
  |> format_request
  |> birdie.snap(title: "User Info Request")
}

pub fn discovery_request_test() {
  setup_client()
  |> client.server_info_request
  |> format_request
  |> birdie.snap(title: "Discovery Request")
}

pub fn calendars_request_test() {
  let home_set =
    client.CalendarHomeSet("/caldav/7b8a9e3b-6655-40b8-8080-b89f75a5272a/")

  setup_client()
  |> calendar.calendars_request(home_set)
  |> format_request
  |> birdie.snap(title: "Calendars Request")
}

pub fn calendar_home_set_request_test() {
  let user_info = client.UserInfo("/remote.php/dav/principals/users/testuser/")

  setup_client()
  |> client.calendar_home_set_request(user_info)
  |> format_request
  |> birdie.snap(title: "Calendar Home Set Request")
}

pub fn changed_request_test() {
  setup_client()
  |> calendar.changed_request(test_calendar())
  |> format_request
  |> birdie.snap(title: "Changed Request")
}

pub fn tasks_request_test() {
  setup_client()
  |> task.tasks_request(test_calendar())
  |> format_request
  |> birdie.snap(title: "Tasks Request")
}

pub fn update_task_request_test() {
  setup_client()
  |> task.update_task_request(test_task())
  |> format_request
  |> birdie.snap(title: "Update Task Request")
}

pub fn create_task_request_test() {
  setup_client()
  |> task.create_task_request_with(
    test_calendar(),
    "New Todo",
    "test-uid-fixed",
    timestamp.from_unix_seconds(0),
  )
  |> format_request
  |> birdie.snap(title: "Create Task Request")
}

pub fn delete_task_request_test() {
  setup_client()
  |> task.delete_task_request(test_task())
  |> format_request
  |> birdie.snap(title: "Delete Task Request")
}

pub fn serialize_vtask_test() {
  test_task()
  |> task.serialize_task
  |> birdie.snap(title: "Serialize VTask")
}

// --- Round trips through this project's Radicale ------------------------------

/// The first task Radicale answered the tasks REPORT with, parsed back from
/// the capture and serialised out again.
fn first_captured_task() {
  let assert Ok(tasks) = task.parse_tasks(capture.body("tasks.xml"))
  let assert Ok(first) = list.first(tasks)
  first
}

pub fn serialize_parsed_radicale_task_test() {
  first_captured_task()
  |> task.serialize_task
  |> birdie.snap(title: "Serialize Parsed Radicale Task")
}

/// The exact request that would push the parsed task back to the server,
/// If-Match etag and all.
pub fn update_parsed_radicale_task_request_test() {
  setup_client()
  |> task.update_task_request(first_captured_task())
  |> format_request
  |> birdie.snap(title: "Update Parsed Radicale Task Request")
}

// --- Escaping -----------------------------------------------------------------

/// A summary with every characterical has to escape, plus a non-ASCII
/// letter, as it goes out on the wire.
pub fn serialize_escaped_summary_test() {
  task.Task(
    ..test_task(),
    summary: Some("Milk, eggs; back\\slash und Ünïcode, twice"),
  )
  |> task.serialize_task
  |> birdie.snap(title: "Serialize Escaped Summary")
}

pub fn create_task_request_escaped_summary_test() {
  setup_client()
  |> task.create_task_request_with(
    test_calendar(),
    "Milk, eggs; back\\slash, twice",
    "uid-escaped-1",
    timestamp.from_unix_seconds(946_684_800),
  )
  |> format_request
  |> birdie.snap(title: "Create Request Escaped Summary")
}

// --- Tables of results --------------------------------------------------------

/// Every calendar the original Radicale capture advertised, one per line.
pub fn parsed_calendars_table_test() {
  let assert Ok(calendars) =
    calendar.parse_calendars(capture.body("calendars.xml"))

  calendars
  |> list.map(fn(cal) {
    let color = case cal.color {
      Some(color) -> color
      None -> "-"
    }
    [
      cal.name,
      color,
      string.inspect(cal.components),
      cal.href,
    ]
    |> string.join(" | ")
  })
  |> string.join("\n")
  |> birdie.snap(title: "Parsed Radicale Calendars")
}

/// The seeded tasks: uid, status, summary, percentage, and whatever landed in
/// `other`.
pub fn parsed_seeded_tasks_table_test() {
  let assert Ok(tasks) = task.parse_tasks(capture.body("tasks_seeded.xml"))

  tasks
  |> list.map(fn(t) {
    let status = case t.status {
      Some(status) -> status
      None -> "-"
    }
    let summary = case t.summary {
      Some(summary) -> summary
      None -> "-"
    }
    let percent = case t.percent_complete {
      Some(percent) -> int.to_string(percent)
      None -> "-"
    }
    let other = case t.other {
      [] -> "-"
      fields -> string.inspect(fields)
    }
    [t.uid, status, summary, percent, other] |> string.join(" | ")
  })
  |> string.join("\n")
  |> birdie.snap(title: "Parsed Seeded Radicale Tasks")
}

/// The ical parser's answers for a spread of inputs, errors included. The
/// inspect output shows exactly what a caller would get back.
pub fn ical_parse_results_table_test() {
  let meta = task.TaskMeta(href: "/tasks/1.ics", etag: "\"1\"")
  let samples = [
    #(
      "plain todo",
      "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:1\r\nSUMMARY:Buy milk\r\nEND:VTODO\r\nEND:VCALENDAR\r\n",
    ),
    #(
      "missing uid",
      "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nSUMMARY:No uid\r\nEND:VTODO\r\nEND:VCALENDAR\r\n",
    ),
    #(
      "empty vtodo",
      "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nEND:VTODO\r\nEND:VCALENDAR\r\n",
    ),
    #(
      "duplicate summary",
      "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:1\r\nSUMMARY:First\r\nSUMMARY:Second\r\nEND:VTODO\r\nEND:VCALENDAR\r\n",
    ),
    #(
      "escaped summary",
      "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:1\r\nSUMMARY:Hello\\, World\r\nEND:VTODO\r\nEND:VCALENDAR\r\n",
    ),
    #(
      "bad percent",
      "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:1\r\nPERCENT-COMPLETE:half\r\nEND:VTODO\r\nEND:VCALENDAR\r\n",
    ),
    #(
      "no vtodo",
      "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:1\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
    ),
    #("truncated", "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:1"),
    #("not ical", "hello world"),
    #("empty", ""),
  ]

  samples
  |> list.map(fn(sample) {
    let #(name, ical) = sample
    name <> ": " <> string.inspect(task.parse_ical(#(meta, ical)))
  })
  |> string.join("\n")
  |> birdie.snap(title: "Parse Ical Results")
}

/// The DAV-level answer for the captured bodies: two listings and two that
/// are not task listings at all.
pub fn parse_tasks_results_table_test() {
  let samples = [
    #("seeded radicale", capture.body("tasks_seeded.xml")),
    #("original capture", capture.body("tasks.xml")),
    #("propfind 404 body", capture.raw("propfind_missing.txt")),
    #("empty calendar report", capture.raw("report_empty_calendar.txt")),
  ]

  samples
  |> list.map(fn(sample) {
    let #(name, resp) = sample
    case task.parse_tasks(resp) {
      Ok(tasks) ->
        name <> ": Ok(" <> int.to_string(list.length(tasks)) <> " tasks)"
      Error(error) -> name <> ": " <> string.inspect(error)
    }
  })
  |> string.join("\n")
  |> birdie.snap(title: "Parse Tasks Results")
}
