import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import xml
import xml/decode

pub fn main() {
  gleeunit.main()
}

fn parse_ok(input: String) -> xml.Element {
  let assert Ok(element) = xml.parse(input, xml.NoWhitespaceOnly)
  element
}

// Parsing basics

pub fn parses_nested_elements_test() {
  let root = parse_ok("<a><b>hi</b><c/></a>")
  root.tag |> should.equal("a")
  root |> xml.text |> should.equal("")
  let assert Ok(b) = root |> xml.child("b")
  b |> xml.text |> should.equal("hi")
  let assert Ok(c) = root |> xml.child("c")
  c.children |> should.equal([])
}

pub fn parses_attributes_test() {
  let root = parse_ok("<comp name=\"VTODO\" other='x'/>")
  root |> xml.attr("name") |> should.equal(Some("VTODO"))
  root |> xml.attr("other") |> should.equal(Some("x"))
  root |> xml.attr("missing") |> should.equal(None)
  let assert [name, other] = root.attributes
  name.name |> should.equal("name")
  other.name |> should.equal("other")
}

pub fn parses_entities_test() {
  let root = parse_ok("<a>&lt;tag&gt; &amp; &quot;q&quot; &#65;&#x42;</a>")
  root |> xml.text |> should.equal("<tag> & \"q\" AB")
}

pub fn parses_attribute_entities_test() {
  let root = parse_ok("<a v=\"1 &lt; 2 &amp; 3\"/>")
  root |> xml.attr("v") |> should.equal(Some("1 < 2 & 3"))
}

pub fn parses_cdata_test() {
  let root = parse_ok("<a><![CDATA[<not & markup>]]></a>")
  root |> xml.text |> should.equal("<not & markup>")
}

pub fn skips_declaration_comment_and_pi_test() {
  let root =
    parse_ok(
      "<?xml version=\"1.0\"?><!-- hi --><?php echo 1 ?><a>x</a><!-- bye -->",
    )
  root.tag |> should.equal("a")
  root |> xml.text |> should.equal("x")
}

pub fn keeps_comments_inside_elements_test() {
  let root = parse_ok("<a><!-- keep me --></a>")
  let assert [xml.Comment(content)] = root.children
  content |> should.equal(" keep me ")
}

pub fn errors_on_mismatched_tag_test() {
  xml.parse("<a><b></a></b>", xml.NoWhitespaceOnly)
  |> should.be_error
}

pub fn errors_on_unclosed_tag_test() {
  xml.parse("<a><b>", xml.NoWhitespaceOnly)
  |> should.be_error
}

pub fn errors_on_unknown_entity_test() {
  xml.parse("<a>&nope;</a>", xml.NoWhitespaceOnly)
  |> should.be_error
}

pub fn errors_on_text_outside_root_test() {
  xml.parse("stray<a/>", xml.NoWhitespaceOnly)
  |> should.be_error
}

pub fn errors_on_two_roots_test() {
  xml.parse("<a/><b/>", xml.NoWhitespaceOnly)
  |> should.be_error
}

pub fn errors_on_no_root_test() {
  xml.parse("<!-- just a comment -->", xml.NoWhitespaceOnly)
  |> should.be_error
}

pub fn allows_newlines_outside_root_test() {
  // Pretty-printed documents start with a newline after the declaration.
  let assert Ok(_) = xml.parse("\n<a/>\n", xml.KeepWhitespace)
}

// Whitespace modes

pub fn keep_whitespace_test() {
  let root = xml.parse("\n  <a>  x  </a>\n", xml.KeepWhitespace)
  let assert Ok(a) = root
  // The indentation around the root is outside it and whitespace-only, so it
  // is allowed; the text inside is verbatim.
  a |> xml.text |> should.equal("  x  ")
}

pub fn keep_whitespace_preserves_ical_test() {
  let ical = "BEGIN:VCALENDAR\nVERSION:2.0\nEND:VCALENDAR\n"
  let root = xml.parse("<c:calendar-data xmlns:c=\"urn:x\">" <> ical <> "</c:calendar-data>", xml.KeepWhitespace)
  let assert Ok(data) = root
  data |> xml.text |> should.equal(ical)
}

pub fn no_whitespace_only_drops_indentation_test() {
  let root =
    parse_ok("<a>\n  <b>x</b>\n  <c>  y  </c>\n</a>")
  // Indentation between elements is gone, inner text verbatim.
  root |> xml.text |> should.equal("")
  let assert Ok(b) = root |> xml.child("b")
  b |> xml.text |> should.equal("x")
  let assert Ok(c) = root |> xml.child("c")
  c |> xml.text |> should.equal("  y  ")
}

pub fn trim_whitespace_test() {
  let root = xml.parse("<a>\n  <b>  x  </b>\n</a>", xml.TrimWhitespace)
  let assert Ok(a) = root
  a |> xml.text |> should.equal("")
  let assert Ok(b) = a |> xml.child("b")
  b |> xml.text |> should.equal("x")
}

pub fn trim_whitespace_keeps_interior_test() {
  let root = xml.parse("<a>  one\ntwo  </a>", xml.TrimWhitespace)
  let assert Ok(a) = root
  a |> xml.text |> should.equal("one\ntwo")
}

