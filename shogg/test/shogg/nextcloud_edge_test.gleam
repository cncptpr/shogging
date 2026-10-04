//// Edge cases exercised against hand-modified `local_*_handmade_*` fixtures.
////
//// The captured responses only show what one instance happened to answer;
//// these variants bend the answers into shapes a server may just as well
//// send: a single `<d:response>` instead of a list, folded and escaped iCal
//// values, a component set with nothing in it, a calendar missing its ctag,
//// and a stray non-VTODO inside a task REPORT.

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

/// One `<d:response>` element instead of several: the decoder has to cope
/// with a single element where a list would normally be expected.
pub fn parse_tasks_single_response_test() {
  let assert Ok(tasks) =
    capture.body("local_tasks_handmade_single.xml") |> task.parse_tasks
  tasks |> list.length |> should.equal(1)

  let assert Ok(found) = tasks |> list.first()
  found.uid |> should.equal("handmade-single")
  found.dtstamp |> should.equal("20261004T090000Z")
  found.status |> should.equal(Some("NEEDS-ACTION"))
  found.summary |> should.equal(Some("Handmade single response"))
  found.meta.href
  |> should.equal(
    "/remote.php/dav/calendars/shogging/shogging-test/handmade-single.ics",
  )
  found.meta.etag |> should.equal("\"handmade-single-etag\"")
}

/// A VTIMEZONE ahead of the todo, a summary folded over two lines, RFC 5545
/// escapes and non-ASCII characters — all of it has to come out the other
/// side as one unescaped summary line.
pub fn parse_tasks_folded_escaped_summary_test() {
  let assert Ok(tasks) =
    capture.body("local_tasks_handmade_escaped.xml") |> task.parse_tasks
  tasks |> list.length |> should.equal(1)

  let assert Ok(found) = tasks |> list.first()
  found.uid |> should.equal("handmade-escaped")
  found.status |> should.equal(Some("COMPLETED"))
  found.percent_complete |> should.equal(Some(100))
  found.x_apple_sort_order |> should.equal(Some(7))
  found.summary
  |> should.equal(Some("Cafe, cream ; and \\ snowman ☃ — actual nice café"))
}

/// The server answered a task REPORT with a VEVENT in the mix; that response
/// is dropped without taking the VTODOs down with it.
pub fn parse_tasks_mixed_components_test() {
  let assert Ok(tasks) =
    capture.body("local_tasks_handmade_mixed.xml") |> task.parse_tasks
  tasks |> list.length |> should.equal(1)

  let assert Ok(found) = tasks |> list.first()
  found.uid |> should.equal("handmade-todo")
  found.summary |> should.equal(Some("The only todo in here"))
}

/// A calendar may declare an empty supported-component-set (a self-closing
/// element with no `<cal:comp/>` children); it still counts as a calendar,
/// just with no components to show.
pub fn parse_calendars_empty_components_test() {
  let assert Ok(calendars) =
    capture.body("local_calendars_handmade_empty_components.xml")
    |> calendar.parse_calendars
  calendars |> list.length |> should.equal(1)

  let assert Ok(found) = calendars |> list.first()
  found.name |> should.equal("Handmade Empty")
  found.ctag |> should.equal("http://sabre.io/ns/sync/42")
  found.components |> should.equal([])
  found.color |> should.equal(None)
}

/// The getctag for the first calendar comes back in a 404 propstat, so the
/// calendar has no ctag and is skipped — the calendar that does have one
/// survives untouched.
pub fn parse_calendars_missing_ctag_test() {
  let assert Ok(calendars) =
    capture.body("local_calendars_handmade_no_ctag.xml")
    |> calendar.parse_calendars
  calendars |> list.length |> should.equal(1)

  let assert Ok(found) = calendars |> list.first()
  found.name |> should.equal("Kept Calendar")
  found.ctag |> should.equal("http://sabre.io/ns/sync/43")
  found.components |> should.equal([calendar.VEvent])
}

/// A PROPFIND answered with exactly one response — here too the single
/// element has to be read as the list of one it stands for.
pub fn parse_user_info_single_response_test() {
  let assert Ok(info) =
    capture.body("local_user_info_handmade_single.xml")
    |> client.parse_user_info
  info
  |> should.equal(client.UserInfo("/remote.php/dav/principals/users/shogging/"))
}

/// The other shape of the same coin: the real home-set capture is a single
/// response, so this multi-response variant is what exercises the decoder's
/// list branch — and the first response is the one that wins.
pub fn parse_calendar_home_set_multiple_responses_test() {
  let assert Ok(home_set) =
    capture.body("local_calendar_home_set_handmade_multi.xml")
    |> client.parse_calendar_home_set
  home_set
  |> should.equal(client.CalendarHomeSet("/remote.php/dav/calendars/shogging/"))
}
