import dotenv
import envoy
import gleam/bool
import gleam/dict
import gleam/dynamic/decode
import gleam/function
import gleam/hackney
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import parsed_it/xml
import shogg/caldav
import simplifile

const xml_ct = "application/xml; charset=utf-8"

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

type ShoggError(send_error) {
  SendError(error: send_error)
  DecodeError(error: xml.XmlDecodeError)
}

type Client(send_fn) {
  Client(
    request: Request(String),
    base_path: String,
    user_path: Option(String),
    send_fn: send_fn,
  )
}

type NoSendFn {
  NoSendFn
}

fn new_client(scheme, host, username, password) {
  Client(
    request: request.new()
      |> request.set_scheme(scheme)
      |> request.set_host(host)
      |> request.set_header(
        "authorization",
        caldav.encode_basic_auth(username, password),
      ),
    base_path: "/caldav/",
    user_path: None,
    send_fn: NoSendFn,
  )
}

fn set_send_fn(client, send_fn: SendFn(e)) {
  Client(..client, send_fn:)
}

type ParsedCalendar {
  ParsedCalendar(href: String)
}

type ResourceType {
  Principal
  Collection
  CardDAVAdressbook
  CalDAVCalendar
  Other(tag: String)
}

type CalDAVComponent {
  VEvent
  VJournal
  VTodo
}

type GetCalendarsProp {
  GetCalendarsProp(
    resource_types: Option(List(ResourceType)),
    display_name: Option(String),
    ctag: Option(String),
    supported_components: Option(List(CalDAVComponent)),
    ical_calendar_color: Option(String),
  )
}

type GetCalendarsResponse {
  GetCalendarsResponse(href: String, prop: GetCalendarsProp)
}

type SendFn(error) =
  fn(Request(String)) -> Result(Response(String), error)

fn get_calendars(client: Client(SendFn(e))) {
  let request_body =
    "<d:propfind xmlns:d=\"DAV:\" xmlns:cs=\"http://calendarserver.org/ns/\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\" xmlns:apple=\"http://apple.com/ns/ical/\">
        <d:prop>
          <d:resourcetype/>
          <d:displayname/>
          <cs:getctag/>
          <c:supported-calendar-component-set/>
          <apple:calendar-color/>
        </d:prop>
      </d:propfind>"

  let assert Some(path) = client.user_path

  let response =
    client.request
    |> request.set_path(path)
    |> request.set_method(http.Other("PROPFIND"))
    |> request.set_body(request_body)
    |> request.set_header("Depth", "1")
    |> request.set_header("Content-Type", xml_ct)
    |> client.send_fn()
  use response <- result.try(response |> result.map_error(SendError))
  Ok(response.body)
}

fn make_info_request(client: Client(e)) {
  client.request
  |> request.set_path(client.base_path)
  |> request.set_method(http.Other("PROPFIND"))
  |> request.set_header("Depth", "1")
  |> request.set_header("Content-Type", xml_ct)
}

fn handle_info_response(client: Client(e), response: Response(String)) {
  use parsed <- result.try(
    xml.parse(response.body, home_propfined_responses_decoder())
    |> result.map_error(DecodeError),
  )
  case parsed {
    [] -> panic
    [first, ..] ->
      Ok(
        Client(
          ..client,
          base_path: first.href,
          user_path: Some(first.current_user_principal),
        ),
      )
  }
}

fn fetch_info(client: Client(SendFn(e))) {
  // TODO: proper discovery
  let response =
    make_info_request(client)
    |> client.send_fn()
  use response <- result.try(response |> result.map_error(SendError))
  handle_info_response(client, response)
}

type HomePropfindResponse {
  HomePropfindResponse(href: String, current_user_principal: String)
}

fn home_propfined_responses_decoder() {
  decode.field(
    "response",
    decode.list({
      use href <- decode.field(
        "href",
        decode.field("$text", decode.string, decode.success),
      )
      use current_user_principal <- decode.field(
        "propstat",
        decode.field(
          "prop",
          decode.field(
            "current-user-principal",
            decode.field(
              "href",
              decode.field("$text", decode.string, decode.success),
              decode.success,
            ),
            decode.success,
          ),
          decode.success,
        ),
      )
      HomePropfindResponse(href:, current_user_principal:) |> decode.success()
    }),
    decode.success,
  )
}

