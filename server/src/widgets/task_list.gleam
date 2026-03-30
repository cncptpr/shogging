import gleam/io
import gleam/list
import lustre/attribute.{attribute, styles}
import lustre/element/html
import lustre/element/keyed
import lustre/event
import shogg/task
import styles.{f, flex, vcenter}
import task_message.{UserClickedReload}
import widgets/task_card

pub fn render(tasks: List(task.Task)) {
  let submitted = fn(fields) {
    io.println("Submitting")
    let assert Ok(#(_, summary)) =
      list.find(fields, fn(f: #(String, String)) { f.0 == "summary" })
    summary |> task_message.UserAddedTask
  }

  html.main(
    [
      attribute.class("container"),
      attribute("x-data", "{ new_summary: undefined }"),
    ],
    [
      html.div([styles([flex, vcenter])], [
        html.h1([styles([f(1)])], [html.text("Shogging List")]),
        html.button(
          [
            styles([#("padding", "5px 10px"), #("margin-right", "10px")]),
            attribute("x-init", ""),
            attribute("x-on:click", "new_summary = ''"),
          ],
          [html.text("Add")],
        ),
        html.button(
          [
            styles([#("padding", "5px 10px")]),
            attribute.class("outline"),
            event.on_click(UserClickedReload),
          ],
          [html.text("Reload")],
        ),
      ]),
      keyed.div(
        [],
        list.map(tasks, fn(item) { #(item.uid, task_card.render(item)) }),
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
          attribute("x-show", "new_summary !== undefined"),
          attribute("x-on:click", "new_summary = undefined"),
        ],
        [
          html.article(
            [
              styles([
                #("position", "absolute"),
                #("top", "50%"),
                #("left", "50%"),
                #("transform", "translate(-50%, -50%)"),
              ]),
              attribute("x-on:click.stop", ""),
            ],
            [
              html.h2([], [html.text("Add New Todo")]),
              html.form(
                [
                  event.on_submit(submitted),
                  attribute("x-on:submit", "new_summary = undefined"),
                ],
                [
                  html.fieldset([attribute.role("group")], [
                    html.input([
                      attribute.type_("text"),
                      attribute.name("summary"),
                      attribute.required(True),
                      attribute("x-model", "new_summary"),
                    ]),
                    html.button([attribute.type_("submit")], [
                      html.text("Submit"),
                    ]),
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
