//// The frontend's update loop: it keeps the model in sync with the server and
//// renders it.
//////
//// Every user action is applied optimistically to the local todos and then
//// mirrored to the server. The server always answers with a fresh `Todos`
//// broadcast, which is what keeps several browser tabs honest.
//// The whole app is a sheet of paper. Everything else only arranges things on
//// it; the colour, the grain and the doodled outlines live in `client.css`.

import config
import gleam/javascript/promise
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import lustre_websocket.{type WebSocket, type WebSocketEvent}
import model.{
  type Model, type Msg, AddDialog, Connected, Connecting, Model, NoDialog,
  Reconnect, Reconnecting, RenameDialog, UserClickedAdd, UserClickedDelete,
  UserClickedReload, UserClickedRename, UserDismissedDialog, UserDismissedError,
  UserSubmittedDraft, UserToggled, UserTypedDraft, WsEvent, queue_push,
  reconnect_delay,
}
import shared/api.{type ClientMsg, type Todo, Todo}
import ui/dialog
import ui/task_list

const page_classes = "page"

pub fn app() -> lustre.App(Nil, Model, Msg) {
  lustre.application(init, update, view)
}

fn init(_) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      todos: [],
      connection: Connecting,
      dialog: NoDialog,
      draft: "",
      error: None,
      socket: None,
      queue: [],
      retries: 0,
      motto: config.motto(),
    )

  #(model, lustre_websocket.init("/ws", WsEvent))
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    WsEvent(event) -> handle_ws_event(model, event)

    Reconnect -> #(model, lustre_websocket.init("/ws", WsEvent))

    UserClickedAdd -> #(
      Model(..model, dialog: AddDialog, draft: "", error: None),
      effect.none(),
    )

    UserClickedReload -> send(model, api.Reload)

    UserClickedRename(id) ->
      case find_todo(model.todos, id) {
        Ok(item) -> #(
          Model(..model, dialog: RenameDialog(id), draft: item.summary),
          effect.none(),
        )
        Error(Nil) -> #(model, effect.none())
      }

    UserClickedDelete(id) -> {
      let model = Model(..model, todos: remove_todo(model.todos, id))
      send(model, api.DeleteTodo(id))
    }

    UserToggled(id, completed) -> {
      let model =
        Model(
          ..model,
          todos: replace_todo(model.todos, id, fn(item) {
            Todo(..item, completed:)
          }),
        )
      send(model, api.ToggleTodo(id, completed))
    }

    UserTypedDraft(draft) -> #(Model(..model, draft:), effect.none())

    UserSubmittedDraft -> submit(model)

    UserDismissedDialog -> #(
      Model(..model, dialog: NoDialog, draft: ""),
      effect.none(),
    )

    UserDismissedError -> #(Model(..model, error: None), effect.none())
  }
}

fn handle_ws_event(
  model: Model,
  event: WebSocketEvent,
) -> #(Model, Effect(Msg)) {
  case event {
    lustre_websocket.InvalidUrl ->
      panic as "the websocket path is hardcoded and valid"

    lustre_websocket.OnOpen(socket) -> #(
      Model(
        ..model,
        socket: Some(socket),
        queue: [],
        retries: 0,
        connection: Connected,
      ),
      flush(socket, model.queue),
    )

    lustre_websocket.OnTextMessage(raw) -> handle_server_msg(model, raw)

    lustre_websocket.OnBinaryMessage(_) -> #(model, effect.none())

    lustre_websocket.OnClose(_) -> #(
      Model(
        ..model,
        socket: None,
        connection: Reconnecting,
        retries: model.retries + 1,
      ),
      schedule_reconnect(reconnect_delay(model.retries)),
    )
  }
}

fn flush(socket: WebSocket, queue: List(String)) -> Effect(Msg) {
  effect.batch(
    list.map(queue, fn(payload) { lustre_websocket.send(socket, payload) }),
  )
}

fn schedule_reconnect(delay: Int) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    promise.wait(delay)
    |> promise.tap(fn(_) { dispatch(Reconnect) })
    Nil
  })
}

fn handle_server_msg(model: Model, raw: String) -> #(Model, Effect(Msg)) {
  case api.parse_server_msg(raw) {
    Ok(api.Todos(todos)) -> #(Model(..model, todos:), effect.none())
    Ok(api.ActionFailed(message)) -> #(
      Model(..model, error: Some(message)),
      effect.none(),
    )
    Error(_) -> #(model, effect.none())
  }
}

fn send(model: Model, msg: ClientMsg) -> #(Model, Effect(Msg)) {
  let payload = api.client_msg_to_string(msg)
  case model.socket {
    Some(socket) -> #(model, lustre_websocket.send(socket, payload))
    None -> #(
      Model(..model, queue: queue_push(model.queue, payload)),
      effect.none(),
    )
  }
}

fn submit(model: Model) -> #(Model, Effect(Msg)) {
  let summary = string.trim(model.draft)

  case model.dialog, summary {
    AddDialog, "" -> #(model, effect.none())
    AddDialog, summary -> {
      let model = Model(..model, dialog: NoDialog, draft: "")
      send(model, api.AddTodo(summary))
    }
    RenameDialog(_), "" -> #(model, effect.none())
    RenameDialog(id), summary -> {
      let model =
        Model(
          ..model,
          dialog: NoDialog,
          draft: "",
          todos: replace_todo(model.todos, id, fn(item) {
            Todo(..item, summary:)
          }),
        )
      send(model, api.RenameTodo(id, summary))
    }
    NoDialog, _ -> #(model, effect.none())
  }
}

fn find_todo(todos: List(Todo), id: String) -> Result(Todo, Nil) {
  list.find(todos, fn(item) { item.id == id })
}

fn replace_todo(
  todos: List(Todo),
  id: String,
  change: fn(Todo) -> Todo,
) -> List(Todo) {
  list.map(todos, fn(item) {
    case item.id == id {
      True -> change(item)
      False -> item
    }
  })
}

fn remove_todo(todos: List(Todo), id: String) -> List(Todo) {
  list.filter(todos, fn(item) { item.id != id })
}

fn view(model: Model) -> Element(Msg) {
  html.div([class(page_classes)], [
    task_list.view(model.todos, model.connection, model.motto),
    dialog.view(model.dialog, model.draft),
    view_error(model.error),
  ])
}

fn view_error(error: Option(String)) -> Element(Msg) {
  case error {
    None -> element.none()
    Some(message) ->
      // The error is a scrap of paper stuck in the corner of the page, not a
      // toast: same paper, same pen, just tilted a little.
      html.div([class("fixed right-6 bottom-6 z-40 flex items-end gap-3")], [
        html.p([class("note max-w-72 py-4 pr-6")], [html.text(message)]),
        html.button(
          [
            class("btn"),
            attribute.type_("button"),
            event.on_click(UserDismissedError),
          ],
          [html.text("shove it")],
        ),
      ])
  }
}
