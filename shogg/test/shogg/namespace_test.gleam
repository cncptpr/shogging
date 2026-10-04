import gleam/dynamic
import gleam/dynamic/decode
import gleam/list
import gleeunit
import gleeunit/should
import parsed_it/xml
import shogg/namespace
import simplifile

pub fn main() {
  gleeunit.main()
}

fn read_response(file) {
  let assert Ok(body) = simplifile.read("test/shogg/responses/" <> file)
  body
}

fn parse_with_stripped(body: String, inner: decode.Decoder(a)) {
  let assert Ok(dyn) = xml.parse_dynamic(body)
  let stripped = namespace.strip_dynamic(dyn)
  let assert Ok(result) = decode.run(stripped, inner)
  result
}

pub fn strip_simple_tag_test() {
  let xml = "<d:response xmlns:d=\"DAV:\"><d:href>/test</d:href></d:response>"
  let result =
    parse_with_stripped(xml, {
      use href <- decode.field(
        "href",
        decode.field("$text", decode.string, decode.success),
      )
      href |> decode.success
    })
  result |> should.equal("/test")
}

pub fn strip_user_info_test() {
  let body = read_response("radicale/user_info.xml")
  let result =
    parse_with_stripped(body, {
      use response <- decode.field(
        "response",
        decode.list({
          use href <- decode.field(
            "href",
            decode.field("$text", decode.string, decode.success),
          )
          href |> decode.success
        }),
      )
      response |> decode.success
    })
  result
  |> should.equal(["/caldav/", "/caldav/7b8a9e3b-6655-40b8-8080-b89f75a5272a/"])
}

pub fn strip_user_info_nextcloud_test() {
  let body = read_response("nextcloud/user_info.xml")
  let result =
    parse_with_stripped(body, {
      use response <- decode.field(
        "response",
        decode.list({
          use href <- decode.field(
            "href",
            decode.field("$text", decode.string, decode.success),
          )
          href |> decode.success
        }),
      )
      response |> decode.success
    })
  result |> should.not_equal([])
  let assert Ok(first) = result |> list.first()
  first |> should.equal("/remote.php/dav/")
}

pub fn strip_calendars_xml_test() {
  let body = read_response("radicale/calendars.xml")
  let result =
    parse_with_stripped(body, {
      use response <- decode.field(
        "response",
        decode.list({
          use href <- decode.field(
            "href",
            decode.field("$text", decode.string, decode.success),
          )
          href |> decode.success
        }),
      )
      response |> decode.success
    })
  result |> should.not_equal([])
}

pub fn strip_nested_tags_test() {
  let xml =
    "<d:root xmlns:d=\"DAV:\"><d:level1><d:level2><d:value>test</d:value></d:level2></d:level1></d:root>"
  let result =
    parse_with_stripped(xml, {
      use level1 <- decode.field("level1", {
        use level2 <- decode.field("level2", {
          use value <- decode.field(
            "value",
            decode.field("$text", decode.string, decode.success),
          )
          value |> decode.success
        })
        level2 |> decode.success
      })
      level1 |> decode.success
    })
  result |> should.equal("test")
}

/// Keys without a prefix are left exactly as they are.
pub fn strip_unprefixed_keys_test() {
  let xml = "<root><child>value</child></root>"
  let result =
    parse_with_stripped(xml, {
      use child <- decode.field(
        "child",
        decode.field("$text", decode.string, decode.success),
      )
      child |> decode.success
    })
  result |> should.equal("value")
}

/// A key with more than one colon loses only the prefix up to the first one.
pub fn strip_key_keeps_the_rest_test() {
  let dyn =
    dynamic.properties([
      #(dynamic.string("pre:mid:suffix"), dynamic.string("v")),
    ])
    |> namespace.strip_dynamic

  let assert Ok(value) =
    decode.run(dyn, {
      use value <- decode.field("mid:suffix", decode.string)
      decode.success(value)
    })
  value |> should.equal("v")
}

/// Stripping is recursive: a dict nested in a dict has its keys stripped too.
pub fn strip_strips_nested_keys_test() {
  let dyn =
    dynamic.properties([
      #(
        dynamic.string("ns:outer"),
        dynamic.properties([#(dynamic.string("ns:inner"), dynamic.string("v"))]),
      ),
    ])
    |> namespace.strip_dynamic

  let assert Ok(value) =
    decode.run(dyn, {
      use outer <- decode.field("outer", {
        use inner <- decode.field("inner", decode.string)
        decode.success(inner)
      })
      decode.success(outer)
    })
  value |> should.equal("v")
}

/// Strings and other primitives pass through untouched.
pub fn strip_leaves_primitives_alone_test() {
  let dyn = namespace.strip_dynamic(dynamic.string("plain"))
  dyn |> should.equal(dynamic.string("plain"))
}

pub fn strip_leaves_lists_of_primitives_alone_test() {
  let dyn =
    dynamic.list([dynamic.string("a"), dynamic.string("b")])
    |> namespace.strip_dynamic
  dyn |> should.equal(dynamic.list([dynamic.string("a"), dynamic.string("b")]))
}

/// The `$text` markers the ical decoders look for carry no colon, so they
/// survive the strip.
pub fn strip_leaves_text_marker_alone_test() {
  let dyn =
    dynamic.properties([#(dynamic.string("$text"), dynamic.string("v"))])
    |> namespace.strip_dynamic

  let assert Ok(value) =
    decode.run(dyn, {
      use value <- decode.field("$text", decode.string)
      decode.success(value)
    })
  value |> should.equal("v")
}

// --- Xmlns -------------------------------------------------------------------

pub fn xmlns_to_string_test() {
  namespace.to_string(namespace.DAV) |> should.equal("DAV:")
  namespace.to_string(namespace.CALDAV)
  |> should.equal("urn:ietf:params:xml:ns:caldav")
  namespace.to_string(namespace.CalendarServer)
  |> should.equal("http://calendarserver.org/ns/")
  // The Apple namespace really does contain a colon.
  namespace.to_string(namespace.Apple)
  |> should.equal("http://apple.com/ns:ical/")
}
