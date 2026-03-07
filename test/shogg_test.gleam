import gleam/http
import gleam/http/request
import gleam/string
import gleeunit
import gleeunit/should
import shogg/client

pub fn main() {
  gleeunit.main()
}

pub fn new_client_creates_request_with_basic_auth_test() {
  let client =
    client.new_client(http.Https, "caldav.example.com", "testuser", "testpass")

  let req = client.user_info_request(client)

  req.scheme |> should.equal(http.Https)
  req.host |> should.equal("caldav.example.com")

  let assert Ok(auth_header) = request.get_header(req, "authorization")
  string.starts_with(auth_header, "Basic ") |> should.be_true()
}

pub fn encode_basic_auth_test() {
  let result = client.encode_basic_auth("user", "pass")
  string.starts_with(result, "Basic ") |> should.be_true()
}
