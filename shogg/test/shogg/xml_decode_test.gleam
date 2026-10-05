import gleam/option.{Some}
import gleam/string
import gleeunit
import gleeunit/should
import simplifile
import xml
import xml/decode

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
    xml.parse(read_response("radicale/user_info.xml"), xml.NoWhitespaceOnly)

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
    xml.parse(read_response("radicale/tasks.xml"), xml.NoWhitespaceOnly)

  // The default xmlns applies to unprefixed elements...
  root.tag |> should.equal("multistatus")
  root.namespace |> should.equal(Some("DAV:"))

  // ...and the C prefix declared on the root resolves on descendants.
  let assert Ok(response) = xml.child(root, "response")
  let assert Ok(propstat) = xml.child(response, "propstat")
  let assert Ok(prop) = xml.child(propstat, "prop")
  let assert Ok(data) = xml.child(prop, "calendar-data")
  data.tag |> should.equal("calendar-data")
  data.prefix |> should.equal(Some("C"))
  data.namespace |> should.equal(Some("urn:ietf:params:xml:ns:caldav"))
}

pub fn keeps_ical_newlines_in_calendar_data_test() {
  let assert Ok(root) =
    xml.parse(read_response("radicale/tasks.xml"), xml.NoWhitespaceOnly)

  let assert Ok(response) = xml.child(root, "response")
  let assert Ok(propstat) = xml.child(response, "propstat")
  let assert Ok(prop) = xml.child(propstat, "prop")
  let assert Ok(data) = xml.child(prop, "calendar-data")
  let ical = xml.text(data)

  string.contains(ical, "BEGIN:VTODO") |> should.be_true
  string.contains(ical, "\n") |> should.be_true
  string.starts_with(ical, "BEGIN:VCALENDAR") |> should.be_true
}

pub fn whitespace_modes_test() {
  let input = "<a>\n  <b> x </b>\n</a>"

  let assert Ok(keep) = xml.parse(input, xml.KeepWhitespace)
  let assert Ok(kept_b) = xml.child(keep, "b")
  kept_b |> xml.text |> should.equal(" x ")

  let assert Ok(trim) = xml.parse(input, xml.TrimWhitespace)
  let assert Ok(trimmed_b) = xml.child(trim, "b")
  trimmed_b |> xml.text |> should.equal("x")

  // Indentation between elements disappears, but only when it is the whole
  // text run.
  let assert Ok(nested) = xml.parse("<a>\n  <b/>text\n  <c/></a>", xml.NoWhitespaceOnly)
  let assert Ok(b) = xml.child(nested, "b")
  let assert Ok(c) = xml.child(nested, "c")
  xml.children(nested) |> should.equal([b, c])
}
