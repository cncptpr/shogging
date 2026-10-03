//// Splits incoming requests between the WebSocket API and the static bundle
//// of the frontend.

import gleam/erlang/process.{type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import mist
import hub
import ws
import static

pub fn router(
  request: Request(mist.Connection),
  hub_subject: Subject(hub.Msg),
) -> Response(mist.ResponseData) {
  case request.path_segments(request) {
    ["ws"] -> ws.handler(request, hub_subject)
    segments -> static.serve(segments)
  }
}
