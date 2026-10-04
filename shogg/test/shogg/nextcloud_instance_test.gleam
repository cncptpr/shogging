//// Parsing the CalDAV responses captured from this project's own Nextcloud
//// instance (`local_*` fixtures, see `dev/nextcloud-capture.sh`).
////
//// Unlike `nextcloud_unit_test.gleam` these go through the shared
//// `shogg/nextcloud_capture` reader, so the raw `.txt` captures are split into
//// status line, headers and body exactly like the app's HTTP client sees
//// them.

import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import shogg/calendar
import shogg/client
import shogg/nextcloud_capture as capture
import shogg/task

pub fn main() {
  gleeunit.main()
}

pub fn parse_server_info_test() {
  let resp = capture.raw("local_server_info.txt")
  resp.status |> should.equal(301)

  let assert Ok(info) = client.parse_server_info(resp)
  info |> should.equal(client.ServerInfo("/remote.php/dav/"))
}

pub fn parse_user_info_test() {
  let assert Ok(info) =
    capture.body("local_user_info.xml") |> client.parse_user_info
  info
  |> should.equal(client.UserInfo("/remote.php/dav/principals/users/shogging/"))
}

pub fn parse_calendar_home_set_test() {
  let assert Ok(home_set) =
    capture.body("local_calendar_home_set.xml")
    |> client.parse_calendar_home_set
  home_set
  |> should.equal(client.CalendarHomeSet("/remote.php/dav/calendars/shogging/"))
}

/// The home PROPFIND answers with eight collections: the calendar home
/// itself, the schedule inbox/outbox, the trash bin and four real calendars.
/// Only the collections with a calendar resource type and full properties
/// make it through.
pub fn parse_calendars_test() {
  let assert Ok(calendars) =
    capture.body("local_calendars.xml") |> calendar.parse_calendars
  calendars |> list.length |> should.equal(4)

  let assert Ok(test_calendar) =
    calendars
    |> list.find(fn(c) { c.name == "Shogging Test" })
  test_calendar.href
  |> should.equal("/remote.php/dav/calendars/shogging/shogging-test/")
  test_calendar.ctag |> should.equal("http://sabre.io/ns/sync/7")
  test_calendar.components |> should.equal([calendar.VTask])
  test_calendar.color |> should.equal(None)

  // The calendars Nextcloud creates by default hold VEVENTs, not VTODOs.
  let assert Ok(personal) =
    calendars
    |> list.find(fn(c) { c.name == "Personal" })
  personal.components |> should.equal([calendar.VEvent])
}

/// The ctag response captured *before* the create/update/delete run carries
/// the same token the calendars listing reported, so nothing changed.
pub fn parse_changed_unchanged_test() {
  let assert Ok(changed) =
    seeded_calendar()
    |> calendar.parse_changed(capture.body("local_calendar_unchanged.xml"))
  changed |> should.equal(calendar.Unchanged)
}

/// Captured *after* the scratch task went in and out again: the calendar's
/// sync token moved on, so `parse_changed` hands back the refreshed calendar.
pub fn parse_changed_changed_test() {
  let assert Ok(calendar.Changed(new_calendar)) =
    seeded_calendar()
    |> calendar.parse_changed(capture.body("local_calendar_changed.xml"))
  new_calendar.ctag |> should.equal("http://sabre.io/ns/sync/10")
  new_calendar.href |> should.equal(seeded_calendar().href)
}

/// The six tasks seeded from `dev/seed/*.ics`, each reported with its etag
/// and calendar data.
pub fn parse_tasks_test() {
  let assert Ok(tasks) = capture.body("local_tasks.xml") |> task.parse_tasks
  tasks |> list.length |> should.equal(6)

  let assert Ok(first) = tasks |> list.first()
  first.uid |> should.not_equal("")
  first.dtstamp |> should.not_equal("")
  first.meta.href |> should.not_equal("")
  first.meta.etag |> should.not_equal("")
}

