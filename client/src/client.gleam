//// The frontend's entry point.

import lustre
import app

pub fn main() -> Nil {
  let assert Ok(_) = lustre.start(app.app(), "#app", Nil)
  Nil
}
