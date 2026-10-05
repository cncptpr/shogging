//// Decoders for `shogxml.Element` values, modelled on `gleam/dynamic/decode`.
////
//// A decoder runs over a single element and extracts a typed value out of
//// it. Compose them with `field`/`optional_field` (matching child elements by
//// local name), `at` (for deep paths), `children` (a list of same-named
//// children, always a list whether the document had one or many), and
//// `attribute`. `element` hands you the raw element for anything else.
////
//// ```gleam
//// fn item_decoder() -> decode.Decoder(String) {
////   use href <- decode.field("href", decode.text)
////   decode.success(href)
//// }
////
//// fn items_decoder() -> decode.Decoder(List(String)) {
////   use items <- decode.children("response", item_decoder())
////   decode.success(items)
//// }
////
//// let assert Ok(items) = decode.run(root, items_decoder())
//// ```
////
//// `field` matches any namespace; use `field_ns` when the namespace
//// URI matters. Errors carry the stdlib `DecodeError` type with a path of
//// tag names, so they read like the dynamic decoders'.

import gleam/dynamic/decode.{type DecodeError, DecodeError}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import shogxml.{type Element, Element, UnableToDecode}

/// A decoder that extracts a value of type `t` from an element.
pub opaque type Decoder(t) {
  Decoder(function: fn(Element) -> #(t, List(DecodeError)))
}

/// Runs a decoder against an element.
///
/// Returns `UnableToDecode` with all accumulated errors when anything fails.
pub fn run(element: Element, decoder: Decoder(t)) -> Result(t, shogxml.Error) {
  let #(value, errors) = decoder.function(element)
  case errors {
    [] -> Ok(value)
    [_, ..] -> Error(UnableToDecode(errors))
  }
}

/// A decoder that always succeeds with the given value.
pub fn success(data: t) -> Decoder(t) {
  Decoder(fn(_) { #(data, []) })
}

/// A decoder that always fails, carrying a placeholder value so the rest of
/// the pipeline can keep running and collect more errors.
pub fn failure(placeholder: t, expected name: String) -> Decoder(t) {
  Decoder(fn(_) { #(placeholder, [DecodeError(name, "Element", [])]) })
}

/// The element itself, for decoders that need to look at the tree in ways
/// the other functions here do not cover. Combine with `map`.
pub const element: Decoder(Element) = Decoder(decode_element)

fn decode_element(element: Element) -> #(Element, List(DecodeError)) {
  #(element, [])
}

/// Decodes a child element with the given local name, in any namespace.
///
/// Intended for `use` syntax:
///
/// ```gleam
/// use href <- decode.field("href", decode.text)
/// ```
pub fn field(
  name: String,
  inner: Decoder(t),
  next: fn(t) -> Decoder(final),
) -> Decoder(final) {
  Decoder(fn(element) {
    let #(value, errors) =
      resolve_child(shogxml.child(element, name), inner, [
        name,
      ])
    let #(out, rest) = next(value).function(element)
    #(out, list.append(errors, rest))
  })
}

/// Like `field`, but returns `default` when there is no such child.
pub fn optional_field(
  name: String,
  default: t,
  inner: Decoder(t),
  next: fn(t) -> Decoder(final),
) -> Decoder(final) {
  Decoder(fn(element) {
    let #(value, errors) = case shogxml.child(element, name) {
      Ok(child) -> {
        let #(value, errors) = inner.function(child)
        #(value, push_path(errors, [name]))
      }
      Error(Nil) -> #(default, [])
    }
    let #(out, rest) = next(value).function(element)
    #(out, list.append(errors, rest))
  })
}

/// Like `field`, but the child must also be in the given namespace URI.
pub fn field_ns(
  namespace: String,
  name: String,
  inner: Decoder(t),
  next: fn(t) -> Decoder(final),
) -> Decoder(final) {
  Decoder(fn(element) {
    let #(value, errors) =
      resolve_child(child_ns(element, namespace, name), inner, [name])
    let #(out, rest) = next(value).function(element)
    #(out, list.append(errors, rest))
  })
}

/// Like `optional_field`, but the child must also be in the given namespace
/// URI.
pub fn optional_field_ns(
  namespace: String,
  name: String,
  default: t,
  inner: Decoder(t),
  next: fn(t) -> Decoder(final),
) -> Decoder(final) {
  Decoder(fn(element) {
    let #(value, errors) = case child_ns(element, namespace, name) {
      Ok(child) -> {
        let #(value, errors) = inner.function(child)
        #(value, push_path(errors, [name]))
      }
      Error(Nil) -> #(default, [])
    }
    let #(out, rest) = next(value).function(element)
    #(out, list.append(errors, rest))
  })
}

/// Decodes a value nested under a path of child names, e.g.
/// `decode.at(["propstat", "prop", "href"], decode.text)`.
pub fn at(path: List(String), inner: Decoder(t)) -> Decoder(t) {
  Decoder(fn(element) { resolve_path(path, element, inner, []) })
}

/// Like `at`, but returns `default` when the path does not exist.
pub fn optional_at(
  path: List(String),
  default: t,
  inner: Decoder(t),
) -> Decoder(t) {
  Decoder(fn(element) {
    case descend(path, element) {
      Ok(element) -> {
        let #(value, errors) = inner.function(element)
        #(value, push_path(errors, path))
      }
      Error(Nil) -> #(default, [])
    }
  })
}

/// Decodes every child element with the given local name, in document order.
/// Always succeeds with a list, empty when there are no such children.
pub fn children(
  name: String,
  inner: Decoder(t),
  next: fn(List(t)) -> Decoder(final),
) -> Decoder(final) {
  Decoder(fn(element) {
    let #(values, errors) =
      decode_each(shogxml.children_named(element, name), inner, name, 0, [])
    let #(out, rest) = next(values).function(element)
    #(out, list.append(errors, rest))
  })
}

/// Decodes every element child, in document order.
pub fn all(
  inner: Decoder(t),
  next: fn(List(t)) -> Decoder(final),
) -> Decoder(final) {
  Decoder(fn(element) {
    let #(values, errors) =
      decode_each(shogxml.children(element), inner, "*", 0, [])
    let #(out, rest) = next(values).function(element)
    #(out, list.append(errors, rest))
  })
}

/// Decodes the value of an attribute with the given local name. The
/// continuation receives the raw string; parse it further in the body if
/// needed.
///
/// ```gleam
/// use name <- decode.attribute("name")
/// decode.success(name)
/// ```
///
/// Or fully applied, as the inner decoder of a `field`:
///
/// ```gleam
/// decode.attribute("name", decode.success)
/// ```
pub fn attribute(
  name: String,
  next: fn(String) -> Decoder(final),
) -> Decoder(final) {
  Decoder(fn(element) {
    let #(value, errors) = case shogxml.attr(element, name) {
      Some(value) -> #(value, [])
      None -> #("", [DecodeError("Attribute", "Nothing", [name])])
    }
    let #(out, rest) = next(value).function(element)
    #(out, list.append(errors, rest))
  })
}

/// Like `attribute`, but returns `default` when the attribute is absent.
pub fn optional_attribute(
  name: String,
  default: String,
  next: fn(String) -> Decoder(final),
) -> Decoder(final) {
  Decoder(fn(element) {
    let value = case shogxml.attr(element, name) {
      Some(value) -> value
      None -> default
    }
    let #(out, rest) = next(value).function(element)
    #(out, rest)
  })
}

/// Decodes the concatenated character data of the element.
///
/// Fails when the element has no character data at all, including when it is
/// empty; empty elements decode to a failure with an empty placeholder.
pub const text: Decoder(String) = Decoder(decode_text)

fn decode_text(element: Element) -> #(String, List(DecodeError)) {
  case shogxml.text(element) {
    "" -> #("", [DecodeError("Text", "Nothing", [])])
    value -> #(value, [])
  }
}

