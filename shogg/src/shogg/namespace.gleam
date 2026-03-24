import gleam/dict
import gleam/dynamic.{
  type Dynamic, classify, list as dyn_list, properties, string,
}
import gleam/dynamic/decode
import gleam/list
import gleam/string

pub type Xmlns {
  DAV
  CALDAV
  CalendarServer
  Apple
}

pub fn to_string(ns) {
  case ns {
    DAV -> "DAV:"
    CALDAV -> "urn:ietf:params:xml:ns:caldav"
    CalendarServer -> "http://calendarserver.org/ns/"
    Apple -> "http://apple.com/ns:ical/"
  }
}

fn strip_key(key: String) -> String {
  case string.split_once(key, ":") {
    Ok(#(_, suffix)) -> suffix
    Error(_) -> key
  }
}

pub fn strip_dynamic(d: Dynamic) -> Dynamic {
  case classify(d) {
    "Dict" -> {
      case decode.run(d, decode.dict(decode.string, decode.dynamic)) {
        Ok(dict) -> {
          dict.to_list(dict)
          |> list.map(fn(entry) {
            let #(key, value) = entry
            #(string(strip_key(key)), strip_dynamic(value))
          })
          |> properties()
        }
        Error(_) -> d
      }
    }
    "List" -> {
      case decode.run(d, decode.list(decode.dynamic)) {
        Ok(items) -> dyn_list(list.map(items, strip_dynamic))
        Error(_) -> d
      }
    }
    _ -> d
  }
}
