//// Settings that belong to a deployment rather than to the build.
////
//// The frontend is a static bundle that is compiled once and served as-is, so
//// anything that should differ per installation cannot live in it. The server
//// reads these from the environment instead and bakes them into the page (see
//// `html.gleam`), which the bundle reads back on startup.

import envoy
import gleam/string

/// `SHOGGING_MOTTO` sets the line under the title.
pub const motto_variable = "SHOGGING_MOTTO"

/// Used when the variable is unset, or set to nothing but whitespace.
pub const default_motto = "Kaufe das Zeug!!!"

pub type Config {
  Config(motto: String)
}

/// Read the configuration from the environment.
///
/// A missing or blank variable falls back to the default rather than failing.
/// The frontend compiles in the same default, so the two agree on what an
/// unconfigured shogging looks like whether it is served by this server or by
/// `lustre/dev`.
pub fn from_env() -> Config {
  case envoy.get(motto_variable) {
    Ok(value) ->
      case string.trim(value) {
        "" -> Config(default_motto)
        motto -> Config(motto)
      }

    Error(_) -> Config(default_motto)
  }
}
