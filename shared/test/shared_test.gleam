import gleeunit
import shared/api.{
  type ClientMsg, type ServerMsg, ActionFailed, AddTodo, DeleteTodo, Reload,
  RenameTodo, Todo, Todos, ToggleTodo,
}

pub fn main() -> Nil {
  gleeunit.main()
}

// gleeunit test functions end in `_test`

fn client_round_trips(msg: ClientMsg) -> Bool {
  case msg |> api.client_msg_to_string |> api.parse_client_msg {
    Ok(decoded) -> decoded == msg
    Error(_) -> False
  }
}

fn server_round_trips(msg: ServerMsg) -> Bool {
  case msg |> api.server_msg_to_string |> api.parse_server_msg {
    Ok(decoded) -> decoded == msg
    Error(_) -> False
  }
}

pub fn client_messages_round_trip_test() {
  assert client_round_trips(Reload)
  assert client_round_trips(AddTodo(summary: "Buy milk"))
  assert client_round_trips(ToggleTodo(id: "uid-1", completed: True))
  assert client_round_trips(RenameTodo(id: "uid-1", summary: "Buy oat milk"))
  assert client_round_trips(DeleteTodo(id: "uid-1"))
}

pub fn client_messages_survive_tricky_strings_test() {
  assert client_round_trips(AddTodo(summary: "quote \" backslash \\ newline\n"))
  assert client_round_trips(RenameTodo(id: "üñï-1", summary: "😀 emoji"))
}

pub fn server_messages_round_trip_test() {
  assert server_round_trips(ActionFailed(message: "CalDAV said no"))
  assert server_round_trips(Todos([]))
  assert server_round_trips(Todos([
    Todo(id: "uid-1", summary: "Buy milk", completed: False),
    Todo(id: "uid-2", summary: "Ship the frontend", completed: True),
  ]))
}

pub fn unknown_client_events_are_rejected_test() {
  assert api.parse_client_msg("{\"event\":\"drop_database\"}") |> is_error
}

pub fn unknown_server_events_are_rejected_test() {
  assert api.parse_server_msg("{\"event\":\"ping\"}") |> is_error
}

pub fn malformed_json_is_rejected_test() {
  assert api.parse_client_msg("not json at all") |> is_error
}

fn is_error(result: Result(a, b)) -> Bool {
  case result {
    Ok(_) -> False
    Error(_) -> True
  }
}
