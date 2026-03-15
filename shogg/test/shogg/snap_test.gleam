import birdie
import gleam/http
import gleam/http/request
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import shogg/calendar
import shogg/client
import shogg/vtodo

pub fn main() {
  birdie.main()
}

fn setup_client() {
  let host = "calendar.example"
  let username = "Username"
  let password = "Password"

  client.new_client(client.https, host:, username:, password:)
  |> client.set_user_path("/caldav/7b8a9e3b-6655-40b8-8080-b89f75a5272a/")
}

fn format_request(req: request.Request(String)) {
  req.method |> http.method_to_string
  <> " "
  <> req.path
  <> " "
  <> req.scheme
  |> http.scheme_to_string
  |> string.uppercase
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
    components: [calendar.VTodo, calendar.VEvent],
    color: None,
  )
}

fn test_vtodo() {
  vtodo.VTodo(
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
    meta: vtodo.VTodoMeta(
      href: "/caldav/7b8a9e3b-6655-40b8-8080-b89f75a5272a/calendars/work/test-uid-12345.ics",
      etag: "\"abc123\"",
    ),
  )
}

pub fn user_info_request_test() {
  setup_client()
  |> client.user_info_request
  |> format_request
  |> birdie.snap(title: "User Info Request")
}

pub fn calendars_request_test() {
  setup_client()
  |> calendar.calendars_request
  |> format_request
  |> birdie.snap(title: "Calendars Request")
}

pub fn todos_request_test() {
  setup_client()
  |> vtodo.todos_request(test_calendar())
  |> format_request
  |> birdie.snap(title: "Todos Request")
}

pub fn update_todo_request_test() {
  setup_client()
  |> vtodo.update_todo_request(test_vtodo())
  |> format_request
  |> birdie.snap(title: "Update Todo Request")
}

pub fn create_todo_request_test() {
  setup_client()
  |> vtodo.create_todo_request_with(
    test_calendar(),
    "New Todo",
    "test-uid-fixed",
    "20240315T120000Z",
  )
  |> format_request
  |> birdie.snap(title: "Create Todo Request")
}

pub fn delete_todo_request_test() {
  setup_client()
  |> vtodo.delete_todo_request(test_vtodo())
  |> format_request
  |> birdie.snap(title: "Delete Todo Request")
}

pub fn serialize_vtodo_test() {
  test_vtodo()
  |> vtodo.serialize_vtodo
  |> birdie.snap(title: "Serialize VTodo")
}
