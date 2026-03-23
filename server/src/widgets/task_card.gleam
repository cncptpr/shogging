import gleam/list
import gleam/option.{Some}
import lustre/attribute.{attribute, styles}
import lustre/element/html
import lustre/event
import shogg/task
import styles.{f, flex, invert, vcenter, width}
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
        styles([
          flex,
          vcenter,
          width("inherit"),
          #("transition", "all 0.3s ease"),
        ]),
      ],
      [
        html.input([
          attribute.type_("checkbox"),
          attribute.checked(completed),
          event.on_check(UserCheckedTask(item.uid, _)),
        ]),
        html.span([styles([f(1)])], [
          case completed {
            True ->
              html.del([attribute.style("color", "grey")], [
                html.text(summary),
              ])
            False -> html.text(summary)
          },
        ]),
        html.button(
          [
            attribute.class("outline"),
            attribute("x-on:click", "open = '" <> item.uid <> "'"),
          ],
          [
            html.img([
              attribute.src("https://www.svgrepo.com/show/521620/edit.svg"),
              attribute.width(20),
              styles([invert]),
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
              styles([invert]),
            ]),
          ],
        ),
      ],
    ),
    html.div(
      [
        styles([
          #("display", "none"),
          #("position", "absolute"),
          #("width", "100%"),
          #("height", "100%"),
          #("top", "0"),
          #("left", "0"),
          #("bottom", "0"),
          #("right", "0"),
          #("background-color", "rgb(0 0 0 / 10%)"),
        ]),
        attribute("x-show", "open === '" <> item.uid <> "'"),
        attribute("x-on:click", "open = undefined"),
      ],
      [
        html.article(
          [
            attribute.id(popover_id),
            attribute.class("popup-content"),
            styles([
              #("position", "absolute"),
              #("top", "50%"),
              #("left", "50%"),
              #("transform", "translate(-50%, -50%)"),
            ]),
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
