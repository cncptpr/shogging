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
  let body = read_response("user_info.xml")
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
  let body = read_response("user_info_nextcloud.xml")
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
  let body = read_response("calendars.xml")
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
