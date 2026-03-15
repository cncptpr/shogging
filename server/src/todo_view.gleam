// IMPORTS ---------------------------------------------------------------------

import gleam/hackney
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import lustre.{type App}
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html
import shogg/calendar.{type Calendar}
import shogg/client.{type IO}
import shogg/vtodo.{type VTodo}
import todo_message.{
  type Msg, ShoggFetchedCalendar, ShoggFetchedTodos, ShoggSendUpdate,
  UserAddedTodo, UserCheckedTodo, UserClickedReload, UserDeletedTodo,
  UserRenamedTodo,
}
import widgets/todo_list

pub fn component() -> App(_, Model, Msg) {
  lustre.application(init, update, view)
}

type Client =
  client.Client(String, IO(hackney.Error))

// TODO: Split todo into completed, and uncompleted. Hide completed
pub type Model {
  Model(client: Client, calendar: Option(Calendar), todos: Option(List(VTodo)))
}

fn init(data) -> #(Model, _) {
  let #(client, calendar_name) = data
  #(
    Model(client, None, None),
    effect.from(fn(dispatch) {
      let assert Ok(calendars) = calendar.fetch_calendars(client)
      let assert Ok(calendar) =
        list.find(calendars, fn(c) { c.name == calendar_name })
      calendar |> ShoggFetchedCalendar |> dispatch
    }),
  )
}

// UPDATE ----------------------------------------------------------------------

fn fetch_todos_effect(model: Model, calendar) {
  effect.from(fn(dispatch) {
    let assert Ok(todos) = vtodo.fetch_todos(model.client, calendar)
    todos |> ShoggFetchedTodos |> dispatch
  })
}

fn sort_todos(todos: List(VTodo)) {
  todos
  |> list.sort(fn(a, b) {
    let assert Some(a) = a.summary
    let assert Some(b) = b.summary
    string.compare(a, b)
  })
  |> list.sort(fn(a, b) {
    case a.x_apple_sort_order, b.x_apple_sort_order {
      Some(a), Some(b) -> int.compare(a, b)
      _, _ -> order.Lt
    }
  })
  |> list.sort(fn(a, b) {
    case vtodo.is_competed(a), vtodo.is_competed(b) {
      True, False -> order.Gt
      False, True -> order.Lt
      _, _ -> order.Eq
    }
  })
}

fn update(model: Model, msg: Msg) -> #(Model, _) {
  case msg {
    ShoggFetchedCalendar(calendar) -> #(
      Model(..model, calendar: Some(calendar)),
      fetch_todos_effect(model, calendar),
    )
    ShoggFetchedTodos(todos) -> {
      io.println("Todos fetched!")
      #(Model(..model, todos: Some(todos |> sort_todos)), effect.none())
    }
    ShoggSendUpdate -> {
      let assert Some(calendar) = model.calendar
      #(model, fetch_todos_effect(model, calendar))
    }
    UserClickedReload -> {
      let assert Some(calendar) = model.calendar
      #(model, fetch_todos_effect(model, calendar))
    }
    UserAddedTodo(summary:) -> {
      let assert Some(calendar) = model.calendar
      let assert Ok(_href) =
        vtodo.send_create_todo(model.client, calendar, summary)
      #(model, fetch_todos_effect(model, calendar))
    }
    UserCheckedTodo(uid:, checked:) -> {
      let assert Model(client, _, Some(todos)) = model
      let assert Ok(vtodo) = list.find(todos, fn(t) { t.uid == uid })
      // TODO: use Enum for status and timestamp for time.
      let vtodo = case checked {
        True ->
          vtodo.VTodo(
            ..vtodo,
            status: Some("COMPLETED"),
            completed: Some(vtodo.get_now_formatted()),
          )
        False ->
          vtodo.VTodo(..vtodo, status: Some("NEEDS-ACTION"), completed: None)
      }
      let todos =
        list.map(todos, fn(t) {
          case t.uid == uid {
            True -> vtodo
            False -> t
          }
        })
        |> sort_todos
      #(
        Model(..model, todos: Some(todos)),
        effect.from(fn(dispatch) {
          let assert Ok(_href) = vtodo.send_update_todo(client, vtodo)
          ShoggSendUpdate |> dispatch
        }),
      )
    }
    UserRenamedTodo(uid:, summary:) -> {
      let assert Model(client, _, Some(todos)) = model
      let assert Ok(vtodo) = list.find(todos, fn(t) { t.uid == uid })
      let vtodo = vtodo.VTodo(..vtodo, summary: Some(summary))
      let todos =
        list.map(todos, fn(t) {
          case t.uid == uid {
            True -> vtodo
            False -> t
          }
        })
        |> sort_todos
      #(
        Model(..model, todos: Some(todos)),
        effect.from(fn(dispatch) {
          let assert Ok(_href) = vtodo.send_update_todo(client, vtodo)
          ShoggSendUpdate |> dispatch
        }),
      )
    }
    UserDeletedTodo(uid:) -> {
      let assert Model(client, _, Some(todos)) = model
      let assert Ok(vtodo) = list.find(todos, fn(t) { t.uid == uid })
      let todos = todos |> list.filter(fn(t) { t.uid != uid }) |> sort_todos
      #(
        Model(..model, todos: Some(todos)),
        effect.from(fn(dispatch) {
          let assert Ok(_) = vtodo.send_delete_todo(client, vtodo)
          // TODO: Make ShoggSendDelete message
          ShoggSendUpdate |> dispatch
        }),
      )
    }
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  case model {
    Model(_, _, Some(todos)) -> todo_list.render(todos)
    _ -> html.h2([], [html.text("Loading Todos ...")])
  }
}
