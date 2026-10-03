//// The list of todos together with the header and the empty state.
////
//// As in `task_card`, the paper and the doodles come from `client.css`; this
//// module is only concerned with what is on the sheet and in what order.

import gleam/list
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/keyed
import lustre/event
import model.{
  type Connection, type Msg, Connected, Connecting, Reconnecting, UserClickedAdd,
  UserClickedReload,
}
import shared/api.{type Todo}
import ui/task_card

pub fn view(
  todos: List(Todo),
  connection: Connection,
  motto: String,
) -> Element(Msg) {
  html.main([class("sheet")], [
    header(connection, motto),
    body(todos),
  ])
}

fn header(connection: Connection, motto: String) -> Element(Msg) {
  html.div([class("flex flex-wrap items-end gap-x-4 gap-y-3")], [
    // `min-w-48` is what makes the wrap happen: without a floor under the
    // title, flex would just squeeze it narrower and narrower instead of moving
    // the buttons down.
    html.div([class("flex-1 min-w-48")], [
      html.h1([class("title")], [html.text("Shogging List")]),
      html.p([class("subtitle mt-1 flex items-center gap-2")], [
        html.span([class("doodle-icon doodle-spark")], []),
        html.text(motto),
      ]),
    ]),
    // The buttons stick together and stay out of the title's way. `ml-auto`
    // pins them to the right whether they fit beside the title or have wrapped
    // onto a line of their own, which is what happens on a narrow screen.
    html.div([class("ml-auto flex shrink-0 items-center gap-3")], [
      status(connection),
      html.button(
        [
          class("btn btn-filled"),
          attribute.type_("button"),
          event.on_click(UserClickedAdd),
        ],
        [html.text("+ add")],
      ),
      html.button(
        [
          class("btn"),
          attribute.type_("button"),
          event.on_click(UserClickedReload),
        ],
        [html.text("reload")],
      ),
    ]),
  ])
}

fn status(connection: Connection) -> Element(Msg) {
  case connection {
    Connected -> element.none()
    Connecting ->
      html.span([class("chip chip-quiet")], [
        html.text("connecting…"),
      ])
    Reconnecting ->
      html.span([class("chip chip-tilted")], [
        html.text("reconnecting…"),
      ])
  }
}

fn body(todos: List(Todo)) -> Element(Msg) {
  case todos {
    [] -> empty_state()
    todos ->
      keyed.div(
        [class("mt-8 space-y-4")],
        list.map(todos, fn(item) { #(item.id, task_card.view(item)) }),
      )
  }
}

fn empty_state() -> Element(Msg) {
  html.div([class("note mt-10 max-w-md")], [
    html.p([class("subtitle text-2xl text-ink")], [
      html.text("Nothing to do yet."),
    ]),
    html.p([class("mt-1 text-ink-soft")], [
      html.text("Add something above and it will show up here, in pencil."),
    ]),
  ])
}
