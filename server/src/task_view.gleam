import gleam/erlang/process
import gleam/hackney
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/string
import gleam/time/duration
import gleam/time/timestamp
import lustre.{type App}
import lustre/attribute
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html
import shogg/calendar.{type Calendar}
import shogg/client.{type IO}
import shogg/task.{type Task}
import task_message.{
  type Msg, ShoggDetectedChange, ShoggFetchedTasks, ShoggSendUpdate,
  UserAddedTask, UserCheckedTask, UserClickedReload, UserDeletedTask,
  UserRenamedTask,
}
import widgets/task_list

pub fn component() -> App(_, Model, Msg) {
  lustre.application(init, update, view)
}

type Client =
  client.Client(IO(hackney.Error))

// TODO: Split task into completed, and uncompleted. Hide completed
pub type Model {
  Model(
    client: Client,
    calendar: Calendar,
    tasks: List(Task),
    check_change_delay: duration.Duration,
  )
}

fn init(data) -> #(Model, _) {
  let #(client, calendar, tasks, seconds) = data
  let model =
    Model(
      client:,
      calendar:,
      tasks: tasks |> sort_tasks,
      check_change_delay: duration.seconds(seconds),
    )
  #(model, spawn_check_changed_effect(model))
}

fn fetch_tasks_effect(model: Model) {
  effect.from(fn(dispatch) {
    let assert Ok(tasks) = task.fetch_tasks(model.client, model.calendar)
    tasks |> ShoggFetchedTasks |> dispatch
  })
}

fn check_changed_loop(model: Model, dispatch) {
  model.check_change_delay |> duration.to_milliseconds |> process.sleep
  let assert Ok(change) = calendar.has_changed(model.client, model.calendar)
  case change {
    calendar.Changed(calendar) -> calendar |> ShoggDetectedChange |> dispatch
    calendar.Unchanged -> check_changed_loop(model, dispatch)
  }
}

/// Spawns a new process, that repeatedly checks the CalDAV Server for a change.
/// When a change is detected, sends a `ShoggChangeDetected` Message, and terminates.
fn spawn_check_changed_effect(model: Model) {
  use dispatch <- effect.from()
  process.spawn(fn() { check_changed_loop(model, dispatch) })
  Nil
}

fn sort_tasks(tasks: List(Task)) {
  tasks
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
    case task.is_competed(a), task.is_competed(b) {
      True, False -> order.Gt
      False, True -> order.Lt
      _, _ -> order.Eq
    }
  })
}

fn update(model: Model, msg: Msg) -> #(Model, _) {
  case msg {
    ShoggFetchedTasks(tasks) -> {
      io.println("Tasks fetched!")
      #(Model(..model, tasks: tasks |> sort_tasks), effect.none())
    }
    ShoggSendUpdate(task) -> {
      let tasks =
        list.map(model.tasks, fn(t) {
          case t.uid == task.uid {
            True -> task
            False -> t
          }
        })
      #(Model(..model, tasks:), effect.none())
    }
    UserClickedReload -> {
      #(model, fetch_tasks_effect(model))
    }
    UserAddedTask(summary:) -> {
      let assert Ok(_href) =
        task.send_create_task(model.client, model.calendar, summary)
      #(model, effect.none())
    }
    UserCheckedTask(uid:, checked:) ->
      handle_user_checked_task(model, uid, checked)
    UserRenamedTask(uid:, summary:) ->
      handle_user_renamed_task(model, uid, summary)
    UserDeletedTask(uid:) -> handle_user_deleted_task(model, uid)
    ShoggDetectedChange(calendar) -> {
      let model = Model(..model, calendar:)
      #(
        model,
        effect.batch([
          fetch_tasks_effect(model),
          spawn_check_changed_effect(model),
        ]),
      )
    }
  }
}

fn handle_user_renamed_task(
  model: Model,
  uid: String,
  summary: String,
) -> #(Model, effect.Effect(Msg)) {
  let assert Ok(task) = list.find(model.tasks, fn(t) { t.uid == uid })
  let task = task.Task(..task, summary: Some(summary))
  let tasks =
    list.map(model.tasks, fn(t) {
      case t.uid == uid {
        True -> task
        False -> t
      }
    })
    |> sort_tasks

  let do_request = fn(dispatch) {
    let response = task.send_update_task(model.client, task)
    case response {
      Ok(task) -> task |> ShoggSendUpdate |> dispatch
      // TODO: Proper retry
      Error(_) -> io.print_error("[Error] Failed to send update")
    }
  }

  #(Model(..model, tasks:), effect.from(do_request))
}

fn handle_user_checked_task(
  model: Model,
  uid: String,
  checked: Bool,
) -> #(Model, effect.Effect(Msg)) {
  let assert Ok(task) = list.find(model.tasks, fn(t) { t.uid == uid })
  // TODO: use Enum for status and timestamp for time.
  let task = case checked {
    True ->
      task.Task(
        ..task,
        status: Some("COMPLETED"),
        completed: Some(timestamp.system_time() |> task.format_cal_date),
      )
    False -> task.Task(..task, status: Some("NEEDS-ACTION"), completed: None)
  }
  let tasks =
    list.map(model.tasks, fn(t) {
      case t.uid == uid {
        True -> task
        False -> t
      }
    })
    |> sort_tasks
  #(
    Model(..model, tasks:),
    effect.from(fn(dispatch) {
      // TODO: Proper Retry
      let assert Ok(task) = task.send_update_task(model.client, task)
      task |> ShoggSendUpdate |> dispatch
    }),
  )
}

fn handle_user_deleted_task(
  model: Model,
  uid: String,
) -> #(Model, effect.Effect(Msg)) {
  let assert Ok(task) = list.find(model.tasks, fn(t) { t.uid == uid })
  let tasks = model.tasks |> list.filter(fn(t) { t.uid != uid }) |> sort_tasks
  #(
    Model(..model, tasks:),
    effect.from(fn(_dispatch) {
      let response = task.send_delete_task(model.client, task)

      case response {
        Ok(_) -> Nil
        Error(_) ->
          io.println(
            "[Error] Failed to delete task "
            <> case task.summary {
              Some(summary) -> summary <> " "
              None -> ""
            }
            <> "["
            <> task.uid
            <> "]",
          )
      }
      Nil
    }),
  )
}

fn view(model: Model) -> Element(Msg) {
  html.div([attribute.attribute("x-data", "{ open: undefined }")], [
    task_list.render(model.tasks),
  ])
}
