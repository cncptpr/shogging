import gleam/bool
import gleam/dict
import gleam/dynamic/decode
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import parsed_it/xml
import shogg.{type ShoggError, DecodeError, ParseError, SendError}
import shogg/client.{type Client, type IO, type UserInfo}
import shogg/namespace.{Apple, CALDAV, CalendarServer, DAV, xmlns}

pub type VComponent {
  VEvent
  VJournal
  VTask
}

pub type Calendar {
  Calendar(
    href: String,
    name: String,
    ctag: String,
    components: List(VComponent),
    // TODO: Fix Color
    color: Option(String),
  )
}

pub type Change(a) {
  Changed(a)
  Unchanged
}

pub fn fetch_calendars(
  client: Client(IO(e)),
  info: UserInfo,
) -> Result(List(Calendar), ShoggError(e)) {
  let response = calendars_request(client, info) |> client.io.send
  use response <- result.try(response |> result.map_error(SendError))
  parse_calendars(response)
}

pub fn calendars_request(
  client: Client(_),
  user_info: UserInfo,
) -> Request(String) {
  let request_body =
    "<d:propfind xmlns:d=\"DAV:\" xmlns:cs=\"http://calendarserver.org/ns/\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\" xmlns:apple=\"http://apple.com/ns:ical/\">
        <d:prop>
          <d:resourcetype/>
          <d:displayname/>
          <cs:getctag/>
          <c:supported-calendar-component-set/>
          <apple:calendar-color/>
        </d:prop>
      </d:propfind>"

  client.request
  |> request.set_path(user_info.principal)
  |> request.set_method(http.Other("PROPFIND"))
  |> request.set_body(request_body)
  |> request.set_header("Depth", "1")
  |> request.set_header("Content-Type", "application/xml; charset=utf-8")
}

pub fn parse_calendars(
  response: Response(String),
) -> Result(List(Calendar), ShoggError(e)) {
  io.println(response.body)
  use parsed <- result.try(
    xml.parse(response.body, calendars_responses_decoder())
    |> result.map_error(DecodeError),
  )
  Ok(responses_to_calendar(parsed))
}

type ResourceType {
  Principal
  Collection
  CardDAVAdressbook
  CalDAVCalendar
  Other(String)
}

type GetCalendarsProp {
  GetCalendarsProp(
    resource_types: Option(List(ResourceType)),
    display_name: Option(String),
    ctag: Option(String),
    supported_components: Option(List(VComponent)),
    ical_calendar_color: Option(String),
  )
}

type GetCalendarsResponse {
  GetCalendarsResponse(href: String, prop: GetCalendarsProp)
}

fn decode_text_field(name name, cb cb) {
  decode.field(name, decode_text(), cb)
}

fn decode_text() {
  decode.field("$text", decode.string, decode.success)
}

fn decode_xml_list(element decoder) {
  decode.one_of(decode.list(decoder), or: [
    decoder |> decode.map(fn(v) { [v] }),
  ])
}

