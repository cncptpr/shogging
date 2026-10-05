import gleam/option.{Some}
import gleam/string
import gleeunit
import gleeunit/should
import simplifile
import shogxml
import shogxml/decode

/// The new XML parser and decoders against the captured CalDAV responses:
/// namespace resolution, local-name matching without prefix surgery, and the
/// whitespace behaviour the iCalendar payloads depend on.
pub fn main() {
  gleeunit.main()
}

fn read_response(file: String) -> String {
  let assert Ok(body) = simplifile.read("test/shogg/responses/" <> file)
  body
}

pub fn decodes_hrefs_from_fixture_test() {
  let assert Ok(root) =
    shogxml.parse(read_response("radicale/user_info.xml"), shogxml.NoWhitespaceOnly)

  let decoder = {
    use responses <- decode.children("response", decode.at(["href"], decode.text))
    decode.success(responses)
  }

  decode.run(root, decoder)
  |> should.equal(Ok([
    "/caldav/",
    "/caldav/7b8a9e3b-6655-40b8-8080-b89f75a5272a/",
  ]))
}

pub fn resolves_namespaces_from_fixture_test() {
  let assert Ok(root) =
    shogxml.parse(read_response("radicale/tasks.xml"), shogxml.NoWhitespaceOnly)

  // The default xmlns applies to unprefixed elements...
  root.tag |> should.equal("multistatus")
  root.namespace |> should.equal(Some("DAV:"))

  // ...and the C prefix declared on the root resolves on descendants.
  let assert Ok(response) = shogxml.child(root, "response")
  let assert Ok(propstat) = shogxml.child(response, "propstat")
  let assert Ok(prop) = shogxml.child(propstat, "prop")
  let assert Ok(data) = shogxml.child(prop, "calendar-data")
  data.tag |> should.equal("calendar-data")
  data.prefix |> should.equal(Some("C"))
  data.namespace |> should.equal(Some("urn:ietf:params:xml:ns:caldav"))
}

pub fn keeps_ical_newlines_in_calendar_data_test() {
  let assert Ok(root) =
    shogxml.parse(read_response("radicale/tasks.xml"), shogxml.NoWhitespaceOnly)

  let assert Ok(response) = shogxml.child(root, "response")
  let assert Ok(propstat) = shogxml.child(response, "propstat")
  let assert Ok(prop) = shogxml.child(propstat, "prop")
  let assert Ok(data) = shogxml.child(prop, "calendar-data")
  let ical = shogxml.text(data)

  string.contains(ical, "BEGIN:VTODO") |> should.be_true
  string.contains(ical, "\n") |> should.be_true
  string.starts_with(ical, "BEGIN:VCALENDAR") |> should.be_true
}

pub fn whitespace_modes_test() {
  let input = "<a>\n  <b> x </b>\n</a>"

  let assert Ok(keep) = shogxml.parse(input, shogxml.KeepWhitespace)
  let assert Ok(kept_b) = shogxml.child(keep, "b")
  kept_b |> shogxml.text |> should.equal(" x ")

  let assert Ok(trim) = shogxml.parse(input, shogxml.TrimWhitespace)
  let assert Ok(trimmed_b) = shogxml.child(trim, "b")
  trimmed_b |> shogxml.text |> should.equal("x")

  // Indentation between elements disappears, but only when it is the whole
  // text run.
  let assert Ok(nested) = shogxml.parse("<a>\n  <b/>text\n  <c/></a>", shogxml.NoWhitespaceOnly)
  let assert Ok(b) = shogxml.child(nested, "b")
  let assert Ok(c) = shogxml.child(nested, "c")
  shogxml.children(nested) |> should.equal([b, c])
}
