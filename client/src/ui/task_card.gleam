//// A single todo: a checkbox, its summary and the edit/delete actions.
////
//// The look lives in `client.css` (`card`, `tick`, `doodle-icon`), so this
//// module only has to say which pieces of doodle to assemble.

import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import model.{type Msg}
import shared/api.{type Todo}

pub fn view(item: Todo) -> Element(Msg) {
  html.label([class("card")], [
    html.input([
      attribute.type_("checkbox"),
      attribute.checked(item.completed),
      class("tick"),
      event.on_check(model.UserToggled(item.id, _)),
    ]),
    html.span([class("card-summary")], [summary(item)]),
    edit_button(item),
    delete_button(item),
  ])
}

fn summary(item: Todo) -> Element(Msg) {
  case item.completed {
    True -> html.del([class("card-summary-done")], [html.text(item.summary)])
    False -> html.text(item.summary)
  }
}

fn edit_button(item: Todo) -> Element(Msg) {
  html.button(
    [
      class("icon-btn"),
      attribute.type_("button"),
      attribute.attribute("aria-label", "Edit " <> item.summary),
      event.on_click(model.UserClickedRename(item.id)),
    ],
    [html.span([class("doodle-icon doodle-pencil")], [])],
  )
}

fn delete_button(item: Todo) -> Element(Msg) {
  html.button(
    [
      class("icon-btn"),
      attribute.type_("button"),
      attribute.attribute("aria-label", "Delete " <> item.summary),
      event.on_click(model.UserClickedDelete(item.id)),
    ],
    [html.span([class("doodle-icon doodle-trash")], [])],
  )
}
