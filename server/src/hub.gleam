//// Owns the CalDAV state and fans every change out to the connected clients.
////
//// The hub is the only place where a browser event turns into a CalDAV
//// request. Every websocket subscribes to it, and after each change it
//// broadcasts the complete list of todos, so all tabs stay in sync without
//// having to know about each other.

import gleam/erlang/process.{type Subject}
import gleam/hackney
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/otp/actor
import gleam/result
import gleam/string
import gleam/time/duration
import gleam/time/timestamp
import shared/api
import shogg
import shogg/calendar.{type Calendar}
import shogg/client.{type IO}
import shogg/task.{type Task}

/// The CalDAV client this deployment talks to.
pub type CalDavClient =
  client.Client(IO(hackney.Error))

pub type Msg {
  /// A websocket connected and wants the current list plus every update.
  Subscribe(subject: Subject(api.ServerMsg))
  /// A websocket went away.
  Unsubscribe(subject: Subject(api.ServerMsg))
  /// A browser asked for something to happen.
  Event(event: api.ClientMsg, reply_to: Subject(api.ServerMsg))
  /// The poller noticed it is time to look for changes on the server.
  Poll
}

type State {
  State(
    client: CalDavClient,
    calendar: Calendar,
    /// The todos as last fetched from the server, in the order we serve them.
    tasks: List(Task),
    subscribers: List(Subject(api.ServerMsg)),
    check_change_delay: duration.Duration,
  )
}

pub fn start(
  client: CalDavClient,
  calendar: Calendar,
  tasks: List(Task),
  check_change_delay: duration.Duration,
) -> Result(Subject(Msg), actor.StartError) {
  let state =
    State(
      client:,
      calendar:,
      tasks: sort_tasks(tasks),
      subscribers: [],
      check_change_delay:,
    )

  use started <- result.try(
    actor.new(state)
    |> actor.on_message(handle)
    |> actor.start,
  )

  start_polling(started.data, check_change_delay)
  Ok(started.data)
}

/// Looks for changes on the CalDAV server forever, nudging the hub every
/// `check_change_delay`. The hub does the actual work so that it always
/// compares against the calendar it currently holds.
fn start_polling(subject: Subject(Msg), delay: duration.Duration) -> Nil {
  process.spawn(fn() { poll_loop(subject, delay) })
  Nil
}

fn poll_loop(subject: Subject(Msg), delay: duration.Duration) -> Nil {
  delay |> duration.to_milliseconds |> process.sleep
  process.send(subject, Poll)
  poll_loop(subject, delay)
}

fn handle(state: State, msg: Msg) -> actor.Next(State, Msg) {
  case msg {
    Subscribe(subject) -> {
      process.send(subject, api.Todos(to_todos(state.tasks)))
      actor.continue(
        State(..state, subscribers: [subject, ..state.subscribers]),
      )
    }

    Unsubscribe(subject) ->
      actor.continue(
        State(
          ..state,
          subscribers: list.filter(state.subscribers, fn(subscriber) {
            subscriber != subject
          }),
        ),
      )

    Event(event, reply_to) ->
      actor.continue(handle_event(state, event, reply_to))

    Poll -> actor.continue(handle_poll(state))
  }
}

fn handle_poll(state: State) -> State {
  case calendar.has_changed(state.client, state.calendar) {
    Ok(calendar.Changed(new_calendar)) ->
      refresh(State(..state, calendar: new_calendar))
    Ok(calendar.Unchanged) -> state
    Error(error) -> {
      io.print_error("[hub] could not check for changes: " <> describe(error))
      state
    }
  }
}

