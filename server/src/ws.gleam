//// The WebSocket endpoint: one process per browser tab, bridging JSON frames
//// between the hub and the client.

import gleam/erlang/process.{type Selector, type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/io
import gleam/option.{type Option, Some}
import mist
import hub
import shared/api

/// Upgrade `request` to a WebSocket. Every tab gets its own socket and its own
/// subscription to the hub, so messages are never shared between tabs by the
/// transport itself: the hub's broadcasts are.
pub fn handler(
  request: Request(mist.Connection),
  hub_subject: Subject(hub.Msg),
) -> Response(mist.ResponseData) {
  mist.websocket(
    request:,
    on_init: init(_, hub_subject),
    handler: loop,
    on_close: close,
  )
}

type State {
  State(hub_subject: Subject(hub.Msg), self: Subject(api.ServerMsg))
}

type Init =
  #(State, Option(Selector(api.ServerMsg)))

fn init(_connection, hub_subject) -> Init {
  let self = process.new_subject()
  let selector =
    process.new_selector()
    |> process.select(self)

  process.send(hub_subject, hub.Subscribe(self))

  #(State(hub_subject:, self:), Some(selector))
}

fn loop(
  state: State,
  message: mist.WebsocketMessage(api.ServerMsg),
  connection: mist.WebsocketConnection,
) -> mist.Next(State, api.ServerMsg) {
  case message {
    // A message from the browser: a `ClientMsg` the hub knows what to do with.
    mist.Text(raw) -> {
      case api.parse_client_msg(raw) {
        Ok(event) ->
          process.send(state.hub_subject, hub.Event(event, state.self))
        Error(_) -> io.println("[ws] ignoring a malformed client message")
      }

      mist.continue(state)
    }

    mist.Binary(_) -> mist.continue(state)

    // A message for the browser, sent by the hub via our subject.
    mist.Custom(server_msg) -> {
      let assert Ok(_) =
        mist.send_text_frame(
          connection,
          api.server_msg_to_string(server_msg),
        )

      mist.continue(state)
    }

    mist.Closed | mist.Shutdown -> mist.stop()
  }
}

fn close(state: State) -> Nil {
  process.send(state.hub_subject, hub.Unsubscribe(state.self))
}
