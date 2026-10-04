import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import shogg/calendar
import shogg/capture
import shogg/client
import shogg/task

pub fn main() {
  gleeunit.main()
}

fn read_response(file: String) {
  capture.body(file)
}

pub fn parse_user_info_test() {
  let resp = read_response("user_info.xml")
  let assert Ok(parsed) = client.parse_user_info(resp)

  let user_info =
    client.UserInfo("/caldav/7b8a9e3b-6655-40b8-8080-b89f75a5272a/")

  parsed |> should.equal(user_info)
}

pub fn parse_calendars_test() {
  let resp = read_response("calendars.xml")
  let assert Ok(calendars) = calendar.parse_calendars(resp)
  calendars |> list.length |> should.equal(3)

  let assert Ok(cal) = calendars |> list.first()
  cal.name |> should.not_equal("")
  cal.href |> should.not_equal("")
  cal.ctag |> should.not_equal("")
}

/// The whole listing, calendar by calendar: the principal and the address book
/// Radicale also returned must have been filtered out, and the ctags arrive
/// quoted, exactly as `CS:getctag` sent them.
pub fn parse_calendars_exact_test() {
  let resp = read_response("calendars.xml")
  let assert Ok(calendars) = calendar.parse_calendars(resp)

  calendars
  |> should.equal([
    calendar.Calendar(
      href: "/caldav/7b8a9e3b-6655-40b8-8080-b89f75a5272a/def-calendar/",
      name: "Personal Calendar",
      ctag: "\"60b4c36a27fcf9bfe6c6c3d2904c2ccfd957bceb3f1040d39db59f34a21bf5ab\"",
      components: [calendar.VEvent, calendar.VJournal, calendar.VTask],
      color: None,
    ),
    calendar.Calendar(
      href: "/caldav/7b8a9e3b-6655-40b8-8080-b89f75a5272a/17F84AF3-92D3-4DDA-BBF6-E1424C2EFCA5/",
      name: "Terminplan Studium",
      ctag: "\"805bccfbe0c36113d751ba9380c791b0086b7f7e07af6fd64b4defac719f0b0f\"",
      components: [calendar.VEvent],
      color: None,
    ),
    calendar.Calendar(
      href: "/caldav/7b8a9e3b-6655-40b8-8080-b89f75a5272a/64FB220B-118F-4DB6-B232-CFF0F69C9DCC/",
      name: "Shogging Dev",
      ctag: "\"3faaac8d428bd5faf1a21d961f8bff64e482ac7da28c3638b9437ca6db205a9e\"",
      components: [calendar.VEvent],
      color: None,
    ),
  ])
}

/// Neither the principal (`/caldav/<uuid>/`) nor the CardDAV address book may
/// survive into the task-app's calendar list.
pub fn parse_calendars_filters_non_calendars_test() {
  let resp = read_response("calendars.xml")
  let assert Ok(calendars) = calendar.parse_calendars(resp)

  let hrefs = calendars |> list.map(fn(cal) { cal.href })
  hrefs
  |> should.equal([
    "/caldav/7b8a9e3b-6655-40b8-8080-b89f75a5272a/def-calendar/",
    "/caldav/7b8a9e3b-6655-40b8-8080-b89f75a5272a/17F84AF3-92D3-4DDA-BBF6-E1424C2EFCA5/",
    "/caldav/7b8a9e3b-6655-40b8-8080-b89f75a5272a/64FB220B-118F-4DB6-B232-CFF0F69C9DCC/",
  ])
}

pub fn parse_tasks_test() {
  let resp = read_response("tasks.xml")
  let assert Ok(tasks) = task.parse_tasks(resp)
  tasks |> should.not_equal([])

  let assert Ok(item) = tasks |> list.first()
  item.uid |> should.not_equal("")
  item.dtstamp |> should.not_equal("")
}

/// Radicale answered with 14 VTODOs; every one of them must parse, not just
/// the first.
pub fn parse_tasks_count_test() {
  let resp = read_response("tasks.xml")
  let assert Ok(tasks) = task.parse_tasks(resp)
  tasks |> list.length |> should.equal(14)
}

