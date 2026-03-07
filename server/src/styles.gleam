import gleam/int

pub const flex = #("display", "flex")

pub const invert = #("filter", "invert(100%)")

pub const vcenter = #("align-items", "center")

pub fn f(strech) {
  #("flex", int.to_string(strech))
}

pub fn width(width) {
  #("width", width)
}
