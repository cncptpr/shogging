import gleam/list
import gleam/option.{Some}
import lustre/attribute.{styles}
import lustre/element
import lustre/element/html
import lustre/event
import shogg/vtodo
import styles.{f, flex, invert, vcenter, width}
import todo_message.{UserCheckedTodo}

pub fn render(item: vtodo.VTodo) {
  let submitted = fn(fields) {
    let assert Ok(#(_, summary)) =
      list.find(fields, fn(f: #(String, String)) { f.0 == "name" })
    summary |> todo_message.UserRenamedTodo(item.uid, _)
  }

  let completed = vtodo.is_competed(item)
  let assert Some(summary) = item.summary
  let popover_id = "rename-prompt-" <> item.uid
  element.fragment([
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
          event.on_check(UserCheckedTodo(item.uid, _)),
        ]),
        html.span([styles([f(1)])], [
          case completed {
            True ->
              html.del([attribute.style("color", "grey")], [html.text(summary)])
            False -> html.text(summary)
          },
        ]),
        html.button(
          [
            attribute.popovertarget(popover_id),
            attribute.class("outline"),
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
            event.on_click(todo_message.UserDeletedTodo(item.uid)),
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
        attribute.id(popover_id),
        attribute.class("popup-content"),
        attribute.popover("auto"),
      ],
      [
        html.h2([], [html.text("Rename")]),
        html.form([event.on_submit(submitted)], [
          html.fieldset([attribute.role("group")], [
            html.input([
              attribute.type_("text"),
              attribute.name("name"),
              attribute.value(summary),
              attribute.required(True),
            ]),
            html.button(
              [
                attribute.type_("submit"),
                attribute.popovertarget(popover_id),
                attribute.popovertargetaction("hidden"),
              ],
              [html.text("Submit")],
            ),
          ]),
        ]),
      ],
    ),
  ])
}
