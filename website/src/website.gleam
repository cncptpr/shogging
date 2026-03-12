import lustre
import lustre/element/html
import lustre/server_component

pub fn main() {
  let app =
    lustre.element(
      html.div([], [
        html.text("Hello, world!"),
        server_component.element([server_component.route("/ws")], [
          html.text("slot"),
        ]),
      ]),
    )
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}
