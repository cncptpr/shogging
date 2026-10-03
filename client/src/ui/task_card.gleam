//// A single todo: a checkbox, its summary and the edit/delete actions.

import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import model.{type Msg}
import shared/api.{type Todo}

pub fn view(item: Todo) -> Element(Msg) {
  html.label([class("group flex items-center gap-3 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 shadow-[0_1px_0_rgba(120,70,30,0.06),0_6px_14px_rgba(120,70,30,0.08)]")], [
    html.input([
      attribute.type_("checkbox"),
      attribute.checked(item.completed),
      class("h-4 w-4 rounded-sm border-amber-300 focus:ring-2 focus:ring-amber-300"),
      event.on_check(model.UserToggled(item.id, _)),
    ]),
    html.span([class("flex-1")], [summary(item)]),
    edit_button(item),
    delete_button(item),
  ])
}

fn summary(item: Todo) -> Element(Msg) {
  let text = [html.text(item.summary)]

  case item.completed {
    True -> html.del([], text)
    False -> html.text(item.summary)
  }
}

fn edit_button(item: Todo) -> Element(Msg) {
  html.button(
    [
      class("rounded-md p-1.5"),
      attribute.type_("button"),
      attribute.attribute("aria-label", "Edit " <> item.summary),
      event.on_click(model.UserClickedRename(item.id)),
    ],
    [html.img([attribute.src("/static/edit.svg"), attribute.width(18)])],
  )
}

fn delete_button(item: Todo) -> Element(Msg) {
  html.button(
    [
      class("rounded-md p-1.5"),
      attribute.type_("button"),
      attribute.attribute("aria-label", "Delete " <> item.summary),
      event.on_click(model.UserClickedDelete(item.id)),
    ],
    [html.img([attribute.src("/static/trash.svg"), attribute.width(18)])],
  )
}
