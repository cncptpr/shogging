import gleam/bool
import gleam/dict
import gleam/dynamic/decode
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import parsed_it/xml
import shogg.{type ShoggError, DecodeError, ParseError, SendError}
import shogg/client.{type Client, type IO, type UserInfo}

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

fn decode_calendars_propstat() {
  use status <- decode_text_field("status")
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
      decode_text() |> decode.map(Some),
    )
    use ctag <- decode.optional_field(
      "CS:getctag",
      None,
      decode_text() |> decode.map(Some),
    )
    use ical_calendar_color <- decode.optional_field(
      "ns3:calendar-color",
      None,
      decode_text() |> decode.map(Some),
    )
    use resource_types <- decode.optional_field(
      "resourcetype",
      None,
      decode.dict(decode.string, decode.dynamic)
        |> decode.map(fn(d) {
          dict.keys(d)
          |> list.filter_map(fn(tag) {
            case tag {
              "$tag" -> Error(Nil)
              "$text" | "$attr" -> panic as "Unexpected tag"
              "CR:addressbook" -> Ok(CardDAVAdressbook)
              "collection" -> Ok(Collection)
              "C:calendar" -> Ok(CalDAVCalendar)
              "principal" -> Ok(Principal)
              tag -> Ok(Other(tag))
            }
          })
          |> Some
        }),
    )
    use supported_components <- decode.optional_field(
      "C:supported-calendar-component-set",
      None,
      decode.field(
        "C:comp",
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

fn decode_calendars_response() {
  use href <- decode.field(
    "href",
    decode.field("$text", decode.string, decode.success),
  )
  use props <- decode.field(
    "propstat",
    decode_xml_list(decode_calendars_propstat()),
  )
  case props |> option.values() |> list.first() {
    Ok(prop) -> GetCalendarsResponse(href, prop) |> decode.success
    Error(Nil) ->
      GetCalendarsResponse(href, GetCalendarsProp(None, None, None, None, None))
      |> decode.success
  }
}

fn calendars_responses_decoder() {
  use root_tag <- decode.field("$tag", decode.string)
  let expected_root_tag = "multistatus"
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
  use Nil <- decode.field("$attrs", assert_namespaces_decoder())

  use responses <- decode.field(
    "response",
    decode_xml_list(decode_calendars_response()),
  )
  responses |> decode.success
}

// TODO: Parse Namespaces
fn assert_namespaces_decoder() {
  use xmlns <- decode.field("xmlns", decode.string)
  use <- guard_ns(
    found: xmlns,
    expected: "DAV:",
    attr_name: "xmlns",
    ns_name: "default",
  )
  use xmlns_c <- decode.field("xmlns:C", decode.string)
  use <- guard_ns(
    found: xmlns_c,
    expected: "urn:ietf:params:xml:ns:caldav",
    attr_name: "xmlns:C",
    ns_name: "CalDAV",
  )
  use xmlns_ns3 <- decode.field("xmlns:ns3", decode.string)
  use <- guard_ns(
    found: xmlns_ns3,
    expected: "http://apple.com/ns:ical/",
    attr_name: "xmlns:ns3",
    ns_name: "Apple iCal",
  )
  decode.success(Nil)
}

fn guard_ns(
  found namespace,
  expected expected,
  attr_name attr,
  ns_name name,
  cb cb,
) {
  use <- bool.guard(
    when: namespace != expected && namespace != "",
    return: decode.failure(
      Nil,
      "Expected '"
        <> expected
        <> "' as the "
        <> name
        <> " ("
        <> attr
        <> ") namespace, found '"
        <> namespace
        <> "'.",
    ),
  )
  cb()
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
  use root_tag <- decode.field("$tag", decode.string)
  use <- bool.guard(
    when: root_tag != "multistatus",
    return: decode.failure([], "Expected 'multistatus' as root tag"),
  )
  use Nil <- decode.field("$attrs", assert_ctag_namespaces_decoder())

  use responses <- decode.field(
    "response",
    decode_xml_list(decode_ctag_response()),
  )
  responses |> decode.success
}

fn assert_ctag_namespaces_decoder() {
  use xmlns <- decode.field("xmlns", decode.string)
  use <- bool.guard(
    when: xmlns != "DAV:" && xmlns != "",
    return: decode.failure(Nil, "Expected DAV namespace"),
  )
  use xmlns_cs <- decode.field("xmlns:CS", decode.string)
  use <- bool.guard(
    when: xmlns_cs != "http://calendarserver.org/ns/" && xmlns_cs != "",
    return: decode.failure(Nil, "Expected CS namespace"),
  )
  decode.success(Nil)
}

fn decode_ctag_response() {
  use _href <- decode.field(
    "href",
    decode.field("$text", decode.string, decode.success),
  )
  use props <- decode.field("propstat", decode_xml_list(decode_ctag_propstat()))
  case props |> option.values() |> list.first() {
    Ok(CtagProp(Some(ctag))) -> CtagResponse(ctag:) |> decode.success
    _ -> decode.failure(CtagResponse(ctag: ""), "No 200 OK ctag found")
  }
}

fn decode_ctag_propstat() {
  use status <- decode.field("status", decode_text())
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
      "CS:getctag",
      None,
      decode_text() |> decode.map(Some),
    )
    CtagProp(ctag:) |> decode.success
  })
  Some(prop) |> decode.success
}
