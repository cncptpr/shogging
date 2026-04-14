import gleam/list
import gleam/option.{Some}
import lustre/attribute.{attribute, class}
import lustre/element/html
import lustre/event
import shogg/task
import task_message.{UserCheckedTask}

pub fn render(item: task.Task) {
  let submitted = fn(fields) {
    let assert Ok(#(_, summary)) =
      list.find(fields, fn(f: #(String, String)) { f.0 == "name" })
    summary |> task_message.UserRenamedTask(item.uid, _)
  }

  let completed = task.is_competed(item)
  let assert Some(summary) = item.summary
  let popover_id = "rename-prompt-" <> item.uid
  html.div([class("relative")], [
    html.label(
      [
        class(
          "group flex items-center gap-3 rounded-xl border border-amber-100/80 bg-amber-50/70 px-4 py-3 shadow-[0_1px_0_rgba(120,70,30,0.08),0_10px_20px_rgba(120,70,30,0.08)] backdrop-blur-sm transition hover:-translate-y-0.5 hover:shadow-[0_1px_0_rgba(120,70,30,0.12),0_16px_30px_rgba(120,70,30,0.14)]",
        ),
      ],
      [
        html.input([
          attribute.type_("checkbox"),
          attribute.checked(completed),
          class(
            "h-4 w-4 rounded-sm border-amber-300 text-amber-700 focus:ring-2 focus:ring-amber-300",
          ),
          event.on_check(UserCheckedTask(item.uid, _)),
        ]),
        html.span([class("flex-1 text-amber-900")], [
          case completed {
            True ->
              html.del([class("text-amber-500/80")], [
                html.text(summary),
              ])
            False -> html.text(summary)
          },
        ]),
        html.button(
          [
            class(
              "rounded-md p-1.5 text-amber-600/80 transition hover:bg-amber-100 hover:text-amber-800",
            ),
            attribute("x-on:click", "open = '" <> item.uid <> "'"),
            attribute.type_("button"),
          ],
          [
            html.img([
              attribute.src("https://www.svgrepo.com/show/521620/edit.svg"),
              attribute.width(18),
              class("opacity-70 transition group-hover:opacity-100"),
              // class("invert"),
            ]),
          ],
        ),
        html.button(
          [
            class(
              "rounded-md p-1.5 text-amber-600/80 transition hover:bg-amber-100 hover:text-amber-800",
            ),
            event.on_click(task_message.UserDeletedTask(item.uid)),
            attribute.type_("button"),
          ],
          [
            html.img([
              attribute.src("https://www.svgrepo.com/show/533007/trash.svg"),
              attribute.width(18),
              class("opacity-70 transition group-hover:opacity-100"),
              // class("invert"),
            ]),
          ],
        ),
      ],
    ),
    html.div(
      [
        attribute.attribute("style", "display: none;"),
        class("fixed inset-0 z-[9999] bg-amber-900/10 backdrop-blur-[1px]"),
        attribute("x-show", "open === '" <> item.uid <> "'"),
        attribute("x-on:click", "open = undefined"),
      ],
      [
        html.article(
          [
            attribute.id(popover_id),
            class(
              "absolute top-1/2 left-1/2 z-[10000] w-[90vw] max-w-md -translate-x-1/2 -translate-y-1/2 rounded-2xl border border-amber-100 bg-amber-50/90 p-6 shadow-[0_10px_30px_rgba(120,70,30,0.2)]",
            ),
            attribute("x-on:click.stop", ""),
          ],
          [
            html.h2([class("text-lg font-semibold text-amber-900")], [
              html.text("Rename"),
            ]),
            html.form(
              [
                attribute("x-on:submit", "open = undefined"),
                event.on_submit(submitted),
                class("mt-4"),
              ],
              [
                html.fieldset([attribute.role("group"), class("flex gap-2")], [
                  html.input([
                    attribute.type_("text"),
                    attribute.name("name"),
                    attribute.value(summary),
                    attribute.required(True),
                    class(
                      "w-full rounded-lg border border-amber-200 bg-white/80 px-3 py-2 text-amber-900 shadow-inner focus:border-amber-400 focus:outline-none focus:ring-2 focus:ring-amber-200",
                    ),
                  ]),
                  html.button(
                    [
                      attribute.type_("submit"),
                      class(
                        "rounded-lg bg-amber-600 px-4 py-2 text-sm font-semibold text-amber-50 shadow-sm transition hover:bg-amber-700",
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
  ])
}
