import gleam/dict
import gleam/dynamic/decode
import gleam/option.{type Option, None, Some}

pub type Xmlns {
  /// Base Protocol: General Recource Tags
  DAV
  /// Calendar Extention: Calendar, Event & Task Specific Tags
  CALDAV
  /// Sync Extention: etag & ctag
  CalendarServer
  /// Apple UX Extentions: Calendar Color
  Apple
}

pub type Namespaces {
  Namespaces(
    dav: Option(String),
    caldav: Option(String),
    calendarserver: Option(String),
    apple: Option(String),
  )
}

const empty_ns = Namespaces(None, None, None, None)

pub fn to_string(ns) {
  case ns {
    DAV -> "DAV:"
    CALDAV -> "urn:ietf:params:xml:ns:caldav"
    CalendarServer -> "http://calendarserver.org/ns/"
    Apple -> "http://apple.com/ns:ical/"
  }
}

pub type UnknownNamespace {
  UnknownNamespace(String)
}

pub fn from_string(ns) {
  case ns {
    "DAV:" -> Ok(DAV)
    "urn:ietf:params:xml:ns:caldav" -> Ok(CALDAV)
    "http://calendarserver.org/ns/" -> Ok(CalendarServer)
    "http://apple.com/ns:ical/" -> Ok(Apple)
    _ -> Error(UnknownNamespace(ns))
  }
}

fn set_namespace(namespaces, xmlns, prefix) {
  case xmlns {
    DAV -> Namespaces(..namespaces, dav: Some(prefix))
    CALDAV -> Namespaces(..namespaces, caldav: Some(prefix))
    CalendarServer -> Namespaces(..namespaces, calendarserver: Some(prefix))
    Apple -> Namespaces(..namespaces, apple: Some(prefix))
  }
}

pub fn xmlns(namespaces: Namespaces, xmlns, tag) {
  let name = case xmlns {
    DAV -> namespaces.dav
    CALDAV -> namespaces.caldav
    CalendarServer -> namespaces.calendarserver
    Apple -> namespaces.apple
  }
  case name {
    Some("") -> tag
    Some(name) -> name <> ":" <> tag
    None -> tag
  }
}

pub fn decode_namespaces() {
  decode.optional_field(
    "$attrs",
    empty_ns,
    {
      use dict <- decode.then(decode.dict(decode.string, decode.string))
      dict.fold(dict, empty_ns, fn(namespaces, name, full_name) {
        let xmlns = from_string(full_name)
        case xmlns, name {
          Error(UnknownNamespace(_)), _ -> namespaces
          Ok(xmlns), "xmlns" -> set_namespace(namespaces, xmlns, "")
          Ok(xmlns), "xmlns:" <> prefix ->
            set_namespace(namespaces, xmlns, prefix)
          Ok(_), _ -> namespaces
        }
      })
      |> decode.success
    },
    decode.success,
  )
}
