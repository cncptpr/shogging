import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/option.{None}
import gleeunit
import gleeunit/should
import shogg/calendar
import shogg/client
import shogg/vtodo
import simplifile

pub fn main() {
  gleeunit.main()
}

fn read_response(file) {
  let assert Ok(body) = simplifile.read("test/shogg/responses/" <> file)
  response.Response(status: 0, headers: [], body:)
}

pub fn parse_user_info_test() {
  let response = read_response("user_info.xml")
  let assert Ok(parsed) = client.parse_user_info(response)

  let user_info =
    client.UserInfo("/caldav/7b8a9e3b-6655-40b8-8080-b89f75a5272a/")

  parsed |> should.equal(user_info)
}

pub fn parse_calendars_test() {
  let response = read_response("calendars.xml")
  let assert Ok(calendars) = calendar.parse_calendars(response)
  calendars |> list.length |> should.equal(3)

  let assert Ok(cal) = calendars |> list.first()
  cal.name |> should.not_equal("")
  cal.href |> should.not_equal("")
  cal.ctag |> should.not_equal("")
}

pub fn parse_todos_test() {
  let response = read_response("todos.xml")
  let assert Ok(todos) = vtodo.parse_todos(response)
  todos |> should.not_equal([])

  let assert Ok(item) = todos |> list.first()
  item.uid |> should.not_equal("")
  item.dtstamp |> should.not_equal("")
}

pub fn parse_update_todo_response_success_test() {
  let response = response.Response(status: 204, headers: [], body: "")
  let assert Ok(Nil) = vtodo.parse_update_todo_response(response)
}

pub fn parse_update_todo_response_created_test() {
  let response = response.Response(status: 201, headers: [], body: "")
  let assert Ok(Nil) = vtodo.parse_update_todo_response(response)
}

pub fn parse_update_todo_response_failure_test() {
  let response = response.Response(status: 400, headers: [], body: "error")
  vtodo.parse_update_todo_response(response) |> should.be_error()
}

pub fn parse_delete_todo_response_success_test() {
  let response = response.Response(status: 204, headers: [], body: "")
  let assert Ok(Nil) = vtodo.parse_delete_todo_response(response)
}

pub fn parse_delete_todo_response_ok_test() {
  let response = response.Response(status: 200, headers: [], body: "")
  let assert Ok(Nil) = vtodo.parse_delete_todo_response(response)
}

pub fn parse_delete_todo_response_failure_test() {
  let response = response.Response(status: 400, headers: [], body: "error")
  vtodo.parse_delete_todo_response(response) |> should.be_error()
}

pub fn parse_create_todo_response_success_test() {
  let req = request.new() |> request.set_path("/test/path.ics")
  let response = response.Response(status: 201, headers: [], body: "")
  let assert Ok(path) = vtodo.parse_create_todo(response, req)
  path |> should.equal("/test/path.ics")
}

pub fn parse_create_todo_response_failure_test() {
  let req = request.new() |> request.set_path("/test/path.ics")
  let response = response.Response(status: 400, headers: [], body: "error")
  vtodo.parse_create_todo(response, req) |> should.be_error()
}

pub fn parse_discovery_response_301_test() {
  let response =
    response.Response(
      status: 301,
      headers: [#("location", "/caldav/user/")],
      body: "",
    )
  let assert Ok(server) = client.parse_server_info(response)
  server |> should.equal(client.ServerInfo("/caldav/user/"))
}

pub fn parse_discovery_response_302_test() {
  let response =
    response.Response(
      status: 302,
      headers: [#("location", "/caldav/")],
      body: "",
    )
  let assert Ok(server) = client.parse_server_info(response)
  server |> should.equal(client.ServerInfo("/caldav/"))
}

pub fn parse_discovery_response_307_test() {
  let response =
    response.Response(
      status: 307,
      headers: [#("location", "/some/path/")],
      body: "",
    )
  let assert Ok(server) = client.parse_server_info(response)
  server |> should.equal(client.ServerInfo("/some/path/"))
}

pub fn parse_discovery_response_308_test() {
  let response =
    response.Response(status: 308, headers: [#("location", "/dav/")], body: "")
  let assert Ok(path) = client.parse_server_info(response)
  path |> should.equal(client.ServerInfo("/dav/"))
}

pub fn parse_discovery_response_no_location_test() {
  let response = response.Response(status: 301, headers: [], body: "")
  client.parse_server_info(response) |> should.be_error()
}

pub fn parse_discovery_response_non_redirect_test() {
  let response = response.Response(status: 200, headers: [], body: "OK")
  client.parse_server_info(response) |> should.be_error()
}

pub fn parse_changed_unchanged_test() {
  let calendars_response = read_response("calendars.xml")
  let assert Ok(calendars) = calendar.parse_calendars(calendars_response)
  let assert Ok(cal) =
    calendars
    |> list.filter(fn(c) { c.name == "Personal Calendar" })
    |> list.first()

  let unchanged_response = read_response("calendar_unchanged.xml")
  let assert Ok(calendar.Unchanged) =
    calendar.parse_changed(cal, unchanged_response)
}

pub fn parse_changed_changed_test() {
  let calendars_response = read_response("calendars.xml")
  let assert Ok(calendars) = calendar.parse_calendars(calendars_response)
  let assert Ok(cal) =
    calendars
    |> list.filter(fn(c) { c.name == "Personal Calendar" })
    |> list.first()

  let changed_response = read_response("calendar_changed.xml")
  let assert Ok(calendar.Changed(new_calendar)) =
    calendar.parse_changed(cal, changed_response)
  new_calendar.ctag |> should.not_equal(cal.ctag)
}

pub fn parse_changed_empty_test() {
  let body =
    "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<multistatus xmlns=\"DAV:\">\n</multistatus>"
  let calendar =
    calendar.Calendar(
      href: "/caldav/user/calendar/",
      name: "Test",
      ctag: "12345abc",
      components: [],
      color: None,
    )
  let resp = response.Response(status: 207, headers: [], body:)
  calendar.parse_changed(calendar, resp) |> should.be_error()
}
