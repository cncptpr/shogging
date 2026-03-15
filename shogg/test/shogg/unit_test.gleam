import gleam/http/request
import gleam/http/response
import gleam/list
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

fn setup_client() {
  let host = "calendar.example"
  let username = "Username"
  let password = "Password"

  client.new_client(client.https, host:, username:, password:)
  |> client.set_user_path("/caldav/7b8a9e3b-6655-40b8-8080-b89f75a5272a/")
}

pub fn parse_user_info_test() {
  let response = read_response("user_info.xml")
  let assert Ok(parsed) = client.parse_user_info(setup_client(), response)
  parsed.user_path
  |> should.equal("/caldav/7b8a9e3b-6655-40b8-8080-b89f75a5272a/")
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
