import gleam/list
import lustre/attribute
import lustre/element/html
import lustre/event
import shogg/vtodo
import todo_message
import widgets/todo_card

pub fn render(todos: List(vtodo.VTodo)) {
  let submitted = fn(fields) {
    let assert Ok(#(_, summary)) =
      list.find(fields, fn(f: #(String, String)) { f.0 == "summary" })
    summary |> todo_message.UserAddedTodo
  }

  html.main([attribute.class("container")], [
    html.h1([], [html.text("Todo List")]),
    html.form([event.on_submit(submitted)], [
      html.fieldset([attribute.role("group")], [
        html.input([
          attribute.name("summary"),
          attribute.placeholder("Add a new todo"),
          attribute.type_("text"),
        ]),
        html.button([attribute.type_("submit")], [html.text("Add")]),
      ]),
    ]),
    ..list.map(todos, todo_card.render)
  ])
}
