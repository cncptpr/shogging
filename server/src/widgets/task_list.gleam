import gleam/io
import gleam/list
import lustre/attribute.{attribute, class}
import lustre/element/html
import lustre/element/keyed
import lustre/event
import shogg/task
import message.{UserClickedReload}
import widgets/task_card

pub fn render(tasks: List(task.Task)) {
  let submitted = fn(fields) {
    io.println("Submitting")
    let assert Ok(#(_, summary)) =
      list.find(fields, fn(f: #(String, String)) { f.0 == "summary" })
    summary |> message.UserAddedTask
  }

  html.main(
    [
      class("text-amber-950"),
      attribute("x-data", "{ new_summary: undefined }"),
    ],
    [
      html.div([class("mx-auto max-w-3xl px-6 py-10")], [
        html.div([class("flex flex-wrap items-center gap-3")], [
          html.h1([class("flex-1 text-3xl font-semibold tracking-tight")], [
            html.text("Shogging List"),
          ]),
          html.button(
            [
              class(
                "rounded-full bg-amber-700 px-4 py-2 text-sm font-semibold text-amber-50 shadow-sm",
              ),
              attribute("x-init", ""),
              attribute("x-on:click", "new_summary = ''"),
              attribute.type_("button"),
            ],
            [html.text("Add")],
          ),
          html.button(
            [
              class(
                "rounded-full border border-amber-300 bg-amber-50 px-4 py-2 text-sm font-semibold text-amber-800 shadow-sm",
              ),
              event.on_click(UserClickedReload),
              attribute.type_("button"),
            ],
            [html.text("Reload")],
          ),
        ]),
        keyed.div(
          [class("mt-6 space-y-3")],
          list.map(tasks, fn(item) { #(item.uid, task_card.render(item)) }),
        ),
      ]),
      html.div(
        [
          attribute.style("display", "none"),
          class("fixed inset-0 bg-amber-900/5"),
          attribute("x-show", "new_summary !== undefined"),
          attribute("x-on:click", "new_summary = undefined"),
        ],
        [
          html.article(
            [
              class(
                "absolute top-1/2 left-1/2 w-[90vw] max-w-md -translate-x-1/2 -translate-y-1/2 rounded-2xl border border-amber-200 bg-amber-50 p-6 shadow-[0_10px_24px_rgba(120,70,30,0.18)]",
              ),
              attribute("x-on:click.stop", ""),
            ],
            [
              html.h2([class("text-lg font-semibold text-amber-900")], [
                html.text("Add New Todo"),
              ]),
              html.form(
                [
                  event.on_submit(submitted),
                  attribute("x-on:submit", "new_summary = undefined"),
                  class("mt-4"),
                ],
                [
                  html.fieldset([attribute.role("group"), class("flex gap-2")], [
                    html.input([
                      attribute.type_("text"),
                      attribute.name("summary"),
                      attribute.required(True),
                      attribute("x-model", "new_summary"),
                      class(
                        "w-full rounded-lg border border-amber-200 bg-white px-3 py-2 text-amber-900 shadow-inner focus:border-amber-400 focus:outline-none focus:ring-2 focus:ring-amber-200",
                      ),
                    ]),
                    html.button(
                      [
                        attribute.type_("submit"),
                        class(
                          "rounded-lg bg-amber-600 px-4 py-2 text-sm font-semibold text-amber-50 shadow-sm",
                        ),
                      ],
                      [html.text("Submit")],
                    ),
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
