import gleam/http/response.{type Response}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import shogg/calendar
import shogg/client
import shogg/task

/// Edge cases built from hand-written CalDAV XML, shaped like what Radicale
/// and Nextcloud send but with the interesting bits isolated: missing
/// properties, odd propstat orders, empty elements, broken statuses.
///
/// Where a test documents that the parser *fails* on input a server may
/// legitimately send, that is the current behaviour being pinned down, not an
/// endorsement of it.
pub fn main() {
  gleeunit.main()
}

fn multistatus(inner: String) -> String {
  "<d:multistatus xmlns:d=\"DAV:\" xmlns:cs=\"http://calendarserver.org/ns/\""
  <> " xmlns:c=\"urn:ietf:params:xml:ns:caldav\""
  <> " xmlns:apple=\"http://apple.com/ns:ical/\">"
  <> inner
  <> "</d:multistatus>"
}

fn dav_response(href: String, propstats: String) -> String {
  "<d:response><d:href>" <> href <> "</d:href>" <> propstats <> "</d:response>"
}

/// `status` is the tail of a status line, e.g. `"200 OK"`.
fn propstat(status: String, prop: String) -> String {
  "<d:propstat>"
  <> prop
  <> "<d:status>HTTP/1.1 "
  <> status
  <> "</d:status></d:propstat>"
}

fn prop(inner: String) -> String {
  "<d:prop>" <> inner <> "</d:prop>"
}

fn as_response(body: String) -> Response(String) {
  response.Response(status: 207, headers: [], body:)
}

const resource_type = "<d:resourcetype><d:collection/><c:calendar/></d:resourcetype>"

const displayname = "<d:displayname>Tasks</d:displayname>"

const ctag = "<cs:getctag>tag-1</cs:getctag>"

const component_set = "<c:supported-calendar-component-set><c:comp name=\"VTODO\"/></c:supported-calendar-component-set>"

fn full_props() -> String {
  resource_type <> displayname <> ctag <> component_set
}

/// One calendar response, `200 OK`, with the given properties.
fn one_calendar(props: String) -> String {
  multistatus(dav_response(
    "/calendars/alice/tasks/",
    propstat("200 OK", prop(props)),
  ))
}

fn parse_calendars(body: String) {
  calendar.parse_calendars(as_response(body))
}

// --- Calendars ---------------------------------------------------------------

/// Every required property present, single response instead of a list.
pub fn calendar_with_full_props_test() {
  parse_calendars(one_calendar(full_props()))
  |> should.equal(
    Ok([
      calendar.Calendar(
        href: "/calendars/alice/tasks/",
        name: "Tasks",
        ctag: "tag-1",
        components: [calendar.VTask],
        color: None,
      ),
    ]),
  )
}

/// A response without a displayname has no name to show, so it is dropped.
pub fn calendar_without_displayname_is_dropped_test() {
  parse_calendars(one_calendar(resource_type <> ctag <> component_set))
  |> should.equal(Ok([]))
}

/// Same for the ctag, which the change polling is built on.
pub fn calendar_without_ctag_is_dropped_test() {
  parse_calendars(one_calendar(resource_type <> displayname <> component_set))
  |> should.equal(Ok([]))
}

/// The component set may be absent altogether, in which case there is no
/// evidence the calendar holds tasks.
pub fn calendar_without_component_set_is_dropped_test() {
  parse_calendars(one_calendar(resource_type <> displayname <> ctag))
  |> should.equal(Ok([]))
}

/// An explicitly empty component set is different from an absent one: the
/// server did answer, and said "no components".
pub fn calendar_with_empty_component_set_is_kept_test() {
  let props =
    resource_type
    <> displayname
    <> ctag
    <> "<c:supported-calendar-component-set></c:supported-calendar-component-set>"

  parse_calendars(one_calendar(props))
  |> should.equal(
    Ok([
      calendar.Calendar(
        href: "/calendars/alice/tasks/",
        name: "Tasks",
        ctag: "tag-1",
        components: [],
        color: None,
      ),
    ]),
  )
}

pub fn calendar_with_self_closing_component_set_is_kept_test() {
  let props =
    resource_type
    <> displayname
    <> ctag
    <> "<c:supported-calendar-component-set/>"

  parse_calendars(one_calendar(props))
  |> should.equal(
    Ok([
      calendar.Calendar(
        href: "/calendars/alice/tasks/",
        name: "Tasks",
        ctag: "tag-1",
        components: [],
        color: None,
      ),
    ]),
  )
}