fn guarl_ns(
  found namespace,
  expected expected,
  attr_name attr,
  ns_name name,
  cb cb,
) {
  use <- bool.guard(
    when: namespace != expected,
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

fn assert_namespaces_decoder() {
  use xmlns <- decode.field("xmlns", decode.string)
  use <- guarl_ns(
    found: xmlns,
    expected: "DAV:",
    attr_name: "xmlns",
    ns_name: "default",
  )
  use xmlns_c <- decode.field("xmlns:C", decode.string)
  use <- guarl_ns(
    found: xmlns_c,
    expected: "urn:ietf:params:xml:ns:caldav",
    attr_name: "xmlns:C",
    ns_name: "CalDAV",
  )
  use xmlns_cr <- decode.field("xmlns:CR", decode.string)
  use <- guarl_ns(
    found: xmlns_cr,
    expected: "urn:ietf:params:xml:ns:carddav",
    attr_name: "xmlns:CR",
    ns_name: "CardDAV",
  )
  use xmlns_cs <- decode.field("xmlns:CS", decode.string)
  use <- guarl_ns(
    found: xmlns_cs,
    expected: "http://calendarserver.org/ns/",
    attr_name: "xmlns:CS",
    ns_name: "Calendar Server",
  )
  use xmlns_ical <- decode.field("xmlns:ICAL", decode.string)
  use <- guarl_ns(
    found: xmlns_ical,
    expected: "http://apple.com/ns/ical/",
    attr_name: "xmlns:ICAL",
    ns_name: "Apple",
  )
  decode.success(Nil)
}

fn decode_get_calendars_propstat() {
  // use tag <- decode.field("$tag", decode.string)
  // use <- bool.guard(
  // tag == "propstat",
  // decode.failure(None, "Expected to be inside of a propstat tag."),
  // )
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
      "ICAL:calendar-color",
      None,
      decode_text() |> decode.map(Some),
    )
    use resource_types <- decode.optional_field(
      "resourcetype",
      None,
      decode.dict(decode.string, decode.dynamic)
        |> decode.map(fn(dict) {
          dict.keys(dict)
          |> list.filter_map(fn(tag) {
            case tag {
              // Filter out meta tags (not an error)
              "$tag" -> Error(Nil)
              // TODO: proper error handling
              "$text" | "$attr" -> panic
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
                "VTODO" -> VTodo
                "VEVENT" -> VEvent
                "VJOURNAL" -> VJournal
                // TODO: proper error handling
                _ -> panic
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

type Calendar {
  Calendar(
    href: String,
    name: String,
    ctag: String,
    components: List(CalDAVComponent),
    color: Option(String),
  )
}

fn decode_get_calendars_response() {
  use href <- decode.field(
    "href",
    decode.field("$text", decode.string, decode.success),
  )
  use props <- decode.field(
    "propstat",
    decode_xml_list(decode_get_calendars_propstat()),
  )
  // Assumtion: There should only ever be one '200 Ok' prop (aka Some(prop)) in a reponse
  // TODO: validate assumtion
  case props |> option.values() |> list.first() {
    Ok(prop) -> GetCalendarsResponse(href, prop) |> decode.success
    Error(Nil) ->
      GetCalendarsResponse(href, GetCalendarsProp(None, None, None, None, None))
      |> decode.success
  }
}

fn get_calendars_responses_decoder() {
  // TODO: properly handle root tag and namespaces
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
    decode_xml_list(decode_get_calendars_response()),
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

pub fn main() {
  let assert Ok(Nil) = dotenv.config()

  let assert Ok(host) = envoy.get("CALDAV_HOST")
  let assert Ok(username) = envoy.get("CALDAV_USERNAME")
  let assert Ok(password) = envoy.get("CALDAV_PASSWORD")

  io.println("Connecting to CalDAV server...")

  // let config =
  //   caldav.ConnectionConfig(url: url, username: username, password: password)

  // let assert Ok(req) = caldav.new_client(config)

  let client =
    new_client(http.Https, host, username, password)
    |> set_send_fn(hackney.send)
  io.println("Sending initial PROPFIND request...")
  let assert Ok(client) = fetch_info(client)

  io.println("Fetching calendars")
  let assert Ok(calendars) = get_calendars(client)
  // let assert Ok(_) = simplifile.write("get_calendars_dump.xml", calendars)
  // let _ = echo xml.parse_dynamic(calendars)
  let assert Ok(calendars) =
    xml.parse(calendars, get_calendars_responses_decoder())
  let _calendars = responses_to_calendar(calendars) |> echo
  Nil
}
/// TODO:
/// - Get all todos
/// - Update todo
/// 
/// Later:
/// - Sync todos
/// - Make radicale add the VTODO component to a calendar
/// - Porper discovery of caldav base path (don't assume /caldav/)
