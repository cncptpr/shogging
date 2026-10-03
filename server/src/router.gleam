//// Splits incoming requests between the WebSocket API, the page shell and the
//// static bundle of the frontend.

import gleam/erlang/process.{type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import html
import hub
import mist
import static
import ws

pub fn router(
  request: Request(mist.Connection),
  hub_subject: Subject(hub.Msg),
  page: String,
) -> Response(mist.ResponseData) {
  case request.path_segments(request) {
    // The document is rendered once at startup and served from memory, so it can
    // carry the deployment's configuration. Both spellings reach it.
    [] | ["index.html"] -> html.respond(page)

    ["ws"] -> ws.handler(request, hub_subject)

    segments -> static.serve(segments)
  }
}