/// The first task in the capture, field by field. Note the summary: the ical
/// source has `SUMMARY:Hello\, World!` and the escaped comma must come out as
/// a plain one.
pub fn parse_tasks_first_task_exact_test() {
  let resp = read_response("tasks.xml")
  let assert Ok(tasks) = task.parse_tasks(resp)
  let assert Ok(first) = tasks |> list.first()

  first
  |> should.equal(task.Task(
    uid: "bbd2394d-47e0-4ff7-956f-0f5fb897225b",
    dtstamp: "20260316T162812Z",
    created: Some("20260314T103533Z"),
    last_modified: Some("20260316T162811Z"),
    status: Some("COMPLETED"),
    summary: Some("Hello, World!"),
    completed: Some("20260316T191426Z"),
    percent_complete: None,
    x_apple_sort_order: None,
    other: [],
    meta: task.TaskMeta(
      href: "/caldav/7b8a9e3b-6655-40b8-8080-b89f75a5272a/def-calendar/bbd2394d-47e0-4ff7-956f-0f5fb897225b.ics",
      etag: "\"c4f00cc32aeaf259fcdae95379c9e5cf1331daa3c11c3395fad96afb38a8f754\"",
    ),
  ))
}

/// All summaries in response order, including the ones with non-ASCII letters.
pub fn parse_tasks_summaries_test() {
  let resp = read_response("tasks.xml")
  let assert Ok(tasks) = task.parse_tasks(resp)

  let summaries =
    tasks
    |> list.map(fn(t) { option.unwrap(t.summary, or: "") })

  summaries
  |> should.equal([
    "Hello, World!",
    "Kartoffel",
    "Shiny Things!",
    "Oliven Öl",
    "Spühlmittel",
    "Zucchini",
    "BBQ",
    "Hullo!",
    "Oh wow!!!",
    "A",
    "Karotte",
    "Ei",
    "Topfdeckel",
    "2x Erbsen",
  ])
}

/// `X-APPLE-SORT-ORDER` is modelled, so it must not leak into `other`.
pub fn parse_tasks_apple_sort_order_test() {
  let resp = read_response("tasks.xml")
  let assert Ok(tasks) = task.parse_tasks(resp)

  let assert Ok(found) = tasks |> list.find(fn(t) { t.uid == "mm9dbyia.tuu" })
  found.x_apple_sort_order |> should.equal(Some(794_160_833))
  found.summary |> should.equal(Some("Oliven Öl"))
  found.other |> should.equal([])
}

pub fn parse_changed_empty_test() {
  let body =
    "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<multistatus xmlns=\"DAV:\">\n</multistatus>"
  let cal =
    calendar.Calendar(
      href: "/caldav/user/calendar/",
      name: "Test",
      ctag: "12345abc",
      components: [],
      color: None,
    )
  let resp = response.Response(status: 207, headers: [], body:)
  calendar.parse_changed(cal, resp) |> should.be_error()
}

// --- Responses captured from this project's Radicale -------------------------

pub fn parse_user_info_seeded_test() {
  let resp = read_response("user_info_seeded.xml")
  client.parse_user_info(resp)
  |> should.equal(Ok(client.UserInfo("/shogging/")))
}

pub fn parse_calendar_home_set_seeded_test() {
  let resp = read_response("calendar_home_set_seeded.xml")
  client.parse_calendar_home_set(resp)
  |> should.equal(Ok(client.CalendarHomeSet("/shogging/")))
}

pub fn parse_calendar_home_set_from_original_capture_test() {
  let resp = read_response("calendar_home_set.xml")
  client.parse_calendar_home_set(resp)
  |> should.equal(
    Ok(client.CalendarHomeSet("/caldav/7b8a9e3b-6655-40b8-8080-b89f75a5272a/")),
  )
}

