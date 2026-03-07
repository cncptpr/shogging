import components/todo_card
import gleam/list
import lustre/attribute
import lustre/element/html
import types.{type TodoItem}

pub fn render(todos: List(TodoItem)) {
  html.main([attribute.class("container")], [
    html.h1([], [html.text("Todo List")]),
    html.form([], [
      html.fieldset([attribute.role("group")], [
        html.input([
          attribute.placeholder("Add a new todo"),
          attribute.type_("text"),
        ]),
        html.button([], [html.text("Add")]),
      ]),
    ]),
    ..list.map(todos, todo_card.render)
  ])
}
