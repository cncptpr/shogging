import gleam/bit_array
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/option
import gleam/string
import gleeunit
import gleeunit/should
import shogg/caldav

pub fn main() {
  gleeunit.main()
}

fn base64_encode(input: String) -> String {
  bit_array.base64_encode(bit_array.from_string(input), False)
}

pub fn new_client_creates_request_with_basic_auth_test() {
  let config =
    caldav.ConnectionConfig(
      url: "https://caldav.example.com/principal/user",
      username: "testuser",
      password: "testpass",
    )

  let assert Ok(req) = caldav.new_client(config)

  req.method |> should.equal(http.Get)
  req.host |> should.equal("caldav.example.com")
  req.scheme |> should.equal(http.Https)
  req.path |> should.equal("/principal/user")

  let assert Ok(auth_header) = request.get_header(req, "authorization")
  let expected = "Basic " <> base64_encode("testuser:testpass")
  auth_header |> should.equal(expected)

  let assert Ok(content_type) = request.get_header(req, "content-type")
  content_type |> should.equal("application/xml; charset=utf-8")

  string.contains(req.body, "D:current-user-principal") |> should.equal(True)
}

pub fn new_client_with_http_scheme_test() {
  let config =
    caldav.ConnectionConfig(
      url: "http://caldav.example.com/caldav",
      username: "user",
      password: "pass",
    )

  let assert Ok(req) = caldav.new_client(config)

  req.scheme |> should.equal(http.Http)
  req.host |> should.equal("caldav.example.com")
}

pub fn new_client_uses_default_port_test() {
  let config =
    caldav.ConnectionConfig(
      url: "https://caldav.example.com/caldav",
      username: "user",
      password: "pass",
    )

  let assert Ok(req) = caldav.new_client(config)

  req.port |> should.equal(option.Some(443))
}

pub fn new_client_with_explicit_port_test() {
  let config =
    caldav.ConnectionConfig(
      url: "https://caldav.example.com:8443/caldav",
      username: "user",
      password: "pass",
    )

  let assert Ok(req) = caldav.new_client(config)

  req.port |> should.equal(option.Some(8443))
}

pub fn new_client_invalid_url_test() {
  let config =
    caldav.ConnectionConfig(
      url: "not-a-valid-url",
      username: "user",
      password: "pass",
    )

  let result = caldav.new_client(config)

  result |> should.equal(Error(caldav.InvalidUrl))
}

pub fn handle_new_client_response_parses_principal_url_test() {
  let config =
    caldav.ConnectionConfig(
      url: "https://caldav.example.com/",
      username: "user",
      password: "pass",
    )

  let resp_body =
    "<?xml version=\"1.0\"?>
<D:multistatus xmlns:D=\"DAV:\">
  <D:response>
    <D:href>/principal/user</D:href>
    <D:propstat>
      <D:prop>
        <D:current-user-principal>
          <D:href>/principal/user/</D:href>
        </D:current-user-principal>
      </D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>"

  let resp =
    response.new(200)
    |> response.set_body(resp_body)

  let result = caldav.handle_new_client_response(config, resp)

  let assert Ok(client) = result
  client.principal_url |> should.equal("/principal/user/")
}

pub fn handle_new_client_response_no_principal_test() {
  let config =
    caldav.ConnectionConfig(
      url: "https://caldav.example.com/",
      username: "user",
      password: "pass",
    )

  let resp_body =
    "<?xml version=\"1.0\"?>
<D:multistatus xmlns:D=\"DAV:\">
</D:multistatus>"

  let resp =
    response.new(200)
    |> response.set_body(resp_body)

  let result = caldav.handle_new_client_response(config, resp)

  result |> should.equal(Error(caldav.NoPrincipalUrl))
}

pub fn get_calendars_request_creates_report_request_test() {
  let client =
    caldav.CalDAVClient(
      url: "https://caldav.example.com/principal/user",
      principal_url: "/principal/user/",
    )

  let req = caldav.get_calendars_request(client)

  req.method |> should.equal(http.Other("REPORT"))
  req.path |> should.equal("/principal/user/")
  string.contains(req.body, "C:calendar-query") |> should.equal(True)
  string.contains(req.body, "C:display-name") |> should.equal(True)
  string.contains(req.body, "D:href") |> should.equal(True)
}

pub fn handle_get_calendars_response_parses_calendars_test() {
  let resp_body =
    "<?xml version=\"1.0\"?>
<D:multistatus xmlns:D=\"DAV:\" xmlns:C=\"urn:ietf:params:xml:ns:caldav\">
  <D:response>
    <D:href>/calendars/work</D:href>
    <D:propstat>
      <D:prop>
        <C:display-name>Work Calendar</C:display-name>
        <C:description>Work events</C:description>
        <C:timezone>America/New_York</C:timezone>
        <D:sync-token>https://caldav.example.com/sync/123</D:sync-token>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/calendars/personal</D:href>
    <D:propstat>
      <D:prop>
        <C:display-name>Personal</C:display-name>
        <C:description>Personal events</C:description>
        <C:timezone>America/Los_Angeles</C:timezone>
        <D:sync-token>https://caldav.example.com/sync/456</D:sync-token>
      </D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>"

  let resp =
    response.new(200)
    |> response.set_body(resp_body)

  let result = caldav.handle_get_calendars_response(resp)

  let assert Ok(calendars) = result
  list.length(calendars) |> should.equal(2)

  let assert [cal1, cal2, ..] = calendars
  cal1.href |> should.equal("/calendars/work")
  cal1.display_name |> should.equal("Work Calendar")
  cal1.description |> should.equal(option.Some("Work events"))
  cal1.timezone |> should.equal(option.Some("America/New_York"))
  cal1.sync_token
  |> should.equal(option.Some("https://caldav.example.com/sync/123"))

  cal2.href |> should.equal("/calendars/personal")
  cal2.display_name |> should.equal("Personal")
}

pub fn handle_get_calendars_response_empty_test() {
  let resp_body =
    "<?xml version=\"1.0\"?>
<D:multistatus xmlns:D=\"DAV:\">
</D:multistatus>"

  let resp =
    response.new(200)
    |> response.set_body(resp_body)

  let result = caldav.handle_get_calendars_response(resp)

  result |> should.equal(Error(caldav.NoCalendars))
}
