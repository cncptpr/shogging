//// The frontend's state and the messages that can change it.
//////
//// This module is a leaf: both the update loop and the view functions import
//// it, so neither of them has to know about the other.

import gleam/list
import gleam/option.{type Option}
import lustre_websocket.{type WebSocket, type WebSocketEvent}
import shared/api.{type Todo}

pub type Connection {
  Connecting
  Connected
  Reconnecting
}

pub type Dialog {
  NoDialog
  AddDialog
  RenameDialog(id: String)
}

pub type Model {
  Model(
    todos: List(Todo),
    connection: Connection,
    dialog: Dialog,
    draft: String,
    error: Option(String),
    socket: Option(WebSocket),
    queue: List(String),
    retries: Int,
  )
}

/// Named after what happened, not after what should be done about it.
pub type Msg {
  WsEvent(WebSocketEvent)
  /// The reconnect timer fired: try to open the socket again.
  Reconnect
  UserClickedAdd
  UserClickedReload
  UserClickedRename(id: String)
  UserClickedDelete(id: String)
  UserToggled(id: String, completed: Bool)
  UserTypedDraft(draft: String)
  UserSubmittedDraft
  UserDismissedDialog
  UserDismissedError
}

/// Capped so a long outage cannot grow the queue without bound; the oldest
/// entries are dropped first.
pub fn queue_push(queue: List(String), payload: String) -> List(String) {
  let queue = list.append(queue, [payload])
  case list.length(queue) > max_queue_size {
    True -> list.drop(queue, list.length(queue) - max_queue_size)
    False -> queue
  }
}

const max_queue_size = 50

/// Exponential backoff, capped at 15 seconds.
pub fn reconnect_delay(retries: Int) -> Int {
  case retries {
    0 -> 1000
    1 -> 2000
    2 -> 4000
    3 -> 8000
    _ -> 15000
  }
}
