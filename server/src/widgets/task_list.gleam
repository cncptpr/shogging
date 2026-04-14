import gleam/io
import gleam/list
import lustre/attribute.{attribute, class}
import lustre/element/html
import lustre/element/keyed
import lustre/event
import shogg/task
import task_message.{UserClickedReload}
import widgets/task_card

pub fn render(tasks: List(task.Task)) {
  let submitted = fn(fields) {
    io.println("Submitting")
    let assert Ok(#(_, summary)) =
      list.find(fields, fn(f: #(String, String)) { f.0 == "summary" })
    summary |> task_message.UserAddedTask
  }

  html.main(
    [
      class("container"),
      attribute("x-data", "{ new_summary: undefined }"),
    ],
    [
      html.div([class("flex align-center")], [
        html.h1([class("flex-1")], [
          html.text("Shogging List"),
        ]),
        html.button(
          [
            class("px-2.5 py-1.25 mr-2.5"),
            attribute("x-init", ""),
            attribute("x-on:click", "new_summary = ''"),
          ],
          [html.text("Add")],
        ),
        html.button(
          [
            class("px-2.5 py-1.25"),
            attribute.class("outline"),
            event.on_click(UserClickedReload),
          ],
          [html.text("Reload")],
        ),
      ]),
      keyed.div(
        [],
        list.map(tasks, fn(item) { #(item.uid, task_card.render(item)) }),
      ),
      html.div(
        [
          class("hidden absolute w-full h-full inset-0 bg-black/10"),
          attribute("x-show", "new_summary !== undefined"),
          attribute("x-on:click", "new_summary = undefined"),
        ],
        [
          html.article(
            [
              class(
                "absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2",
              ),
              attribute("x-on:click.stop", ""),
            ],
            [
              html.h2([], [html.text("Add New Todo")]),
              html.form(
                [
                  event.on_submit(submitted),
                  attribute("x-on:submit", "new_summary = undefined"),
                ],
                [
                  html.fieldset([attribute.role("group")], [
                    html.input([
                      attribute.type_("text"),
                      attribute.name("summary"),
                      attribute.required(True),
                      attribute("x-model", "new_summary"),
                    ]),
                    html.button([attribute.type_("submit")], [
                      html.text("Submit"),
                    ]),
                  ]),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  )
}
