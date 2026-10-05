import gleam/bool
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import shogg.{type ShoggError, ParseError, SendError, XmlDecodeError}
import shogg/client.{type CalendarHomeSet, type Client, type IO}
import xml
import xml/decode

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
  home_set: CalendarHomeSet,
) -> Result(List(Calendar), ShoggError(e)) {
  let response = calendars_request(client, home_set) |> client.io.send
  use response <- result.try(response |> result.map_error(SendError))
  parse_calendars(response)
}

pub fn calendars_request(
  client: Client(_),
  calendar_home_set: CalendarHomeSet,
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
  |> request.set_path(calendar_home_set.home)
  |> request.set_method(http.Other("PROPFIND"))
  |> request.set_body(request_body)
  |> request.set_header("Depth", "1")
  |> request.set_header("Content-Type", "application/xml; charset=utf-8")
}

pub fn parse_calendars(
  response: Response(String),
) -> Result(List(Calendar), ShoggError(e)) {
  use root <- result.try(
    xml.parse(response.body, xml.NoWhitespaceOnly)
    |> result.map_error(XmlDecodeError),
  )
  use parsed <- result.try(
    decode.run(root, calendars_responses_decoder())
    |> result.map_error(XmlDecodeError),
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

/// Maps a `<resourcetype>` child's local name to what it means. A server is
/// free to advertise types this app does not know, so they are kept as
/// `Other` rather than refused.
fn resource_type_of_tag(tag: String) -> ResourceType {
  case tag {
    "addressbook" -> CardDAVAdressbook
    "collection" -> Collection
    "calendar" -> CalDAVCalendar
    "principal" -> Principal
    _ -> Other(tag)
  }
}

/// The components this app knows how to show tasks from.
///
/// A server is free to advertise others as well — availability and free/busy
/// among them — so an unrecognised name is dropped rather than refused: a
/// calendar that supports VTODOs alongside something else still supports VTODOs.
/// `Error` is what `list.filter_map` drops, hence the error rather than an
/// option; the same shape `decode_resource_type_tag` uses.
fn vcomponent_of_name(name name) -> Result(VComponent, Nil) {
  case name {
    "VTODO" -> Ok(VTask)
    "VEVENT" -> Ok(VEvent)
    "VJOURNAL" -> Ok(VJournal)
    _ -> Error(Nil)
  }
}

fn decode_calendars_propstat() -> decode.Decoder(Option(GetCalendarsProp)) {
  use status <- decode.field("status", decode.text)
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
  use prop <- decode.field("prop", {
    use display_name <- decode.optional_field(
      "displayname",
      None,
      decode.text |> decode.map(Some),
    )
    use ctag <- decode.optional_field(
      "getctag",
      None,
      decode.text |> decode.map(Some),
    )
    use ical_calendar_color <- decode.optional_field(
      "calendar-color",
      None,
      decode.text |> decode.map(Some),
    )
    use resource_types <- decode.optional_field(
      "resourcetype",
      None,
      decode.element
        |> decode.map(fn(element) {
          xml.children(element)
          |> list.map(fn(child) { resource_type_of_tag(child.tag) })
          |> Some
        }),
    )
    use supported_components <- decode.optional_field(
      "supported-calendar-component-set",
      None,
      // A server may send the element with nothing in it, so `comp` is looked
      // up optionally: an empty list rather than a failure to decode. Requiring
      // it meant one such calendar took down the whole listing.
      decode.children(
        "comp",
        decode.attribute("name", decode.success),
        fn(names) {
          let components = names |> list.filter_map(vcomponent_of_name)
          decode.success(Some(components))
        },
      ),
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

fn decode_calendars_response() -> decode.Decoder(GetCalendarsResponse) {
  use href <- decode.field("href", decode.text)
  use props <- decode.children("propstat", decode_calendars_propstat())
  case props |> option.values() |> list.first() {
    Ok(prop) -> GetCalendarsResponse(href, prop) |> decode.success
    Error(Nil) ->
      GetCalendarsResponse(href, GetCalendarsProp(None, None, None, None, None))
      |> decode.success
  }
}

fn calendars_responses_decoder() -> decode.Decoder(List(GetCalendarsResponse)) {
  use responses <- decode.children("response", decode_calendars_response())
  case responses {
    // An empty multistatus names no collection at all, which is not a
    // listing the rest of the app can use.
    [] -> decode.failure([], "Expected at least one <response> element")
    _ -> responses |> decode.success
  }
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

pub fn changed_request(
  client: Client(_),
  calendar: Calendar,
) -> Request(String) {
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
  use root <- result.try(
    xml.parse(response.body, xml.NoWhitespaceOnly)
    |> result.map_error(XmlDecodeError),
  )
  use parsed <- result.try(
    decode.run(root, ctag_decoder())
    |> result.map_error(XmlDecodeError),
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

fn ctag_decoder() -> decode.Decoder(List(CtagResponse)) {
  use responses <- decode.children("response", decode_ctag_response())
  responses |> decode.success
}

fn decode_ctag_response() -> decode.Decoder(CtagResponse) {
  use _href <- decode.field("href", decode.text)
  use props <- decode.children("propstat", decode_ctag_propstat())
  case props |> option.values() |> list.first() {
    Ok(CtagProp(Some(ctag))) -> CtagResponse(ctag:) |> decode.success
    _ -> decode.failure(CtagResponse(ctag: ""), "No 200 OK ctag found")
  }
}

fn decode_ctag_propstat() -> decode.Decoder(Option(CtagProp)) {
  use status <- decode.field("status", decode.text)
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
  use prop <- decode.field("prop", {
    use ctag <- decode.optional_field(
      "getctag",
      None,
      decode.text |> decode.map(Some),
    )
    CtagProp(ctag:) |> decode.success
  })
  Some(prop) |> decode.success
}
