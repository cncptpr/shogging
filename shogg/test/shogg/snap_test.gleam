import birdie
import gleam/http
import gleam/http/request
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/time/timestamp
import shogg/calendar
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