// Namespaces

pub fn default_namespace_applies_to_elements_test() {
  let root = parse_ok("<multistatus xmlns=\"DAV:\"><response/></multistatus>")
  root.namespace |> should.equal("DAV:")
  let assert Ok(response) = root |> xml.child("response")
  response.namespace |> should.equal("DAV:")
  response.tag |> should.equal("response")
}

pub fn prefixed_namespace_resolves_test() {
  let root =
    parse_ok("<d:multistatus xmlns:d=\"DAV:\" xmlns:c=\"urn:caldav\">"
      <> "<C:calendar-data xmlns:C=\"urn:real\"/>"
      <> "</d:multistatus>")
  root.prefix |> should.equal("d")
  root.namespace |> should.equal("DAV:")
  // Nearest declaration wins over the outer "c" prefix.
  let assert Ok(data) = root |> xml.child("calendar-data")
  data.namespace |> should.equal("urn:real")
  data.prefix |> should.equal("C")
}

pub fn unprefixed_attribute_has_no_namespace_test() {
  let root = parse_ok("<a xmlns=\"DAV:\" lang=\"en\"/>")
  root.namespace |> should.equal("DAV:")
  // The xmlns declaration itself stays visible as an attribute.
  let assert [xmlns, lang] = root.attributes
  xmlns.name |> should.equal("xmlns")
  lang.namespace |> should.equal("")
  lang.name |> should.equal("lang")
}

pub fn unprefixed_element_without_default_namespace_test() {
  let root = parse_ok("<a><b/></a>")
  root.namespace |> should.equal("")
  let assert Ok(b) = root |> xml.child("b")
  b.namespace |> should.equal("")
}

pub fn shadowed_prefix_on_child_test() {
  let root = parse_ok("<a xmlns:p=\"one\"><p:b xmlns:p=\"two\"/></a>")
  let assert Ok(b) = root |> xml.child("b")
  b.namespace |> should.equal("two")
  b.prefix |> should.equal("p")
}

// Decoders

fn item_decoder() -> decode.Decoder(#(String, String)) {
  use href <- decode.field("href", decode.text)
  use tag <- decode.field("tag", decode.text)
  decode.success(#(href, tag))
}

fn items_decoder() -> decode.Decoder(List(#(String, String))) {
  use items <- decode.children("response", item_decoder())
  decode.success(items)
}

pub fn decodes_children_test() {
  let root =
    parse_ok("<multistatus><response><href>/a</href><tag>one</tag></response>"
      <> "<response><href>/b</href><tag>two</tag></response></multistatus>")
  decode.run(root, items_decoder())
  |> should.equal(Ok([#("/a", "one"), #("/b", "two")]))
}

pub fn decodes_single_child_as_list_test() {
  // One <response> decodes to a one-element list without one_of gymnastics.
  let root =
    parse_ok("<multistatus><response><href>/a</href><tag>x</tag></response></multistatus>")
  decode.run(root, items_decoder())
  |> should.equal(Ok([#("/a", "x")]))
}

pub fn decodes_at_path_test() {
  let root =
    parse_ok("<r><a><b><href>/deep</href></b></a></r>")
  decode.run(root, decode.at(["a", "b", "href"], decode.text))
  |> should.equal(Ok("/deep"))
}

pub fn optional_field_uses_default_test() {
  let root = parse_ok("<r><present>x</present></r>")
  let decoder = {
    use present <- decode.optional_field("present", "none", decode.text)
    use absent <- decode.optional_field("absent", "none", decode.text)
    decode.success(#(present, absent))
  }
  decode.run(root, decoder) |> should.equal(Ok(#("x", "none")))
}

pub fn field_missing_reports_path_test() {
  let root = parse_ok("<r><a><b/></a></r>")
  decode.run(root, decode.at(["a", "b"], decode.text))
  |> should.be_error
}

pub fn decodes_attribute_test() {
  let root = parse_ok("<r><comp name=\"VTODO\"/></r>")
  let decoder = {
    use name <- decode.field(
      "comp",
      decode.attribute("name", decode.success),
    )
    decode.success(name)
  }
  decode.run(root, decoder) |> should.equal(Ok("VTODO"))
}

pub fn decodes_namespace_strictly_test() {
  let root = parse_ok("<r xmlns=\"DAV:\"><href>/x</href></r>")
  // The child is in "DAV:", so a wrong namespace must fail.
  decode.run(root, decode.field_ns("urn:wrong", "href", decode.text, decode.success))
  |> should.be_error
  decode.run(root, decode.field_ns("DAV:", "href", decode.text, decode.success))
  |> should.equal(Ok("/x"))
}

pub fn decodes_element_escape_hatch_test() {
  let root = parse_ok("<r><a/><b/><a/></r>")
  let tags = {
    use all <- decode.all(decode.element)
    decode.success(all |> list.map(fn(el) { el.tag }))
  }
  decode.run(root, tags) |> should.equal(Ok(["a", "b", "a"]))
}

pub fn text_fails_on_empty_element_test() {
  let root = parse_ok("<a/>")
  decode.run(root, decode.text) |> should.be_error
}
