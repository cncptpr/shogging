// IMPORTS ---------------------------------------------------------------------

import gleam/hackney
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
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
  lustre.application(init, update, view)
}

// MODEL -----------------------------------------------------------------------

type Client =
  client.Client(String, IO(hackney.Error))

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

fn update(model: Model, msg: Msg) -> #(Model, _) {
  case msg {
    ShoggFetchedCalendar(calendar) -> #(
      Model(..model, calendar: Some(calendar)),
      fetch_todos_effect(model, calendar),
    )
    ShoggFetchedTodos(todos) -> {
      io.println("Todos fetched!")
      #(Model(..model, todos: Some(todos)), effect.none())
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
      let todos = list.filter(todos, fn(t) { t.uid != uid })
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