/// `apple:calendar-color` is the only optional property that survives with a
/// value instead of being dropped.
pub fn calendar_color_is_kept_test() {
  let props =
    full_props() <> "<apple:calendar-color>#FF9900</apple:calendar-color>"

  let assert Ok([cal]) = parse_calendars(one_calendar(props))
  cal.color |> should.equal(Some("#FF9900"))
}

/// Without the colour element the field stays `None` rather than failing.
pub fn calendar_without_color_is_none_test() {
  let assert Ok([cal]) = parse_calendars(one_calendar(full_props()))
  cal.color |> should.equal(None)
}

/// A principal collection must not be listed as a calendar even when it
/// advertises a ctag and components.
pub fn calendar_without_calendar_resource_type_is_dropped_test() {
  let props =
    "<d:resourcetype><d:collection/><d:principal/></d:resourcetype>"
    <> displayname
    <> ctag
    <> component_set

  parse_calendars(one_calendar(props)) |> should.equal(Ok([]))
}

/// Servers advertise component types this app has never heard of next to the
/// ones it knows; the calendar is still usable.
pub fn calendar_with_unknown_resource_type_is_kept_test() {
  let props =
    "<d:resourcetype><d:collection/><c:calendar/><x:free-busy-set/></d:resourcetype>"
    <> displayname
    <> ctag
    <> component_set

  let assert Ok([cal]) = parse_calendars(one_calendar(props))
  cal.components |> should.equal([calendar.VTask])
}

/// Radicale splits the answered and unanswered properties into separate
/// propstats, the 404 one first. The 404'd colour must be skipped without
/// spoiling the 200 propstat behind it.
pub fn calendar_propstat_404_before_200_test() {
  let body =
    multistatus(dav_response(
      "/calendars/alice/tasks/",
      propstat(
        "404 Not Found",
        prop("<apple:calendar-color>#FF0000</apple:calendar-color>"),
      )
        <> propstat("200 OK", prop(full_props())),
    ))

  parse_calendars(body)
  |> should.equal(
    Ok([
      calendar.Calendar(
        href: "/calendars/alice/tasks/",
        name: "Tasks",
        ctag: "tag-1",
        components: [calendar.VTask],
        color: None,
      ),
    ]),
  )
}

/// Only the first `200 OK` propstat is read: everything a second one carries
/// is invisible, so a response that spreads properties over two 200 propstats
/// yields no calendar.
pub fn calendar_reads_only_the_first_200_propstat_test() {
  let body =
    multistatus(dav_response(
      "/calendars/alice/tasks/",
      propstat("200 OK", prop(displayname))
        <> propstat("200 OK", prop(ctag <> component_set)),
    ))

  parse_calendars(body) |> should.equal(Ok([]))
}

/// A propstat status that is neither `200 OK` nor `404 Not Found` fails the
/// whole listing rather than skipping the response.
pub fn calendar_unexpected_propstat_status_test() {
  parse_calendars(string.replace(
    one_calendar(full_props()),
    "200 OK",
    "403 Forbidden",
  ))
  |> should.be_error()
}

/// An empty multistatus has no `response` element at all.
pub fn calendar_empty_multistatus_test() {
  parse_calendars(multistatus("")) |> should.be_error()
}

pub fn calendar_malformed_xml_test() {
  parse_calendars("<d:multistatus xmlns:d=\"DAV:\"><d:response>")
  |> should.be_error()
}

/// A `href` without text in it cannot name the collection.
pub fn calendar_empty_href_test() {
  let body =
    multistatus(dav_response("", propstat("200 OK", prop(full_props()))))
    |> string.replace("<d:href></d:href>", "<d:href/>")

  parse_calendars(body) |> should.be_error()
}

// --- Tasks -------------------------------------------------------------------

fn tasks_multistatus(inner: String) -> String {
  "<d:multistatus xmlns:d=\"DAV:\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\">"
  <> inner
  <> "</d:multistatus>"
}

fn vtodo(summary: String) -> String {
  "BEGIN:VCALENDAR\n"
  <> "VERSION:2.0\n"
  <> "PRODID:-//Test//EN\n"
  <> "BEGIN:VTODO\n"
  <> "UID:uid-1\n"
  <> "DTSTAMP:20260101T000000Z\n"
  <> "STATUS:NEEDS-ACTION\n"
  <> "SUMMARY:"
  <> summary
  <> "\nEND:VTODO\n"
  <> "END:VCALENDAR\n"
}