fn handle_event(
  state: State,
  event: api.ClientMsg,
  reply_to: Subject(api.ServerMsg),
) -> State {
  case event {
    api.Reload -> refresh(state)

    api.AddTodo(summary) ->
      mutate(
        state,
        reply_to,
        task.send_create_task(state.client, state.calendar, summary)
          |> result.replace(Nil),
      )

    api.ToggleTodo(id, completed) ->
      change_todo(state, reply_to, id, fn(item) {
        case completed {
          True ->
            task.Task(
              ..item,
              status: Some("COMPLETED"),
              completed: Some(timestamp.system_time() |> task.format_cal_date),
              percent_complete: Some(100),
            )
          False ->
            task.Task(
              ..item,
              status: Some("NEEDS-ACTION"),
              completed: None,
              percent_complete: None,
            )
        }
      })

    api.RenameTodo(id, summary) ->
      change_todo(state, reply_to, id, fn(item) {
        task.Task(..item, summary: Some(summary))
      })

    api.DeleteTodo(id) -> delete_todo(state, reply_to, id)
  }
}

fn change_todo(
  state: State,
  reply_to: Subject(api.ServerMsg),
  id: String,
  change: fn(Task) -> Task,
) -> State {
  case find_task(state.tasks, id) {
    Error(Nil) ->
      mutate(
        state,
        reply_to,
        Error(shogg.ParseError("There is no todo with id " <> id)),
      )
    Ok(item) ->
      mutate(
        state,
        reply_to,
        task.send_update_task(state.client, change(item))
          |> result.replace(Nil),
      )
  }
}

fn delete_todo(
  state: State,
  reply_to: Subject(api.ServerMsg),
  id: String,
) -> State {
  case find_task(state.tasks, id) {
    Error(Nil) ->
      mutate(
        state,
        reply_to,
        Error(shogg.ParseError("There is no todo with id " <> id)),
      )
    Ok(item) ->
      mutate(state, reply_to, task.send_delete_task(state.client, item))
  }
}

/// Run one CalDAV mutation. Success means everybody gets a fresh list;
/// failure means the client that asked gets an error *and* a fresh list, so
/// the optimistic update it made in the meantime is rolled back.
fn mutate(
  state: State,
  reply_to: Subject(api.ServerMsg),
  outcome: Result(Nil, shogg.ShoggError(hackney.Error)),
) -> State {
  case outcome {
    Ok(Nil) -> refresh(state)
    Error(error) -> {
      let message = describe(error)
      io.print_error("[hub] " <> message)
      process.send(reply_to, api.ActionFailed(message:))
      broadcast(state, api.Todos(to_todos(state.tasks)))
      state
    }
  }
}

fn refresh(state: State) -> State {
  case task.fetch_tasks(state.client, state.calendar) {
    Ok(tasks) -> {
      let tasks = sort_tasks(tasks)
      broadcast(state, api.Todos(to_todos(tasks)))
      State(..state, tasks:)
    }
    Error(error) -> {
      io.print_error("[hub] could not fetch the todos: " <> describe(error))
      state
    }
  }
}

fn broadcast(state: State, msg: api.ServerMsg) -> Nil {
  list.each(state.subscribers, fn(subscriber) { process.send(subscriber, msg) })
}

fn find_task(tasks: List(Task), id: String) -> Result(Task, Nil) {
  list.find(tasks, fn(item) { item.uid == id })
}

fn to_todos(tasks: List(Task)) -> List(api.Todo) {
  list.map(tasks, fn(item) {
    api.Todo(
      id: item.uid,
      summary: option.unwrap(item.summary, ""),
      completed: task.is_competed(item),
    )
  })
}

// The server sorts, so that the client never has to care how CalDAV wants its
// tasks ordered: completed tasks last, then by the app's sort order, then by
// name.
fn sort_tasks(tasks: List(Task)) -> List(Task) {
  tasks
  |> list.sort(fn(a, b) {
    string.compare(option.unwrap(a.summary, ""), option.unwrap(b.summary, ""))
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

fn describe(error: shogg.ShoggError(_)) -> String {
  case error {
    shogg.ParseError(message) -> message
    shogg.SendError(_) -> "Could not reach the CalDAV server"
    shogg.XmlDecodeError(_) -> "Could not understand the CalDAV server's reply"
  }
}
