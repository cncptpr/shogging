import gleam/function
import lustre/attribute.{styles}
import lustre/element/html
import lustre/event
import styles.{f, flex, invert, vcenter, width}
import todo_list
import types.{type TodoItem}

pub fn render(item: TodoItem) {
  html.label([styles([flex, vcenter, width("inherit")])], [
    html.input([attribute.type_("checkbox"), attribute.checked(item.checked)]),
    html.span([styles([f(1)])], [
      case item.checked {
        True -> fn(v) { html.del([attribute.style("color", "grey")], [v]) }
        False -> function.identity
      }(html.text(item.summary)),
    ]),
    html.button([attribute.class("outline")], [
      html.img([
        attribute.src("https://www.svgrepo.com/show/521620/edit.svg"),
        attribute.width(20),
        styles([invert]),
      ]),
    ]),
    html.button(
      [
        attribute.class("outline"),
        event.on_click(todo_list.UserDeletedTodo(item.uid)),
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
