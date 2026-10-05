//// Pure Gleam XML parsing: no FFI, identical behaviour on Erlang and
//// JavaScript.
////
//// `parse` turns an XML string into a tree of `Element`s carrying the local
//// tag name, the resolved namespace URI, attributes, and children. Character
//// data arrives as `Text` nodes among the children, with three modes
//// controlling what happens to whitespace:
////
//// - `KeepWhitespace`: everything verbatim, needed when the text *is* the
////   payload (iCalendars, embedded scripts).
//// - `NoWhitespaceOnly`: text runs that are entirely whitespace (element
////   indentation) are dropped, others verbatim. The usual choice.
//// - `TrimWhitespace`: every text run is trimmed at both ends; runs left
////   empty are dropped.
////
//// The extracted tree is most easily consumed with the decoders in
//// `xml/decode`, which are modelled on `gleam/dynamic/decode`:
////
//// ```gleam
//// use items <- decode.children("response", item_decoder())
//// decode.run(root, decode.success(items))
//// ```
////
//// Plain navigation helpers (`children`, `child`, `text`, `attr`) are on this
//// module for when a decoder is overkill.

import gleam/dynamic/decode.{type DecodeError}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// A child of an element.
///
/// `Elem` wraps a nested element, `Text` carries character data (already
/// entity-unescaped and processed according to the whitespace mode), and
/// `Comment` keeps comment content for inspection. The navigation helpers and
/// decoders only look at element children unless stated otherwise.
pub type Node {
  Text(String)
  Comment(String)
  Elem(Element)
}

/// A parsed XML element.
pub type Element {
  Element(
    // The prefix exactly as written, None when the name has none.
    prefix: Option(String),
    // The namespace URI the prefix (or the default namespace) resolves to,
    // None when the name is in no namespace.
    namespace: Option(String),
    // The local name of the tag, without any prefix.
    tag: String,
    attributes: List(Attribute),
    children: List(Node),
  )
}

/// An attribute. Like elements, the name is stored local with the resolved
/// namespace; attributes without a prefix are always in no namespace, even
/// when a default `xmlns` is in effect.
pub type Attribute {
  Attribute(
    prefix: Option(String),
    namespace: Option(String),
    name: String,
    value: String,
  )
}

/// How whitespace in character data is handled while parsing.
pub type Whitespace {
  /// Text is kept exactly as it appears in the document.
  KeepWhitespace
  /// Text runs consisting solely of whitespace are dropped, others are kept
  /// verbatim. Good default for element-only content.
  NoWhitespaceOnly
  /// Every text run is trimmed at both ends; runs left empty are dropped.
  TrimWhitespace
}

/// Why a document could not be turned into the requested value.
pub type Error {
  /// The input is not well-formed XML. `position` is the grapheme offset of
  /// the offending construct.
  InvalidXml(message: String, position: Int)
  /// The document parsed but did not match the decoder it was run against.
  UnableToDecode(List(DecodeError))
}

/// Parses an XML document with the given whitespace mode.
///
/// ```gleam
/// let assert Ok(root) = xml.parse("<a><b>hi</b></a>", xml.NoWhitespaceOnly)
/// ```
pub fn parse(input: String, whitespace: Whitespace) -> Result(Element, Error) {
  parse_loop(string.to_graphemes(input), 0, [], None, whitespace)
}

// Navigation

/// The element children of `element`, in document order.
pub fn children(element: Element) -> List(Element) {
  list.filter_map(element.children, fn(node) {
    case node {
      Elem(child) -> Ok(child)
      Text(_) | Comment(_) -> Error(Nil)
    }
  })
}

/// The element children of `element` with the given local name, in document
/// order. The namespace is not considered; see `xml/decode` for
/// namespace-aware decoding.
pub fn children_named(element: Element, name: String) -> List(Element) {
  children(element)
  |> list.filter(fn(child) { child.tag == name })
}

/// The first element child with the given local name.
pub fn child(element: Element, name: String) -> Result(Element, Nil) {
  case children_named(element, name) {
    [first, ..] -> Ok(first)
    [] -> Error(Nil)
  }
}

/// The character data directly inside `element`, concatenated.
///
/// Deeper descendants' text is not included; the whitespace mode has already
/// been applied to each run at parse time.
pub fn text(element: Element) -> String {
  list.filter_map(element.children, fn(node) {
    case node {
      Text(value) -> Ok(value)
      _ -> Error(Nil)
    }
  })
  |> string.concat
}

