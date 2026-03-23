import gleam/list
import lustre/attribute.{styles}
import lustre/element/html
import lustre/element/keyed
import lustre/event
import shogg/task
import styles.{f, flex, vcenter}
import task_message.{UserClickedReload}
import widgets/task_card

pub fn render(tasks: List(task.Task)) {
  let submitted = fn(fields) {
    let assert Ok(#(_, summary)) =
      list.find(fields, fn(f: #(String, String)) { f.0 == "summary" })
    summary |> task_message.UserAddedTask
  }

  html.main([attribute.class("container")], [
    html.div([styles([flex, vcenter])], [
      html.h1([styles([f(1)])], [html.text("Shogging List")]),
      html.button(
        [
          styles([#("padding", "5px 10px")]),
          attribute.class("outline"),
          event.on_click(UserClickedReload),
        ],
        [html.text("Reload")],
      ),
    ]),
    html.form([event.on_submit(submitted)], [
      html.fieldset([attribute.role("group")], [
        html.input([
          attribute.name("summary"),
          attribute.placeholder("Add a new task"),
          attribute.type_("text"),
        ]),
        html.button([attribute.type_("submit")], [html.text("Add")]),
      ]),
    ]),
    keyed.div(
      [],
      list.map(tasks, fn(item) { #(item.uid, task_card.render(item)) }),
    ),
  ])
}