/// One `200 OK` response carrying an etag and calendar data.
fn one_task(ical: String) -> String {
  tasks_multistatus(dav_response(
    "/calendars/alice/tasks/uid-1.ics",
    propstat(
      "200 OK",
      prop(
        "<d:getetag>\"etag-1\"</d:getetag><c:calendar-data>"
        <> ical
        <> "</c:calendar-data>",
      ),
    ),
  ))
}

fn parse_tasks(body: String) {
  task.parse_tasks(as_response(body))
}

pub fn task_with_full_props_test() {
  parse_tasks(one_task(vtodo("Buy milk")))
  |> should.equal(
    Ok([
      task.Task(
        uid: "uid-1",
        dtstamp: "20260101T000000Z",
        created: None,
        last_modified: None,
        status: Some("NEEDS-ACTION"),
        summary: Some("Buy milk"),
        completed: None,
        percent_complete: None,
        x_apple_sort_order: None,
        other: [],
        meta: task.TaskMeta(
          href: "/calendars/alice/tasks/uid-1.ics",
          etag: "\"etag-1\"",
        ),
      ),
    ]),
  )
}

/// Where the calendars parser treats an empty multistatus as an error, the
/// tasks parser answers "no tasks": `response` defaults to an empty list.
pub fn tasks_empty_multistatus_is_no_tasks_test() {
  parse_tasks(tasks_multistatus("")) |> should.equal(Ok([]))
}

/// A single response where a list is also legal.
pub fn tasks_single_response_element_test() {
  parse_tasks(one_task(vtodo("One")))
  |> should.equal(
    Ok([
      task.Task(
        uid: "uid-1",
        dtstamp: "20260101T000000Z",
        created: None,
        last_modified: None,
        status: Some("NEEDS-ACTION"),
        summary: Some("One"),
        completed: None,
        percent_complete: None,
        x_apple_sort_order: None,
        other: [],
        meta: task.TaskMeta(
          href: "/calendars/alice/tasks/uid-1.ics",
          etag: "\"etag-1\"",
        ),
      ),
    ]),
  )
}

/// One response the server could not answer (404) currently fails the parse
/// for the entire listing, taking the other, parsable responses with it.
pub fn tasks_one_404_propstat_fails_the_parse_test() {
  let good =
    dav_response(
      "/calendars/alice/tasks/uid-1.ics",
      propstat(
        "200 OK",
        prop(
          "<d:getetag>\"etag-1\"</d:getetag><c:calendar-data>"
          <> vtodo("Buy milk")
          <> "</c:calendar-data>",
        ),
      ),
    )
  let missing =
    dav_response(
      "/calendars/alice/tasks/gone.ics",
      propstat(
        "404 Not Found",
        prop(
          "<d:getetag>\"etag-2\"</d:getetag><c:calendar-data>"
          <> vtodo("Gone")
          <> "</c:calendar-data>",
        ),
      ),
    )

  parse_tasks(tasks_multistatus(good <> missing)) |> should.be_error()
}

/// Etag and calendar data are both required; one without the other is a
/// failed parse, not a partial task.
pub fn tasks_etag_without_calendar_data_test() {
  let body =
    tasks_multistatus(dav_response(
      "/calendars/alice/tasks/uid-1.ics",
      propstat("200 OK", prop("<d:getetag>\"etag-1\"</d:getetag>")),
    ))

  parse_tasks(body) |> should.be_error()
}

pub fn tasks_calendar_data_without_etag_test() {
  let body =
    tasks_multistatus(dav_response(
      "/calendars/alice/tasks/uid-1.ics",
      propstat(
        "200 OK",
        prop("<c:calendar-data>" <> vtodo("Buy milk") <> "</c:calendar-data>"),
      ),
    ))

  parse_tasks(body) |> should.be_error()
}

pub fn tasks_unexpected_propstat_status_test() {
  let body =
    tasks_multistatus(dav_response(
      "/calendars/alice/tasks/uid-1.ics",
      propstat(
        "403 Forbidden",
        prop(
          "<d:getetag>\"etag-1\"</d:getetag><c:calendar-data>"
          <> vtodo("Buy milk")
          <> "</c:calendar-data>",
        ),
      ),
    ))

  parse_tasks(body) |> should.be_error()
}

