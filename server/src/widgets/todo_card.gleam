import gleam/function
import gleam/option.{Some}
import lustre/attribute.{styles}
import lustre/element/html
import lustre/event
import shogg/vtodo
import styles.{f, flex, invert, vcenter, width}
import todo_message.{UserCheckedTodo}

pub fn render(item: vtodo.VTodo) {
  let completed = vtodo.is_competed(item)
  let assert Some(summary) = item.summary
  html.label([styles([flex, vcenter, width("inherit")])], [
    html.input([
      attribute.type_("checkbox"),
      attribute.checked(completed),
      event.on_check(UserCheckedTodo(item.uid, _)),
    ]),
    html.span([styles([f(1)])], [
      case completed {
        True -> fn(v) { html.del([attribute.style("color", "grey")], [v]) }
        False -> function.identity
      }(html.text(summary)),
    ]),
    // TODO: how do I do this?
    // - How do I do a text field only on one client? Lustre SPA / Raw JS
    // - How do I send the result to the server? Normal Rest API
    html.button([attribute.class("outline"), attribute.disabled(True)], [
      html.img([
        attribute.src("https://www.svgrepo.com/show/521620/edit.svg"),
        attribute.width(20),
        styles([invert]),
      ]),
    ]),
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
  ])
}
