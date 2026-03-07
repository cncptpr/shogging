// IMPORTS ---------------------------------------------------------------------

import components/todo_list
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import lustre.{type App}
import lustre/element.{type Element}
import types.{type TodoItem, TodoItem}

// MAIN ------------------------------------------------------------------------

/// The only difference between this module and the counter defined in
/// 05-components/01-basic-setup is this function. The client component example
/// exposes a `register` function to register the custom element, but here we
/// expose a `component` function that constructs a Lustre application but does
/// not start it.
///
/// It's common practice to provide both functions so that your users can choose
/// where to run the component. This is known as a **universal component** because
/// it can run in both the browser and the server.
///
pub fn component() -> App(_, Model, Msg) {
  lustre.simple(init, update, view)
}

// MODEL -----------------------------------------------------------------------

pub type Model =
  dict.Dict(String, TodoItem)

fn init(_) -> Model {
  dict.new()
  |> dict.insert("1", TodoItem("1", "Todo Task", True))
  |> dict.insert("2", TodoItem("2", "Untodo Task", False))
  |> dict.insert("3", TodoItem("3", "Todo Task 2", True))
}

// UPDATE ----------------------------------------------------------------------

pub type Msg {
  UserAddedTodo(summary: String)
  UserCheckedTodo(uid: String, checked: Bool)
  UserRenamedTodo(uid: String, summary: String)
  UserDeletedTodo(uid: String)
}

fn update(model: Model, msg: Msg) -> Model {
  case msg {
    UserAddedTodo(summary:) -> {
      let uid = int.random(100 * 16) |> int.to_base16
      dict.insert(model, uid, TodoItem(uid:, summary:, checked: False))
    }

    UserCheckedTodo(uid:, checked:) -> {
      case dict.get(model, uid) {
        Ok(item) -> dict.insert(model, uid, TodoItem(..item, checked:))
        _ -> {
          io.print_error("Nonexisting Todo toggled: " <> uid)
          model
        }
      }
    }
    UserDeletedTodo(uid:) -> dict.delete(model, uid)
    UserRenamedTodo(uid:, summary:) -> {
      case dict.get(model, uid) {
        Ok(item) -> dict.insert(model, uid, TodoItem(..item, summary:))
        _ -> {
          io.print_error("Nonexisting Todo renamed: " <> uid)
          model
        }
      }
    }
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  todo_list.render(dict.values(model))
}
