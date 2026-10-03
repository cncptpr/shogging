//// Settings that belong to a deployment rather than to the build.
////
//// The frontend is a static bundle that is compiled once and served as-is, so
//// anything that should differ per installation cannot live in it. The server
//// reads these from the environment instead and bakes them into the page (see
//// `html.gleam`), which the bundle reads back on startup.
////
//// The port is the exception: it is read here too, but it is for the server
//// itself rather than for the page, so it is handed straight to mist.

import envoy
import gleam/int
import gleam/result
import gleam/string

/// `SHOGGING_MOTTO` sets the line under the title.
pub const motto_variable = "SHOGGING_MOTTO"

/// Used when the variable is unset, or set to nothing but whitespace.
pub const default_motto = "Kaufe das Zeug!!!"

/// `SHOGGING_PORT` sets the port the server listens on.
pub const port_variable = "SHOGGING_PORT"

/// Used when the variable is unset or is not a number, so that an unconfigured
/// server is reachable on the port `lustre/dev` proxies to.
pub const default_port = 1234

pub type Config {
  Config(motto: String, port: Int)
}

/// Read the configuration from the environment.
///
/// A missing or blank variable falls back to the default rather than failing.
/// The frontend compiles in the same default, so the two agree on what an
/// unconfigured shogging looks like whether it is served by this server or by
/// `lustre/dev`.
pub fn from_env() -> Config {
  Config(motto: motto_from_env(), port: port_from_env())
}

/// A motto of nothing but whitespace counts as unset: a blank line under the
/// title is not a thing anybody wants, so it falls back like a missing variable.
fn motto_from_env() -> String {
  case envoy.get(motto_variable) {
    Ok(value) ->
      case string.trim(value) {
        "" -> default_motto
        motto -> motto
      }

    Error(_) -> default_motto
  }
}

fn port_from_env() -> Int {
  case envoy.get(port_variable) {
    Ok(value) -> port_from_value(value)
    Error(_) -> default_port
  }
}

/// The parsing on its own, without the environment, so that it can be tested
/// without setting variables for the whole test run.
pub fn port_from_value(value: String) -> Int {
  value |> int.parse |> result.unwrap(default_port)
}