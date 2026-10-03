//// The messages shogging's frontend and backend send each other over the
//// WebSocket, together with their JSON codecs.
////
//// Both sides import this module, so the two ends of the wire can never drift
//// apart. Everything CalDAV specific stays on the server: the browser only
//// ever sees `Todo`s.

import gleam/dynamic/decode.{type Decoder}
import gleam/json

/// The server translates these to and from `shogg/task.Task`s.
pub type Todo {
  Todo(id: String, summary: String, completed: Bool)
}

pub type ClientMsg {
  Reload
  AddTodo(summary: String)
  ToggleTodo(id: String, completed: Bool)
  RenameTodo(id: String, summary: String)
  DeleteTodo(id: String)
}

pub type ServerMsg {
  /// Sent when a client connects and after every change the server knows of.
  Todos(List(Todo))
  /// Sent to the client that made the request, alongside a fresh `Todos` so
  /// optimistic updates get rolled back.
  ActionFailed(message: String)
}

pub fn encode_client_msg(msg: ClientMsg) -> json.Json {
  case msg {
    Reload -> json.object([#("event", json.string("reload"))])
    AddTodo(summary) ->
      json.object([
        #("event", json.string("add_todo")),
        #("summary", json.string(summary)),
      ])
    ToggleTodo(id, completed) ->
      json.object([
        #("event", json.string("toggle_todo")),
        #("id", json.string(id)),
        #("completed", json.bool(completed)),
      ])
    RenameTodo(id, summary) ->
      json.object([
        #("event", json.string("rename_todo")),
        #("id", json.string(id)),
        #("summary", json.string(summary)),
      ])
    DeleteTodo(id) ->
      json.object([
        #("event", json.string("delete_todo")),
        #("id", json.string(id)),
      ])
  }
}

pub fn encode_server_msg(msg: ServerMsg) -> json.Json {
  case msg {
    Todos(todos) ->
      json.object([
        #("event", json.string("todos")),
        #("todos", json.array(todos, todo_to_json)),
      ])
    ActionFailed(message) ->
      json.object([
        #("event", json.string("action_failed")),
        #("message", json.string(message)),
      ])
  }
}

pub fn todo_to_json(item: Todo) -> json.Json {
  json.object([
    #("id", json.string(item.id)),
    #("summary", json.string(item.summary)),
    #("completed", json.bool(item.completed)),
  ])
}

pub fn client_msg_to_string(msg: ClientMsg) -> String {
  encode_client_msg(msg) |> json.to_string
}

pub fn server_msg_to_string(msg: ServerMsg) -> String {
  encode_server_msg(msg) |> json.to_string
}

fn todo_decoder() -> Decoder(Todo) {
  use id <- decode.field("id", decode.string)
  use summary <- decode.field("summary", decode.string)
  use completed <- decode.field("completed", decode.bool)
  decode.success(Todo(id:, summary:, completed:))
}

fn add_todo_decoder() -> Decoder(ClientMsg) {
  use summary <- decode.field("summary", decode.string)
  decode.success(AddTodo(summary:))
}

fn toggle_todo_decoder() -> Decoder(ClientMsg) {
  use id <- decode.field("id", decode.string)
  use completed <- decode.field("completed", decode.bool)
  decode.success(ToggleTodo(id:, completed:))
}

fn rename_todo_decoder() -> Decoder(ClientMsg) {
  use id <- decode.field("id", decode.string)
  use summary <- decode.field("summary", decode.string)
  decode.success(RenameTodo(id:, summary:))
}

fn delete_todo_decoder() -> Decoder(ClientMsg) {
  use id <- decode.field("id", decode.string)
  decode.success(DeleteTodo(id:))
}

/// Unknown events fail to decode, so they can be logged and dropped rather
/// than silently misinterpreted.
pub fn client_msg_decoder() -> Decoder(ClientMsg) {
  use event <- decode.field("event", decode.string)
  case event {
    "reload" -> decode.success(Reload)
    "add_todo" -> add_todo_decoder()
    "toggle_todo" -> toggle_todo_decoder()
    "rename_todo" -> rename_todo_decoder()
    "delete_todo" -> delete_todo_decoder()
    _ -> decode.failure(Reload, expected: "client event")
  }
}

fn todos_decoder() -> Decoder(ServerMsg) {
  use todos <- decode.field("todos", decode.list(todo_decoder()))
  decode.success(Todos(todos))
}

fn action_failed_decoder() -> Decoder(ServerMsg) {
  use message <- decode.field("message", decode.string)
  decode.success(ActionFailed(message:))
}

pub fn server_msg_decoder() -> Decoder(ServerMsg) {
  use event <- decode.field("event", decode.string)
  case event {
    "todos" -> todos_decoder()
    "action_failed" -> action_failed_decoder()
    _ -> decode.failure(ActionFailed(message: ""), expected: "server event")
  }
}

pub fn parse_client_msg(raw: String) -> Result(ClientMsg, json.DecodeError) {
  json.parse(raw, client_msg_decoder())
}

pub fn parse_server_msg(raw: String) -> Result(ServerMsg, json.DecodeError) {
  json.parse(raw, server_msg_decoder())
}