/// The seeded home set holds exactly one calendar; the principal response in
/// front of it is not one.
pub fn parse_calendars_seeded_test() {
  let resp = read_response("calendars_seeded.xml")
  let assert Ok(calendars) = calendar.parse_calendars(resp)

  calendars
  |> should.equal([
    calendar.Calendar(
      href: "/shogging/shogging-test/",
      name: "Shogging Test",
      ctag: "\"b9d4844e90c5fb19f6fb7c02ea0de967d18f174a43b729ab3d8d2b77d45eead2\"",
      components: [calendar.VTask],
      color: None,
    ),
  ])
}

pub fn parse_tasks_seeded_count_test() {
  let resp = read_response("tasks_seeded.xml")
  let assert Ok(tasks) = task.parse_tasks(resp)
  tasks |> list.length |> should.equal(6)
}

/// `SUMMARY:Lebensmittel kaufen\, Brot und Milch` must be unescaped, and the
/// unmodelled `DUE` must be kept under `other`.
pub fn parse_tasks_seeded_unescaped_summary_test() {
  let resp = read_response("tasks_seeded.xml")
  let assert Ok(tasks) = task.parse_tasks(resp)

  let assert Ok(found) =
    tasks |> list.find(fn(t) { t.uid == "shogging-seed-groceries" })
  found.summary
  |> should.equal(Some("Lebensmittel kaufen, Brot und Milch"))
  found.status |> should.equal(Some("NEEDS-ACTION"))
  found.other |> should.equal([#("DUE", "20261004T170000Z")])
}

pub fn parse_tasks_seeded_percent_complete_test() {
  let resp = read_response("tasks_seeded.xml")
  let assert Ok(tasks) = task.parse_tasks(resp)

  let assert Ok(found) =
    tasks |> list.find(fn(t) { t.uid == "shogging-seed-invoice" })
  found.percent_complete |> should.equal(Some(50))
  found.status |> should.equal(Some("IN-PROCESS"))
  found.summary |> should.equal(Some("Pay electricity invoice"))
  found.other |> should.equal([#("DUE", "20260930T120000Z")])
}

/// The completed seed tasks carry both `STATUS:COMPLETED` and `COMPLETED:`.
pub fn parse_tasks_seeded_completed_test() {
  let resp = read_response("tasks_seeded.xml")
  let assert Ok(tasks) = task.parse_tasks(resp)

  let assert Ok(found) =
    tasks |> list.find(fn(t) { t.uid == "shogging-seed-desk" })
  found.status |> should.equal(Some("COMPLETED"))
  found.completed |> should.equal(Some("20260928T180000Z"))
  task.is_competed(found) |> should.be_true()
  found.other |> should.equal([])
}

/// A task without a `DUE` keeps nothing in `other`.
pub fn parse_tasks_seeded_readme_test() {
  let resp = read_response("tasks_seeded.xml")
  let assert Ok(tasks) = task.parse_tasks(resp)

  let assert Ok(found) =
    tasks |> list.find(fn(t) { t.uid == "shogging-seed-readme" })
  found.summary |> should.equal(Some("Tippfehler im README korrigieren"))
  found.other |> should.equal([])
}

/// The ctag in the change probe matches the one from the calendar listing, so
/// nothing has changed.
pub fn parse_changed_seeded_unchanged_test() {
  let calendars_resp = read_response("calendars_seeded.xml")
  let assert Ok([cal]) = calendar.parse_calendars(calendars_resp)

  let changed_resp = read_response("calendar_changed_seeded.xml")
  calendar.parse_changed(cal, changed_resp)
  |> should.equal(Ok(calendar.Unchanged))
}

/// The same probe, but against a calendar that has a stale ctag: the response
/// must come back as changed, carrying the ctag Radicale sent.
pub fn parse_changed_seeded_changed_test() {
  let calendars_resp = read_response("calendars_seeded.xml")
  let assert Ok([cal]) = calendar.parse_calendars(calendars_resp)
  let stale = calendar.Calendar(..cal, ctag: "stale")

  let changed_resp = read_response("calendar_changed_seeded.xml")
  calendar.parse_changed(stale, changed_resp)
  |> should.equal(Ok(calendar.Changed(cal)))
}

/// Radicale answers a REPORT against an empty calendar with a self-closing
/// multistatus — no `<response>` at all — which is zero tasks, not an error.
pub fn parse_tasks_empty_calendar_test() {
  let resp = capture.raw("report_empty_calendar.txt")
  resp.status |> should.equal(207)
  task.parse_tasks(resp) |> should.equal(Ok([]))
}

/// A 404 PROPFIND comes back as plain text, not XML.
pub fn parse_calendars_from_404_body_test() {
  let resp = capture.raw("propfind_missing.txt")
  resp.status |> should.equal(404)
  calendar.parse_calendars(resp) |> should.be_error()
}

// --- Raw status/header captures ----------------------------------------------

/// The discovery request Radicale answers with a bare `301` and a relative
/// `Location: /` (header names lowercased as the HTTP client delivers them).
pub fn parse_server_info_redirect_test() {
  let resp = capture.raw("server_info_redirect.txt")
  resp.status |> should.equal(301)
  client.parse_server_info(resp)
  |> should.equal(Ok(client.ServerInfo("/")))
}

pub fn parse_create_task_response_seeded_test() {
  let resp = capture.raw("create_task_response.txt")
  resp.status |> should.equal(201)
  let req =
    request.new()
    |> request.set_path("/shogging/shogging-test/shogg-capture-create.ics")

  task.parse_create_task(resp, req)
  |> should.equal(Ok("/shogging/shogging-test/shogg-capture-create.ics"))
}

/// A successful Radicale PUT answers `204` with the new `ETag`.
pub fn parse_update_task_response_seeded_test() {
  let resp = capture.raw("update_task_response.txt")
  resp.status |> should.equal(204)

  let original =
    task.Task(
      uid: "shogg-capture-create",
      dtstamp: "20261004T100000Z",
      created: Some("20261004T100000Z"),
      last_modified: None,
      status: Some("COMPLETED"),
      summary: Some("Captured create"),
      completed: None,
      percent_complete: None,
      x_apple_sort_order: None,
      other: [],
      meta: task.TaskMeta(
        href: "/shogging/shogging-test/shogg-capture-create.ics",
        etag: "\"430f883e32ede948585489328de6329d7a3df046cfeb93b84b24e97f6b2cd21b\"",
      ),
    )

  task.parse_update_task_response(resp, original)
  |> should.equal(Ok(
    task.Task(
      ..original,
      meta: task.TaskMeta(
        href: "/shogging/shogging-test/shogg-capture-create.ics",
        etag: "\"9a18007c5d6a71c43db5f92c98f12e7c29a598e72a8406921908103efe0ab9e5\"",
      ),
    ),
  ))
}

/// A PUT with a stale `If-Match` gets a `412` from Radicale.
pub fn parse_update_task_response_stale_etag_test() {
  let resp = capture.raw("update_stale_etag.txt")
  resp.status |> should.equal(412)
  task.parse_update_task_response(
    resp,
    task.Task(
      uid: "",
      dtstamp: "",
      created: None,
      last_modified: None,
      status: None,
      summary: None,
      completed: None,
      percent_complete: None,
      x_apple_sort_order: None,
      other: [],
      meta: task.TaskMeta(href: "", etag: ""),
    ),
  )
  |> should.be_error()
}

/// Radicale answers a successful DELETE with `200 OK`, not the `204` the spec
/// suggests.
pub fn parse_delete_task_response_seeded_test() {
  let resp = capture.raw("delete_task_response.txt")
  resp.status |> should.equal(200)
  task.parse_delete_task_response(resp) |> should.equal(Ok(Nil))
}

pub fn parse_delete_task_response_missing_test() {
  let resp = capture.raw("delete_missing.txt")
  resp.status |> should.equal(404)
  task.parse_delete_task_response(resp) |> should.be_error()
}