/// The value of the attribute with the given local name.
pub fn attr(element: Element, name: String) -> Option(String) {
  find_attribute(element, name)
  |> option.map(fn(attribute) { attribute.value })
}

fn find_attribute(element: Element, name: String) -> Option(Attribute) {
  find_attribute_in(element.attributes, name)
}

fn find_attribute_in(
  attributes: List(Attribute),
  name: String,
) -> Option(Attribute) {
  case attributes {
    [] -> None
    [attribute, ..rest] ->
      case attribute.name == name {
        True -> Some(attribute)
        False -> find_attribute_in(rest, name)
      }
  }
}

// Parsing

type Frame {
  Frame(
    qualified: String,
    prefix: Option(String),
    namespace: Option(String),
    tag: String,
    scope: List(#(String, Option(String))),
    attributes: List(Attribute),
    children: List(Node),
  )
}

fn parse_loop(
  input: List(String),
  pos: Int,
  stack: List(Frame),
  root: Option(Element),
  whitespace: Whitespace,
) -> Result(Element, Error) {
  case input {
    [] ->
      case stack, root {
        [], Some(root) -> Ok(root)
        [], None -> Error(InvalidXml("Document has no root element", pos))
        [_, ..], _ ->
          Error(InvalidXml("Unexpected end of input: element not closed", pos))
      }

    ["<", "/", ..rest] -> handle_close(rest, pos, stack, root, whitespace)
    ["<", "!", "-", "-", ..rest] ->
      handle_comment(rest, pos, stack, root, whitespace)
    ["<", "!", "[", "C", "D", "A", "T", "A", "[", ..rest] ->
      handle_cdata(rest, pos, stack, root, whitespace)
    ["<", "?", ..rest] -> handle_pi(rest, pos, stack, root, whitespace)
    ["<", "!", ..rest] ->
      handle_declaration(rest, pos, stack, root, whitespace)
    ["<", ..rest] -> handle_open(rest, pos, stack, root, whitespace)
    _ -> handle_text(input, pos, stack, root, whitespace)
  }
}

fn handle_open(
  input: List(String),
  pos: Int,
  stack: List(Frame),
  root: Option(Element),
  whitespace: Whitespace,
) -> Result(Element, Error) {
  let #(name, rest, after_name) = take_name(input, pos + 1)
  case name == "" {
    True -> Error(InvalidXml("Expected an element name after '<'", pos))
    False -> {
      use #(raw_attrs, rest, after_attrs, self_closing) <- result.try(
        parse_attributes(rest, after_name),
      )
      let parent_scope = case stack {
        [] -> root_scope()
        [frame, ..] -> frame.scope
      }
      let frame = build_frame(name, raw_attrs, parent_scope)
      case self_closing {
        True -> {
          use #(stack, root) <- result.try(attach(frame, stack, root, pos))
          parse_loop(rest, after_attrs, stack, root, whitespace)
        }
        False ->
          parse_loop(rest, after_attrs, [frame, ..stack], root, whitespace)
      }
    }
  }
}

fn handle_close(
  input: List(String),
  pos: Int,
  stack: List(Frame),
  root: Option(Element),
  whitespace: Whitespace,
) -> Result(Element, Error) {
  let #(name, rest, after_name) = take_name(input, pos + 2)
  let #(rest, after_space) = skip_space(rest, after_name)
  case rest {
    [">", ..rest] ->
      case stack {
        [] ->
          Error(InvalidXml(
            "Closing tag </" <> name <> "> has no matching open tag",
            pos,
          ))
        [frame, ..parent] ->
          case frame.qualified == name {
            False ->
              Error(InvalidXml(
                "Mismatched closing tag: expected </"
                  <> frame.qualified
                  <> "> but found </"
                  <> name
                  <> ">",
                pos,
              ))
            True -> {
              use #(stack, root) <- result.try(attach(frame, parent, root, pos))
              parse_loop(rest, after_space + 1, stack, root, whitespace)
            }
          }
      }
    _ ->
      Error(InvalidXml(
        "Expected '>' to finish the closing tag </" <> name,
        pos,
      ))
  }
}