pub fn tasks_response_without_href_test() {
  let body =
    tasks_multistatus(
      "<d:response>"
      <> propstat(
        "200 OK",
        prop(
          "<d:getetag>\"etag-1\"</d:getetag><c:calendar-data>"
          <> vtodo("Buy milk")
          <> "</c:calendar-data>",
        ),
      )
      <> "</d:response>",
    )

  parse_tasks(body) |> should.be_error()
}

/// An item whose calendar-data is not ical at all is dropped from the list
/// while its parsable neighbours survive.
pub fn tasks_drops_unparseable_ical_test() {
  let good =
    dav_response(
      "/calendars/alice/tasks/uid-1.ics",
      propstat(
        "200 OK",
        prop(
          "<d:getetag>\"etag-1\"</d:getetag><c:calendar-data>"
          <> vtodo("Buy milk")
          <> "</c:calendar-data>",
        ),
      ),
    )
  let junk =
    dav_response(
      "/calendars/alice/tasks/junk.ics",
      propstat(
        "200 OK",
        prop(
          "<d:getetag>\"etag-2\"</d:getetag><c:calendar-data>not ical at all</c:calendar-data>",
        ),
      ),
    )

  let assert Ok(tasks) = parse_tasks(tasks_multistatus(good <> junk))
  tasks |> list.length |> should.equal(1)
}

/// A VTODO without its `BEGIN:VCALENDAR` wrapper is not trusted.
pub fn tasks_without_vcalendar_header_test() {
  let data = "BEGIN:VTODO\nUID:uid-1\nSUMMARY:Buy milk\nEND:VTODO\n"
  let body =
    tasks_multistatus(dav_response(
      "/calendars/alice/tasks/uid-1.ics",
      propstat(
        "200 OK",
        prop(
          "<d:getetag>\"etag-1\"</d:getetag><c:calendar-data>"
          <> data
          <> "</c:calendar-data>",
        ),
      ),
    ))

  parse_tasks(body) |> should.equal(Ok([]))
}

/// A VTODO that is never closed is not parsable and is dropped.
pub fn tasks_without_end_of_vtodo_test() {
  let data =
    "BEGIN:VCALENDAR\nVERSION:2.0\nBEGIN:VTODO\nUID:uid-1\nSUMMARY:Buy milk\n"
  let body =
    tasks_multistatus(dav_response(
      "/calendars/alice/tasks/uid-1.ics",
      propstat(
        "200 OK",
        prop(
          "<d:getetag>\"etag-1\"</d:getetag><c:calendar-data>"
          <> data
          <> "</c:calendar-data>",
        ),
      ),
    ))

  parse_tasks(body) |> should.equal(Ok([]))
}

// --- Change polling ----------------------------------------------------------

fn changed_body(propstats: String) -> String {
  multistatus(dav_response("/calendars/alice/tasks/", propstats))
}

fn parse_changed(ctag: String, body: String) {
  calendar.parse_changed(
    calendar.Calendar(
      href: "/calendars/alice/tasks/",
      name: "Tasks",
      ctag: ctag,
      components: [calendar.VTask],
      color: None,
    ),
    as_response(body),
  )
}

pub fn changed_ctag_test() {
  parse_changed(
    "old",
    changed_body(propstat("200 OK", prop("<cs:getctag>new</cs:getctag>"))),
  )
  |> should.equal(
    Ok(
      calendar.Changed(calendar.Calendar(
        href: "/calendars/alice/tasks/",
        name: "Tasks",
        ctag: "new",
        components: [calendar.VTask],
        color: None,
      )),
    ),
  )
}

/// Only the first response is read when a multistatus carries several.
pub fn changed_uses_the_first_response_test() {
  let body =
    multistatus(
      dav_response(
        "/calendars/alice/tasks/",
        propstat("200 OK", prop("<cs:getctag>tag-a</cs:getctag>")),
      )
      <> dav_response(
        "/calendars/alice/other/",
        propstat("200 OK", prop("<cs:getctag>tag-b</cs:getctag>")),
      ),
    )

  parse_changed("stale", body)
  |> should.equal(
    Ok(
      calendar.Changed(calendar.Calendar(
        href: "/calendars/alice/tasks/",
        name: "Tasks",
        ctag: "tag-a",
        components: [calendar.VTask],
        color: None,
      )),
    ),
  )
}

