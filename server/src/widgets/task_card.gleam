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
  html.div([], [
    html.label(
      [
        class("flex align-center"),
      ],
      [
        html.input([
          attribute.type_("checkbox"),
          attribute.checked(completed),
          event.on_check(UserCheckedTask(item.uid, _)),
        ]),
        html.span([class("flex-1")], [
          case completed {
            True ->
              html.del([class("text-grey-500")], [
                html.text(summary),
              ])
            False -> html.text(summary)
          },
        ]),
        html.button(
          [
            attribute("x-on:click", "open = '" <> item.uid <> "'"),
          ],
          [
            html.img([
              attribute.src("https://www.svgrepo.com/show/521620/edit.svg"),
              attribute.width(20),
              // class("invert"),
            ]),
          ],
        ),
        html.button(
          [
            attribute.class("outline"),
            event.on_click(task_message.UserDeletedTask(item.uid)),
          ],
          [
            html.img([
              attribute.src("https://www.svgrepo.com/show/533007/trash.svg"),
              attribute.width(20),
              // class("invert"),
            ]),
          ],
        ),
      ],
    ),
    html.div(
      [
        class(
          "hidden absolute w-full h-full t-0 l-0 b-0 r-0 bg-[rgb(0 0 0 / 10%)]",
        ),
        attribute("x-show", "open === '" <> item.uid <> "'"),
        attribute("x-on:click", "open = undefined"),
      ],
      [
        html.article(
          [
            attribute.id(popover_id),
            class("absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2"),
            attribute("x-on:click.stop", ""),
          ],
          [
            html.h2([], [html.text("Rename")]),
            html.form(
              [
                attribute("x-on:submit", "open = undefined"),
                event.on_submit(submitted),
              ],
              [
                html.fieldset([attribute.role("group")], [
                  html.input([
                    attribute.type_("text"),
                    attribute.name("name"),
                    attribute.value(summary),
                    attribute.required(True),
                  ]),
                  html.button([attribute.type_("submit")], [html.text("Submit")]),
                ]),
              ],
            ),
          ],
        ),
      ],
    ),
  ])
}