fn handle_text(
  input: List(String),
  pos: Int,
  stack: List(Frame),
  root: Option(Element),
  whitespace: Whitespace,
) -> Result(Element, Error) {
  let #(run, rest) = take_text(input)
  let after_run = pos + list.length(run)
  use unescaped <- result.try(unescape(run, pos))
  handle_text_content(unescaped, pos, rest, after_run, stack, root, whitespace)
}

fn handle_cdata(
  input: List(String),
  pos: Int,
  stack: List(Frame),
  root: Option(Element),
  whitespace: Whitespace,
) -> Result(Element, Error) {
  // `pos` is the "<" of "<![CDATA[", which is 9 graphemes long. CDATA content
  // is character data without entity interpretation.
  case scan_for(input, ["]", "]", ">"]) {
    Error(Nil) -> Error(InvalidXml("Unterminated CDATA section", pos))
    Ok(#(content, rest)) ->
      handle_text_content(
        content,
        pos + 9,
        rest,
        pos + 9 + list.length(content) + 3,
        stack,
        root,
        whitespace,
      )
  }
}

fn handle_text_content(
  content: List(String),
  content_pos: Int,
  rest: List(String),
  next_pos: Int,
  stack: List(Frame),
  root: Option(Element),
  whitespace: Whitespace,
) -> Result(Element, Error) {
  case stack {
    [] ->
      // Character data outside the root element is only ever whitespace: the
      // newline after the XML declaration and such.
      case only_space(content) {
        True -> parse_loop(rest, next_pos, stack, root, whitespace)
        False ->
          Error(InvalidXml("Text outside of the root element", content_pos))
      }
    [frame, ..frames] ->
      case process_text(whitespace, content) {
        None -> parse_loop(rest, next_pos, stack, root, whitespace)
        Some(value) ->
          parse_loop(
            rest,
            next_pos,
            [
              Frame(..frame, children: [Text(value), ..frame.children]),
              ..frames
            ],
            root,
            whitespace,
          )
      }
  }
}

fn handle_comment(
  input: List(String),
  pos: Int,
  stack: List(Frame),
  root: Option(Element),
  whitespace: Whitespace,
) -> Result(Element, Error) {
  // pos is the "<" of "<!--", four graphemes.
  case scan_for(input, ["-", "-", ">"]) {
    Error(Nil) -> Error(InvalidXml("Unterminated comment", pos))
    Ok(#(content, rest)) -> {
      let next_pos = pos + 4 + list.length(content) + 3
      case stack {
        // A comment before or after the root element is dropped.
        [] -> parse_loop(rest, next_pos, stack, root, whitespace)
        [frame, ..frames] ->
          parse_loop(
            rest,
            next_pos,
            [
              Frame(..frame, children: [Comment(string.concat(content)), ..frame.children]),
              ..frames
            ],
            root,
            whitespace,
          )
      }
    }
  }
}

fn handle_pi(
  input: List(String),
  pos: Int,
  stack: List(Frame),
  root: Option(Element),
  whitespace: Whitespace,
) -> Result(Element, Error) {
  // pos is the "<" of "<?", including the XML declaration. Processing
  // instructions are not kept.
  case scan_for(input, ["?", ">"]) {
    Error(Nil) -> Error(InvalidXml("Unterminated processing instruction", pos))
    Ok(#(content, rest)) ->
      parse_loop(rest, pos + 2 + list.length(content) + 2, stack, root, whitespace)
  }
}

fn handle_declaration(
  input: List(String),
  pos: Int,
  stack: List(Frame),
  root: Option(Element),
  whitespace: Whitespace,
) -> Result(Element, Error) {
  // pos is the "<" of "<!", which is a doctype or another declaration.
  // Bracket depth keeps the internal subset's ">" from ending it early.
  case skip_declaration(input, 0, pos + 2) {
    Error(Nil) -> Error(InvalidXml("Unterminated declaration", pos))
    Ok(#(rest, next_pos)) -> parse_loop(rest, next_pos, stack, root, whitespace)
  }
}

// Tag and attribute scanning

fn take_name(input: List(String), pos: Int) -> #(String, List(String), Int) {
  do_take_name(input, pos, [])
}

fn do_take_name(
  input: List(String),
  pos: Int,
  acc: List(String),
) -> #(String, List(String), Int) {
  case input {
    [] -> #(string.concat(list.reverse(acc)), [], pos + list.length(acc))
    [grapheme, ..rest] ->
      case is_name_stop(grapheme) {
        True -> #(
          string.concat(list.reverse(acc)),
          input,
          pos + list.length(acc),
        )
        False -> do_take_name(rest, pos, [grapheme, ..acc])
      }
  }
}