pub fn parse_tasks_fields_test() {
  let assert Ok(tasks) = capture.body("local_tasks.xml") |> task.parse_tasks

  // RFC 5545 escaping (`\,`) is gone by the time the summary reaches us.
  let assert Ok(groceries) =
    tasks
    |> list.find(fn(t) { t.uid == "shogging-seed-groceries" })
  groceries.summary |> should.equal(Some("Lebensmittel kaufen, Brot und Milch"))

  let assert Ok(desk) =
    tasks
    |> list.find(fn(t) { t.uid == "shogging-seed-desk" })
  desk.status |> should.equal(Some("COMPLETED"))
  desk.summary |> should.equal(Some("Clean up the desk"))
}

/// A REPORT against the second, always-empty calendar still answers 207, just
/// with no responses in it.
pub fn parse_tasks_empty_report_test() {
  let assert Ok(tasks) =
    capture.raw("local_report_empty.txt") |> task.parse_tasks
  tasks |> should.equal([])
}

pub fn parse_create_task_test() {
  let resp = capture.raw("local_create_task.txt")
  resp.status |> should.equal(201)
  let assert Ok(etag) = response.get_header(resp, "etag")
  etag |> should.not_equal("")

  let req =
    request.new()
    |> request.set_path(
      "/remote.php/dav/calendars/shogging/shogging-test/local-capture-task.ics",
    )
  let assert Ok(path) = task.parse_create_task(resp, req)
  path |> should.equal(req.path)
}

pub fn parse_update_task_test() {
  let resp = capture.raw("local_update_task.txt")
  resp.status |> should.equal(204)
  let assert Ok(etag) = response.get_header(resp, "etag")

  let assert Ok(updated) = task.parse_update_task_response(resp, scratch_task())
  updated.meta.etag |> should.equal(etag)
}

/// A PUT with an `If-Match` that no longer matches is refused with 412, which
/// the update parser turns into an error.
pub fn parse_update_stale_etag_test() {
  let resp = capture.raw("local_update_stale_etag.txt")
  resp.status |> should.equal(412)

  task.parse_update_task_response(resp, scratch_task()) |> should.be_error()
}

pub fn parse_delete_task_test() {
  let resp = capture.raw("local_delete_task.txt")
  resp.status |> should.equal(204)

  task.parse_delete_task_response(resp) |> should.be_ok()
}

/// Deleting an object that is not there anymore fails the precondition (the
/// capture still carries the stale `If-Match`), which is not a success for
/// the delete parser.
pub fn parse_delete_missing_task_test() {
  let resp = capture.raw("local_delete_missing.txt")
  resp.status |> should.not_equal(204)

  task.parse_delete_task_response(resp) |> should.be_error()
}

pub fn propfind_missing_calendar_test() {
  let resp = capture.raw("local_propfind_missing.txt")
  resp.status |> should.equal(404)
}

/// The task as it was mid-flight during the capture run.
fn scratch_task() -> task.Task {
  task.Task(
    uid: "local-capture-task",
    dtstamp: "20261004T120000Z",
    created: None,
    last_modified: None,
    status: Some("IN-PROCESS"),
    summary: Some("Local capture task (updated)"),
    completed: None,
    percent_complete: None,
    x_apple_sort_order: None,
    other: [],
    meta: task.TaskMeta(
      href: "/remote.php/dav/calendars/shogging/shogging-test/local-capture-task.ics",
      etag: "\"5979e996b828bb1a7c247ffbc82910c8\"",
    ),
  )
}

/// The seeded task calendar as the calendars listing describes it.
fn seeded_calendar() -> calendar.Calendar {
  let assert Ok(calendars) =
    capture.body("local_calendars.xml") |> calendar.parse_calendars
  let assert Ok(found) =
    calendars
    |> list.find(fn(c) { c.name == "Shogging Test" })
  found
}