/// A 404 propstat on the ctag probe fails the decode; it is not read as "no
/// change".
pub fn changed_propstat_404_test() {
  parse_changed(
    "old",
    changed_body(propstat("404 Not Found", prop("<cs:getctag>x</cs:getctag>"))),
  )
  |> should.be_error()
}

/// The element being there but empty is an error: `optional_field` only
/// defaults when the element is absent entirely.
pub fn changed_empty_ctag_element_test() {
  parse_changed("old", changed_body(propstat("200 OK", prop("<cs:getctag/>"))))
  |> should.be_error()
}

/// And an absent getctag is an error too, rather than a successful "no ctag".
pub fn changed_missing_ctag_element_test() {
  parse_changed(
    "old",
    changed_body(propstat("200 OK", prop("<d:displayname>x</d:displayname>"))),
  )
  |> should.be_error()
}

// --- Discovery and principal lookups -----------------------------------------

pub fn user_info_empty_multistatus_test() {
  client.parse_user_info(as_response(
    "<d:multistatus xmlns:d=\"DAV:\"></d:multistatus>",
  ))
  |> should.be_error()
}

/// The principal decoder does not look at the propstat status: a 404 that
/// still carries the element parses all the same.
pub fn user_info_ignores_propstat_status_test() {
  let not_found =
    propstat(
      "404 Not Found",
      prop(
        "<d:current-user-principal><d:href>/me/</d:href></d:current-user-principal>",
      ),
    )
  let body =
    multistatus(dav_response("/", not_found) <> dav_response("/b/", not_found))

  client.parse_user_info(as_response(body))
  |> should.equal(Ok(client.UserInfo("/me/")))
}

/// A multistatus with exactly one response is a plain dict rather than a
/// list; the decoder accepts both shapes, just like its calendar home-set
/// sibling.
pub fn user_info_single_response_test() {
  let body =
    multistatus(dav_response(
      "/",
      propstat(
        "200 OK",
        prop(
          "<d:current-user-principal><d:href>/me/</d:href></d:current-user-principal>",
        ),
      ),
    ))

  client.parse_user_info(as_response(body))
  |> should.equal(Ok(client.UserInfo("/me/")))
}

/// With several responses, only the first one counts.
pub fn user_info_uses_the_first_response_test() {
  let body =
    multistatus(
      dav_response(
        "/",
        propstat(
          "200 OK",
          prop(
            "<d:current-user-principal><d:href>/first/</d:href></d:current-user-principal>",
          ),
        ),
      )
      <> dav_response(
        "/b/",
        propstat(
          "200 OK",
          prop(
            "<d:current-user-principal><d:href>/second/</d:href></d:current-user-principal>",
          ),
        ),
      ),
    )

  client.parse_user_info(as_response(body))
  |> should.equal(Ok(client.UserInfo("/first/")))
}

pub fn user_info_propstat_404_without_principal_test() {
  let not_found =
    propstat("404 Not Found", prop("<d:displayname>anonymous</d:displayname>"))
  let body =
    multistatus(dav_response("/", not_found) <> dav_response("/b/", not_found))

  client.parse_user_info(as_response(body)) |> should.be_error()
}

pub fn calendar_home_set_empty_multistatus_test() {
  client.parse_calendar_home_set(as_response(
    "<d:multistatus xmlns:d=\"DAV:\"></d:multistatus>",
  ))
  |> should.be_error()
}

pub fn calendar_home_set_missing_element_test() {
  let body =
    multistatus(dav_response(
      "/me/",
      propstat("200 OK", prop("<d:displayname>Me</d:displayname>")),
    ))

  client.parse_calendar_home_set(as_response(body)) |> should.be_error()
}

/// Like the principal lookup, the home-set decoder does not check the
/// propstat status: the element alone decides.
pub fn calendar_home_set_ignores_propstat_status_test() {
  let body =
    multistatus(dav_response(
      "/me/",
      propstat(
        "404 Not Found",
        prop(
          "<c:calendar-home-set><c:href>/me/calendars/</c:href></c:calendar-home-set>",
        ),
      ),
    ))

  client.parse_calendar_home_set(as_response(body))
  |> should.equal(Ok(client.CalendarHomeSet("/me/calendars/")))
}
