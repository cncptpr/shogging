//// The modal dialog used for adding and renaming a todo.
////
//// The clickable backdrop is a *sibling* of the dialog rather than its
//// parent: that way clicking inside the dialog never bubbles onto the
//// backdrop, so no event propagation tricks are needed to keep it open.

import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import model.{
  type Dialog, type Msg, AddDialog, NoDialog, RenameDialog, UserDismissedDialog,
  UserSubmittedDraft, UserTypedDraft,
}

pub fn view(current: Dialog, draft: String) -> Element(Msg) {
  case current {
    NoDialog -> element.none()
    AddDialog -> render("Add a new thing", draft)
    RenameDialog(_) -> render("Scratch that, write this", draft)
  }
}

fn render(title: String, draft: String) -> Element(Msg) {
  html.div([class("fixed inset-0 z-50")], [
    html.div([class("scrim"), event.on_click(UserDismissedDialog)], []),
    html.article([class("dialog retrace")], [
      html.h2([class("subtitle text-3xl text-ink")], [html.text(title)]),
      html.form([event.on_submit(fn(_) { UserSubmittedDraft }), class("mt-5")], [
        html.fieldset([attribute.role("group"), class("flex gap-3")], [
          html.input([
            attribute.type_("text"),
            attribute.name("summary"),
            attribute.value(draft),
            attribute.placeholder("in pencil…"),
            attribute.required(True),
            attribute.autofocus(True),
            event.on_input(UserTypedDraft),
            class("field focus:border-pencil-blue focus:outline-none"),
          ]),
          html.button(
            [
              attribute.type_("submit"),
              class("btn btn-filled self-center"),
            ],
            [html.text("ok")],
          ),
        ]),
      ]),
    ]),
  ])
}
