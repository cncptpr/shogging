import gleam/http/request
import gleam/http/response
import gleam/option.{None}
import gleeunit
import gleeunit/should
import shogg/client
import shogg/task

pub fn main() {
  gleeunit.main()
}

fn empty_task() {
  task.Task(
    completed: None,
    created: None,
    dtstamp: "",
    last_modified: None,
    meta: task.TaskMeta(etag: "", href: ""),
    other: [],
    percent_complete: None,
    status: None,
    summary: None,
    uid: "",
    x_apple_sort_order: None,
  )
}

pub fn parse_update_task_response_success_test() {
  let resp =
    response.Response(status: 204, headers: [#("etag", "some-etag")], body: "")
  let assert Ok(task) = task.parse_update_task_response(resp, empty_task())
  task.meta.etag |> should.equal("some-etag")
}

pub fn parse_update_task_response_created_test() {
  let resp =
    response.Response(status: 201, headers: [#("etag", "some-etag")], body: "")
  let assert Ok(task) = task.parse_update_task_response(resp, empty_task())
  task.meta.etag |> should.equal("some-etag")
}

pub fn parse_update_task_response_failure_test() {
  let resp = response.Response(status: 400, headers: [], body: "error")
  task.parse_update_task_response(resp, empty_task()) |> should.be_error()
}

pub fn parse_delete_task_response_success_test() {
  let resp = response.Response(status: 204, headers: [], body: "")
  let assert Ok(Nil) = task.parse_delete_task_response(resp)
}

pub fn parse_delete_task_response_ok_test() {
  let resp = response.Response(status: 200, headers: [], body: "")
  let assert Ok(Nil) = task.parse_delete_task_response(resp)
}

pub fn parse_delete_task_response_failure_test() {
  let resp = response.Response(status: 400, headers: [], body: "error")
  task.parse_delete_task_response(resp) |> should.be_error()
}

pub fn parse_create_task_response_success_test() {
  let req = request.new() |> request.set_path("/test/path.ics")
  let resp = response.Response(status: 201, headers: [], body: "")
  let assert Ok(path) = task.parse_create_task(resp, req)
  path |> should.equal("/test/path.ics")
}

pub fn parse_create_task_response_failure_test() {
  let req = request.new() |> request.set_path("/test/path.ics")
  let resp = response.Response(status: 400, headers: [], body: "error")
  task.parse_create_task(resp, req) |> should.be_error()
}

pub fn parse_discovery_response_301_test() {
  let resp =
    response.Response(
      status: 301,
      headers: [#("location", "/caldav/user/")],
      body: "",
    )
  let assert Ok(server) = client.parse_server_info(resp)
  server |> should.equal(client.ServerInfo("/caldav/user/"))
}

pub fn parse_discovery_response_302_test() {
  let resp =
    response.Response(
      status: 302,
      headers: [#("location", "/caldav/")],
      body: "",
    )
  let assert Ok(server) = client.parse_server_info(resp)
  server |> should.equal(client.ServerInfo("/caldav/"))
}

pub fn parse_discovery_response_307_test() {
  let resp =
    response.Response(
      status: 307,
      headers: [#("location", "/some/path/")],
      body: "",
    )
  let assert Ok(server) = client.parse_server_info(resp)
  server |> should.equal(client.ServerInfo("/some/path/"))
}

pub fn parse_discovery_response_308_test() {
  let resp =
    response.Response(status: 308, headers: [#("location", "/dav/")], body: "")
  let assert Ok(path) = client.parse_server_info(resp)
  path |> should.equal(client.ServerInfo("/dav/"))
}

pub fn parse_discovery_response_no_location_test() {
  let resp = response.Response(status: 301, headers: [], body: "")
  client.parse_server_info(resp) |> should.be_error()
}

pub fn parse_discovery_response_non_redirect_test() {
  let resp = response.Response(status: 200, headers: [], body: "OK")
  client.parse_server_info(resp) |> should.be_error()
}