fn decode_resource_type_tag(ns, tag) {
  case tag {
    "$tag" -> Error(Nil)
    "$text" | "$attr" -> panic as "Unexpected tag"
    _ -> {
      let expected = xmlns(ns, DAV, "addressbook")
      case tag == expected {
        True -> Ok(CardDAVAdressbook)
        False -> {
          let expected = xmlns(ns, DAV, "collection")
          case tag == expected {
            True -> Ok(Collection)
            False -> {
              let expected = xmlns(ns, CALDAV, "calendar")
              case tag == expected {
                True -> Ok(CalDAVCalendar)
                False -> {
                  let expected = xmlns(ns, DAV, "principal")
                  case tag == expected {
                    True -> Ok(Principal)
                    False -> Ok(Other(tag))
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

fn decode_calendars_propstat(ns) {
  use status <- decode_text_field(xmlns(ns, DAV, "status"))
  use <- bool.guard(
    when: string.contains(status, "404 Not Found"),
    return: decode.success(None),
  )
  use <- bool.guard(
    when: !string.contains(status, "200 OK"),
    return: decode.failure(
      None,
      "Expected propstat status to either be '200 OK' or '404 Not Found'. Got '"
        <> status
        <> "'.",
    ),
  )
  use prop <- decode.field(xmlns(ns, DAV, "prop"), {
    use display_name <- decode.optional_field(
      xmlns(ns, DAV, "displayname"),
      None,
      decode_text() |> decode.map(Some),
    )
    use ctag <- decode.optional_field(
      xmlns(ns, CalendarServer, "getctag"),
      None,
      decode_text() |> decode.map(Some),
    )
    use ical_calendar_color <- decode.optional_field(
      xmlns(ns, Apple, "calendar-color"),
      None,
      decode_text() |> decode.map(Some),
    )
    use resource_types <- decode.optional_field(
      xmlns(ns, DAV, "resourcetype"),
      None,
      decode.dict(decode.string, decode.dynamic)
        |> decode.map(fn(d) {
          dict.keys(d)
          |> list.filter_map(fn(tag) { decode_resource_type_tag(ns, tag) })
          |> Some
        }),
    )
    use supported_components <- decode.optional_field(
      xmlns(ns, CALDAV, "supported-calendar-component-set"),
      None,
      decode.field(
        xmlns(ns, CALDAV, "comp"),
        decode_xml_list(decode.field(
          "$attrs",
          decode.field("name", decode.string, decode.success)
            |> decode.map(fn(name) {
              case name {
                "VTODO" -> VTask
                "VEVENT" -> VEvent
                "VJOURNAL" -> VJournal
                _ -> panic as "Unknown component"
              }
            }),
          decode.success,
        )),
        decode.success,
      )
        |> decode.map(Some),
    )
    GetCalendarsProp(
      resource_types:,
      display_name:,
      ctag:,
      supported_components:,
      ical_calendar_color:,
    )
    |> decode.success
  })
  Some(prop) |> decode.success
}

fn decode_calendars_response(ns) {
  use href <- decode.field(
    xmlns(ns, DAV, "href"),
    decode.field("$text", decode.string, decode.success),
  )
  use props <- decode.field(
    xmlns(ns, DAV, "propstat"),
    decode_xml_list(decode_calendars_propstat(ns)),
  )
  case props |> option.values() |> list.first() {
    Ok(prop) -> GetCalendarsResponse(href, prop) |> decode.success
    Error(Nil) ->
      GetCalendarsResponse(href, GetCalendarsProp(None, None, None, None, None))
      |> decode.success
  }
}

fn calendars_responses_decoder() {
  use ns <- decode.then(namespace.decode_namespaces())
  echo ns
  use root_tag <- decode.field("$tag", decode.string)
  let expected_root_tag = xmlns(ns, DAV, "multistatus")
  use <- bool.guard(
    when: root_tag != expected_root_tag,
    return: decode.failure(
      [],
      "Expected '"
        <> expected_root_tag
        <> "' as the root tag, found '"
        <> root_tag
        <> "'.",
    ),
  )

  use responses <- decode.field(
    xmlns(ns, DAV, "response"),
    decode_xml_list(decode_calendars_response(ns)),
  )
  responses |> decode.success
}

fn responses_to_calendar(responses: List(GetCalendarsResponse)) {
  responses
  |> list.filter_map(fn(res) {
    case res.prop {
      GetCalendarsProp(
        supported_components: Some(components),
        resource_types: Some(resource_types),
        display_name: Some(name),
        ctag: Some(ctag),
        ical_calendar_color: color,
      ) ->
        case list.contains(resource_types, CalDAVCalendar) {
          True ->
            Ok(Calendar(href: res.href, name:, ctag:, components:, color:))
          False -> Error(Nil)
        }
      _ -> Error(Nil)
    }
  })
}

pub fn changed_request(client: Client(_), calendar: Calendar) -> Request(String) {
  let request_body =
    "<d:propfind xmlns:d=\"DAV:\" xmlns:cs=\"http://calendarserver.org/ns/\">
      <d:prop>
        <cs:getctag/>
      </d:prop>
    </d:propfind>"

  client.request
  |> request.set_path(calendar.href)
  |> request.set_method(http.Other("PROPFIND"))
  |> request.set_body(request_body)
  |> request.set_header("Depth", "0")
  |> request.set_header("Content-Type", "application/xml; charset=utf-8")
}

pub fn parse_changed(
  calendar: Calendar,
  response: Response(String),
) -> Result(Change(Calendar), ShoggError(e)) {
  use parsed <- result.try(
    xml.parse(response.body, ctag_decoder())
    |> result.map_error(DecodeError),
  )
  case parsed {
    [] -> Error(ParseError("No ctag response found"))
    [CtagResponse(ctag:), ..] -> {
      let new_calendar = Calendar(..calendar, ctag: ctag)
      case ctag == calendar.ctag {
        True -> Ok(Unchanged)
        False -> Ok(Changed(new_calendar))
      }
    }
  }
}

pub fn has_changed(
  client: Client(IO(e)),
  calendar: Calendar,
) -> Result(Change(Calendar), ShoggError(e)) {
  let response = changed_request(client, calendar) |> client.io.send
  use response <- result.try(response |> result.map_error(SendError))
  parse_changed(calendar, response)
}

type CtagProp {
  CtagProp(ctag: Option(String))
}

type CtagResponse {
  CtagResponse(ctag: String)
}

fn ctag_decoder() {
  use ns <- decode.then(namespace.decode_namespaces())
  use root_tag <- decode.field("$tag", decode.string)
  use <- bool.guard(
    when: root_tag != xmlns(ns, DAV, "multistatus"),
    return: decode.failure([], "Expected 'multistatus' as root tag"),
  )

  use responses <- decode.field(
    xmlns(ns, DAV, "response"),
    decode_xml_list(decode_ctag_response(ns)),
  )
  responses |> decode.success
}

fn decode_ctag_response(ns) {
  use _href <- decode.field(
    xmlns(ns, DAV, "href"),
    decode.field("$text", decode.string, decode.success),
  )
  use props <- decode.field(
    xmlns(ns, DAV, "propstat"),
    decode_xml_list(decode_ctag_propstat(ns)),
  )
  case props |> option.values() |> list.first() {
    Ok(CtagProp(Some(ctag))) -> CtagResponse(ctag:) |> decode.success
    _ -> decode.failure(CtagResponse(ctag: ""), "No 200 OK ctag found")
  }
}

fn decode_ctag_propstat(ns) {
  use status <- decode.field(xmlns(ns, DAV, "status"), decode_text())
  use <- bool.guard(
    when: string.contains(status, "404 Not Found"),
    return: decode.success(None),
  )
  use <- bool.guard(
    when: !string.contains(status, "200 OK"),
    return: decode.failure(
      None,
      "Expected propstat status to be '200 OK'. Got '" <> status <> "'.",
    ),
  )
  use prop <- decode.field(xmlns(ns, DAV, "prop"), {
    use ctag <- decode.optional_field(
      xmlns(ns, CalendarServer, "getctag"),
      None,
      decode_text() |> decode.map(Some),
    )
    CtagProp(ctag:) |> decode.success
  })
  Some(prop) |> decode.success
}