/// Transforms the value inside a decoder.
pub fn map(decoder: Decoder(a), transformer: fn(a) -> b) -> Decoder(b) {
  Decoder(fn(element) {
    let #(value, errors) = decoder.function(element)
    #(transformer(value), errors)
  })
}

/// Tries several decoders, using the first that succeeds.
pub fn one_of(
  first: Decoder(a),
  or alternatives: List(Decoder(a)),
) -> Decoder(a) {
  Decoder(fn(element) {
    let #(value, errors) = first.function(element)
    case errors {
      [] -> #(value, [])
      [_, ..] ->
        case first_success(alternatives, element) {
          Ok(result) -> result
          Error(Nil) -> #(value, errors)
        }
    }
  })
}

/// Decodes to `None` when the inner decoder fails.
pub fn optional(inner: Decoder(a)) -> Decoder(Option(a)) {
  Decoder(fn(element) {
    let #(value, errors) = inner.function(element)
    case errors {
      [] -> #(Some(value), [])
      [_, ..] -> #(None, [])
    }
  })
}

// Internals

fn first_success(
  decoders: List(Decoder(a)),
  element: Element,
) -> Result(#(a, List(DecodeError)), Nil) {
  case decoders {
    [] -> Error(Nil)
    [decoder, ..rest] -> {
      let #(value, errors) = decoder.function(element)
      case errors {
        [] -> Ok(#(value, []))
        [_, ..] -> first_success(rest, element)
      }
    }
  }
}

// A missing child still needs a value to pass to `next`, so the inner
// decoder runs against an empty element to borrow its placeholder, exactly
// as the dynamic decoders borrow one from a wrong-typed Dynamic.
fn resolve_child(
  child: Result(Element, Nil),
  inner: Decoder(t),
  path: List(String),
) -> #(t, List(DecodeError)) {
  case child {
    Ok(child) -> {
      let #(value, errors) = inner.function(child)
      #(value, push_path(errors, path))
    }
    Error(Nil) -> {
      let #(placeholder, _) = inner.function(empty_element())
      #(placeholder, [DecodeError("Field", "Nothing", path)])
    }
  }
}

