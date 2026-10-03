//// The frontend's entry point.

import app
import lustre

pub fn main() -> Nil {
  let assert Ok(_) = lustre.start(app.app(), "#app", Nil)
  Nil
}