fn is_name_stop(grapheme: String) -> Bool {
  grapheme == " "
  || grapheme == "\t"
  || grapheme == "\r"
  || grapheme == "\n"
  || grapheme == ">"
  || grapheme == "/"
  || grapheme == "="
  || grapheme == "\""
  || grapheme == "'"
  || grapheme == "<"
}

fn skip_space(input: List(String), pos: Int) -> #(List(String), Int) {
  case input {
    [grapheme, ..rest] ->
      case is_space(grapheme) {
        True -> skip_space(rest, pos + 1)
        False -> #(input, pos)
      }
    [] -> #([], pos)
  }
}

fn is_space(grapheme: String) -> Bool {
  grapheme == " " || grapheme == "\t" || grapheme == "\r" || grapheme == "\n"
}

fn take_text(input: List(String)) -> #(List(String), List(String)) {
  do_take_text(input, [])
}

fn do_take_text(input: List(String), acc: List(String)) -> #(List(String), List(String)) {
  case input {
    ["<", ..] -> #(list.reverse(acc), input)
    [] -> #(list.reverse(acc), [])
    [grapheme, ..rest] -> do_take_text(rest, [grapheme, ..acc])
  }
}

fn parse_attributes(
  input: List(String),
  pos: Int,
) -> Result(#(List(#(String, String)), List(String), Int, Bool), Error) {
  let #(input, pos) = skip_space(input, pos)
  case input {
    [] -> Error(InvalidXml("Unexpected end of input inside a tag", pos))
    [">", ..rest] -> Ok(#([], rest, pos + 1, False))
    ["/", ..rest] ->
      case rest {
        [">", ..rest] -> Ok(#([], rest, pos + 2, True))
        _ -> Error(InvalidXml("Expected '>' after '/' in a tag", pos))
      }
    _ -> {
      let #(name, rest, after_name) = take_name(input, pos)
      case name == "" {
        True -> Error(InvalidXml("Expected an attribute name", pos))
        False -> {
          let #(rest, after_space) = skip_space(rest, after_name)
          case rest {
            ["=", ..rest] -> {
              let #(rest, after_equals) = skip_space(rest, after_space + 1)
              use #(value, rest, after_value) <- result.try(
                take_attr_value(rest, after_equals, pos),
              )
              use #(attrs, rest, final_pos, self_closing) <- result.try(
                parse_attributes(rest, after_value),
              )
              Ok(#([#(name, value), ..attrs], rest, final_pos, self_closing))
            }
            _ ->
              Error(InvalidXml(
                "Expected '=' after attribute '" <> name <> "'",
                pos,
              ))
          }
        }
      }
    }
  }
}

fn take_attr_value(
  input: List(String),
  pos: Int,
  err_pos: Int,
) -> Result(#(String, List(String), Int), Error) {
  case input {
    [] -> Error(InvalidXml("Unexpected end of input in an attribute value", err_pos))
    [quote, ..rest] ->
      case quote {
        "\"" -> take_quoted(rest, quote, pos, err_pos, [])
        "'" -> take_quoted(rest, quote, pos, err_pos, [])
        _ ->
          Error(InvalidXml("Attribute values must be quoted", err_pos))
      }
  }
}

fn take_quoted(
  input: List(String),
  quote: String,
  pos: Int,
  err_pos: Int,
  acc: List(String),
) -> Result(#(String, List(String), Int), Error) {
  case input {
    [] -> Error(InvalidXml("Unterminated attribute value", err_pos))
    [grapheme, ..rest] ->
      case grapheme == quote {
        True -> {
          use unescaped <- result.try(unescape(list.reverse(acc), err_pos))
          Ok(#(string.concat(unescaped), rest, pos + 1))
        }
        False -> take_quoted(rest, quote, pos + 1, err_pos, [grapheme, ..acc])
      }
  }
}

// Tree construction

fn root_scope() -> List(#(String, Option(String))) {
  [#("xml", Some("http://www.w3.org/XML/1998/namespace"))]
}

fn build_frame(
  qualified: String,
  raw_attrs: List(#(String, String)),
  parent_scope: List(#(String, Option(String))),
) -> Frame {
  // Namespace declarations apply to the whole element regardless of where
  // they appear among the attributes, so they are collected first and layered
  // over the parent scope: the nearest declaration wins.
  let declarations =
    list.filter_map(raw_attrs, xmlns_declaration)
  let scope = list.append(declarations, parent_scope)
  let #(prefix, local) = split_qname(qualified)
  let attributes =
    list.map(raw_attrs, fn(raw) {
      let #(qname, value) = raw
      let #(attr_prefix, attr_name) = split_qname(qname)
      Attribute(
        prefix: attr_prefix,
        namespace: attribute_namespace(scope, attr_prefix),
        name: attr_name,
        value: value,
      )
    })
  Frame(
    qualified: qualified,
    prefix: prefix,
    namespace: resolve_element_namespace(scope, prefix),
    tag: local,
    scope: scope,
    attributes: attributes,
    children: [],
  )
}

fn attach(
  frame: Frame,
  stack: List(Frame),
  root: Option(Element),
  pos: Int,
) -> Result(#(List(Frame), Option(Element)), Error) {
  let element =
    Element(
      prefix: frame.prefix,
      namespace: frame.namespace,
      tag: frame.tag,
      attributes: frame.attributes,
      children: list.reverse(frame.children),
    )
  case stack {
    [] ->
      case root {
        None -> Ok(#([], Some(element)))
        Some(_) ->
          Error(InvalidXml("Document has more than one root element", pos))
      }
    [parent, ..rest] ->
      Ok(#(
        [
          Frame(..parent, children: [Elem(element), ..parent.children]),
          ..rest
        ],
        root,
      ))
  }
}

fn split_qname(name: String) -> #(Option(String), String) {
  case string.split_once(name, ":") {
    Ok(#(prefix, local)) -> #(Some(prefix), local)
    Error(Nil) -> #(None, name)
  }
}

fn xmlns_declaration(
  raw: #(String, String),
) -> Result(#(String, Option(String)), Nil) {
  let #(name, value) = raw
  // An empty namespace name undeclares the prefix (or the default one).
  let uri = case value {
    "" -> None
    _ -> Some(value)
  }
  case name {
    "xmlns" -> Ok(#("", uri))
    _ ->
      case string.split_once(name, ":") {
        Ok(#("xmlns", prefix)) -> Ok(#(prefix, uri))
        _ -> Error(Nil)
      }
  }
}

fn resolve(
  scope: List(#(String, Option(String))),
  prefix: String,
) -> Option(String) {
  case list.key_find(scope, prefix) {
    Ok(uri) -> uri
    Error(Nil) -> None
  }
}

// An unprefixed element takes the default namespace, "" being the key the
// `xmlns` declaration binds.
fn resolve_element_namespace(
  scope: List(#(String, Option(String))),
  prefix: Option(String),
) -> Option(String) {
  case prefix {
    None -> resolve(scope, "")
    Some(prefix) -> resolve(scope, prefix)
  }
}

// Attributes without a prefix are in no namespace even when a default
// namespace is in effect, per the namespaces spec.
fn attribute_namespace(
  scope: List(#(String, Option(String))),
  prefix: Option(String),
) -> Option(String) {
  case prefix {
    None -> None
    Some(prefix) -> resolve(scope, prefix)
  }
}

// Character references

fn unescape(input: List(String), pos: Int) -> Result(List(String), Error) {
  do_unescape(input, pos, [])
}

fn do_unescape(
  input: List(String),
  pos: Int,
  acc: List(String),
) -> Result(List(String), Error) {
  case input {
    [] -> Ok(list.reverse(acc))
    ["&", ..rest] ->
      case take_reference(rest, [], 0) {
        Error(Nil) -> Error(InvalidXml("Unterminated character reference", pos))
        Ok(#(reference, rest)) ->
          case reference_to_string(reference) {
            Ok(value) ->
              do_unescape(
                rest,
                pos,
                list.fold(string.to_graphemes(value), acc, fn(acc, grapheme) {
                  [grapheme, ..acc]
                }),
              )
            Error(Nil) ->
              Error(InvalidXml(
                "Unknown entity or character reference: &" <> reference <> ";",
                pos,
              ))
          }
      }
    [grapheme, ..rest] -> do_unescape(rest, pos + 1, [grapheme, ..acc])
  }
}

// References are short ("&#x10FFFF;" at most), so a cap turns a bare "&"
// followed by pages of text into an error instead of a full scan.
fn take_reference(
  input: List(String),
  acc: List(String),
  taken: Int,
) -> Result(#(String, List(String)), Nil) {
  case input, taken {
    _, 24 -> Error(Nil)
    [], _ -> Error(Nil)
    [";", ..rest], _ -> Ok(#(string.concat(list.reverse(acc)), rest))
    [grapheme, ..rest], _ ->
      take_reference(rest, [grapheme, ..acc], taken + 1)
  }
}

fn reference_to_string(reference: String) -> Result(String, Nil) {
  case reference {
    "lt" -> Ok("<")
    "gt" -> Ok(">")
    "amp" -> Ok("&")
    "quot" -> Ok("\"")
    "apos" -> Ok("'")
    _ ->
      case string.starts_with(reference, "#") {
        False -> Error(Nil)
        True -> {
          let digits = string.drop_start(reference, 1)
          let parsed = case string.starts_with(digits, "x") || string.starts_with(digits, "X") {
            True -> int.base_parse(string.drop_start(digits, 1), 16)
            False -> int.parse(digits)
          }
          case parsed {
            Ok(codepoint) ->
              case string.utf_codepoint(codepoint) {
                Ok(cp) -> Ok(string.from_utf_codepoints([cp]))
                Error(Nil) -> Error(Nil)
              }
            Error(Nil) -> Error(Nil)
          }
        }
      }
  }
}

// Whitespace modes

fn process_text(whitespace: Whitespace, run: List(String)) -> Option(String) {
  case run {
    [] -> None
    _ ->
      case whitespace {
        KeepWhitespace -> Some(string.concat(run))
        NoWhitespaceOnly ->
          case only_space(run) {
            True -> None
            False -> Some(string.concat(run))
          }
        TrimWhitespace ->
          case trim_space(run) {
            [] -> None
            trimmed -> Some(string.concat(trimmed))
          }
      }
  }
}

fn only_space(run: List(String)) -> Bool {
  list.all(run, is_space)
}

fn trim_space(run: List(String)) -> List(String) {
  run
  |> list.drop_while(is_space)
  |> list.reverse
  |> list.drop_while(is_space)
  |> list.reverse
}

// Generic scanners

// Scans for a multi-grapheme terminator, returning what came before it and
// what comes after it. Error when the terminator never appears.
fn scan_for(
  input: List(String),
  terminator: List(String),
) -> Result(#(List(String), List(String)), Nil) {
  do_scan_for(input, terminator, [])
}

fn do_scan_for(
  input: List(String),
  terminator: List(String),
  acc: List(String),
) -> Result(#(List(String), List(String)), Nil) {
  case starts_with(input, terminator) {
    True -> Ok(#(list.reverse(acc), list.drop(input, list.length(terminator))))
    False ->
      case input {
        [] -> Error(Nil)
        [grapheme, ..rest] -> do_scan_for(rest, terminator, [grapheme, ..acc])
      }
  }
}

fn starts_with(input: List(String), prefix: List(String)) -> Bool {
  case input, prefix {
    _, [] -> True
    [], _ -> False
    [i, ..irest], [p, ..prest] -> i == p && starts_with(irest, prest)
  }
}

// Skips a `<!...>` declaration, counting bracket depth so the internal subset
// of a doctype does not end it early. Returns the rest and new position.
fn skip_declaration(
  input: List(String),
  depth: Int,
  pos: Int,
) -> Result(#(List(String), Int), Nil) {
  case input {
    [] -> Error(Nil)
    [grapheme, ..rest] ->
      case grapheme, depth {
        "[", _ -> skip_declaration(rest, depth + 1, pos + 1)
        "]", 0 -> skip_declaration(rest, 0, pos + 1)
        "]", _ -> skip_declaration(rest, depth - 1, pos + 1)
        ">", 0 -> Ok(#(rest, pos + 1))
        _, _ -> skip_declaration(rest, depth, pos + 1)
      }
  }
}
