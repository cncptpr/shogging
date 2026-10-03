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
  type Dialog, type Msg, AddDialog, NoDialog, RenameDialog,
  UserDismissedDialog, UserSubmittedDraft, UserTypedDraft,
}

pub fn view(current: Dialog, draft: String) -> Element(Msg) {
  case current {
    NoDialog -> element.none()
    AddDialog -> render("Add New Todo", draft)
    RenameDialog(_) -> render("Rename", draft)
  }
}

fn render(title: String, draft: String) -> Element(Msg) {
  html.div([class("fixed inset-0 z-50")], [
    html.div([
      class("absolute inset-0 bg-amber-900/5"),
      event.on_click(UserDismissedDialog),
    ], []),
    html.article([class("absolute top-1/2 left-1/2 w-[90vw] max-w-md -translate-x-1/2 -translate-y-1/2 rounded-2xl border border-amber-200 bg-amber-50 p-6 shadow-[0_10px_24px_rgba(120,70,30,0.18)]")], [
      html.h2([class("text-lg font-semibold text-amber-900")], [
        html.text(title),
      ]),
      html.form([event.on_submit(fn(_) { UserSubmittedDraft }), class("mt-4")], [
        html.fieldset([attribute.role("group"), class("flex gap-2")], [
          html.input([
            attribute.type_("text"),
            attribute.name("summary"),
            attribute.value(draft),
            attribute.required(True),
            attribute.autofocus(True),
            event.on_input(UserTypedDraft),
            class("w-full rounded-lg border border-amber-200 bg-white px-3 py-2 text-amber-900 shadow-inner focus:border-amber-400 focus:outline-none focus:ring-2 focus:ring-amber-200"),
          ]),
          html.button(
            [
              attribute.type_("submit"),
              class("rounded-lg bg-amber-600 px-4 py-2 text-sm font-semibold text-amber-50 shadow-sm"),
            ],
            [html.text("Submit")],
          ),
        ]),
      ]),
    ]),
  ])
}
