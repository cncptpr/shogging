//// The list of todos together with the header and the empty state.

import gleam/list
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/keyed
import lustre/event
import model.{
  type Connection, type Msg, Connecting, Connected, Reconnecting,
  UserClickedAdd, UserClickedReload,
}
import shared/api.{type Todo}
import ui/task_card

pub fn view(todos: List(Todo), connection: Connection) -> Element(Msg) {
  html.main([class("text-amber-950")], [
    html.div([class("mx-auto max-w-3xl px-6 py-10")], [
      header(connection),
      body(todos),
    ]),
  ])
}

fn header(connection: Connection) -> Element(Msg) {
  html.div([class("flex flex-wrap items-center gap-3")], [
    html.h1([class("flex-1 text-3xl font-semibold tracking-tight")], [
      html.text("Shogging List"),
    ]),
    status(connection),
    html.button(
      [
        class("rounded-full bg-amber-700 px-4 py-2 text-sm font-semibold text-amber-50 shadow-sm"),
        attribute.type_("button"),
        event.on_click(UserClickedAdd),
      ],
      [html.text("Add")],
    ),
    html.button(
      [
        class("rounded-full border border-amber-300 bg-amber-50 px-4 py-2 text-sm font-semibold text-amber-800 shadow-sm"),
        attribute.type_("button"),
        event.on_click(UserClickedReload),
      ],
      [html.text("Reload")],
    ),
  ])
}

fn status(connection: Connection) -> Element(Msg) {
  case connection {
    Connected -> element.none()
    Connecting ->
      html.span([class("rounded-full bg-amber-200 px-3 py-1 text-xs font-semibold text-amber-800")], [
        html.text("Connecting…"),
      ])
    Reconnecting ->
      html.span([class("rounded-full bg-amber-300 px-3 py-1 text-xs font-semibold text-amber-950")], [
        html.text("Reconnecting…"),
      ])
  }
}

fn body(todos: List(Todo)) -> Element(Msg) {
  case todos {
    [] ->
      html.p([class("mt-6 text-sm text-amber-800")], [
        html.text("Nothing to do yet. Add a todo above."),
      ])
    todos ->
      keyed.div(
        [class("mt-6 space-y-3")],
        list.map(todos, fn(item) { #(item.id, task_card.view(item)) }),
      )
  }
}
