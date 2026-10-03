//// The page shell, rendered by the server instead of by the frontend build.
////
//// `gleam run -m lustre/dev build` writes the JavaScript bundle, the stylesheet
//// and the icons into priv/static; `static.gleam` hands those out by path. The
//// document itself is built here, because the one thing a static bundle cannot
//// know is this deployment's configuration: the motto is read from the
//// environment and written into the page, where the bundle reads it back before
//// its first render (see `client/src/config.gleam`).
////
//// Because the document is generated rather than read off disk, whatever is set
//// here is what every page load gets. Changing `SHOGGING_MOTTO` therefore needs
//// a restart of the server, not a rebuild of the frontend.
////
//// Note that the frontend also generates a document, used when it is served by
//// `lustre/dev` on its own port. That one carries no configuration, so the
//// frontend falls back to its own default.
//// The document the bundle mounts into. The frontend looks for this id.
//// The id of the element the configuration is written into. The frontend looks
//// it up by this exact id.

import config.{type Config}
import gleam/bytes_tree
import gleam/http/response.{type Response}
import gleam/json
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import mist

const mount_id = "app"

const config_id = "motto"

/// The configuration, as a JSON island in a `<script>` the browser never runs.
///
/// `type="application/json"` because the text is data, not code: the point is
/// that nothing here is executed. JSON then does the escaping, so a motto with
/// quotes, backslashes or newlines in it cannot break the document.
///
/// The one thing to patch up is `</`, the only sequence that ends a `<script>`
/// element. `<\/` is a valid JSON escape for the solidus, so the browser no
/// longer sees a closing tag and the parser hands back the original text.
fn config_island(config: Config) -> String {
  json.object([#("motto", json.string(config.motto))])
  |> json.to_string
  |> string.replace("</", "<\\/")
}

fn config_element(config: Config) -> Element(Nil) {
  html.script(
    [attribute.id(config_id), attribute.type_("application/json")],
    config_island(config),
  )
}

/// The shell: no rendered content of our own, just the mount point and the two
/// built assets. Keeping it minimal means it cannot drift far from what
/// `lustre/dev` produces for the same bundle.
fn document(config: Config) -> Element(Nil) {
  html.html([attribute.lang("en")], [
    html.head([], [
      html.meta([attribute.charset("utf-8")]),
      html.meta([
        attribute.name("viewport"),
        attribute.content("width=device-width, initial-scale=1"),
      ]),
      html.title([], "Shogging"),
      // In the head and before the bundle, which is a module and therefore
      // deferred, so the configuration is there by the time it looks.
      config_element(config),
      html.link([attribute.rel("stylesheet"), attribute.href("/client.css")]),
      html.script([attribute.type_("module"), attribute.src("/client.js")], ""),
    ]),
    html.body([], [html.div([attribute.id(mount_id)], [])]),
  ])
}

/// The document as a single string, ready to be cached and served.
///
/// The doctype is added by hand because `element.to_readable_string/1` starts at
/// `<html>`; `lustre/dev` does exactly the same thing for its own document, so
/// both paths produce the same shape of markup.
pub fn render(config: Config) -> String {
  "<!doctype html>\n" <> element.to_readable_string(document(config))
}

/// A `200` carrying the cached document.
pub fn respond(document: String) -> Response(mist.ResponseData) {
  response.new(200)
  |> response.prepend_header("content-type", "text/html; charset=utf-8")
  |> response.prepend_header("cache-control", "no-cache")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(document)))
}