fn resolve_path(
  path: List(String),
  element: Element,
  inner: Decoder(t),
  visited: List(String),
) -> #(t, List(DecodeError)) {
  case path {
    [] -> {
      let #(value, errors) = inner.function(element)
      #(value, push_path(errors, visited))
    }
    [name, ..rest] ->
      case shogxml.child(element, name) {
        Ok(child) ->
          resolve_path(rest, child, inner, list.append(visited, [name]))
        Error(Nil) -> {
          let #(placeholder, _) = inner.function(empty_element())
          #(placeholder, [
            DecodeError("Field", "Nothing", list.append(visited, [name])),
          ])
        }
      }
  }
}

fn descend(path: List(String), element: Element) -> Result(Element, Nil) {
  case path {
    [] -> Ok(element)
    [name, ..rest] ->
      case shogxml.child(element, name) {
        Ok(child) -> descend(rest, child)
        Error(Nil) -> Error(Nil)
      }
  }
}

fn child_ns(
  element: Element,
  namespace: String,
  name: String,
) -> Result(Element, Nil) {
  shogxml.children_named(element, name)
  |> list.find(fn(child) { child.namespace == Some(namespace) })
}

fn decode_each(
  elements: List(Element),
  inner: Decoder(t),
  name: String,
  index: Int,
  acc: List(t),
) -> #(List(t), List(DecodeError)) {
  case elements {
    [] -> #(list.reverse(acc), [])
    [element, ..rest] -> {
      let #(value, errors) = inner.function(element)
      let errors = push_path(errors, [name, int.to_string(index)])
      let #(values, more) =
        decode_each(rest, inner, name, index + 1, [value, ..acc])
      #(values, list.append(errors, more))
    }
  }
}

fn push_path(
  errors: List(DecodeError),
  path: List(String),
) -> List(DecodeError) {
  list.map(errors, fn(error) {
    DecodeError(..error, path: list.append(path, error.path))
  })
}

fn empty_element() -> Element {
  Element(prefix: None, namespace: None, tag: "", attributes: [], children: [])
}
