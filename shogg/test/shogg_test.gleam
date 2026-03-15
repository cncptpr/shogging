import gleam/http
import gleam/http/request
import gleeunit
import gleeunit/should
import shogg/client.{ServerInfo}

pub fn main() {
  gleeunit.main()
}

pub fn new_client_creates_request_with_basic_auth_test() {
  let client =
    client.new_client(http.Https, "caldav.example.com", "user", "pass")

  let req = client.user_info_request(client, ServerInfo("/caldav/"))

  req.scheme |> should.equal(http.Https)
  req.host |> should.equal("caldav.example.com")

  let assert Ok(auth_header) = request.get_header(req, "authorization")
  auth_header |> should.equal("Basic dXNlcjpwYXNz")
}
