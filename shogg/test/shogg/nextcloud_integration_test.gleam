//// Round trip against the live Nextcloud of the `nextcloud` devenv profile,
//// covering the whole path shogg walks: discover the DAV endpoint, find the
//// principal, the calendar home and the calendars, read the tasks, then
//// create, update, re-read, refuse a stale write and delete a task again.
////
//// The instance is not required for `gleam test`: when nothing answers on
//// `NEXTCLOUD_HOST` (default `http://127.0.0.1:8081`) the test prints a
//// notice and passes. To run it for real:
////
////     devenv --profile nextcloud tasks run nextcloud:seed
////     devenv --profile nextcloud up
////     gleam test

import envoy
import gleam/hackney
import gleam/io
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import gleam/time/timestamp
import gleeunit
import gleeunit/should
import shogg.{type ShoggError, SendError}
import shogg/calendar
import shogg/client
import shogg/task

pub fn main() {
  gleeunit.main()
}

/// The uid of the task the lifecycle creates. A leftover from an interrupted
/// run carries the same uid and is removed before the assertions start.
const task_uid = "shogg-integration-test"

pub fn nextcloud_full_path_test() {
  let host =
    envoy.get("NEXTCLOUD_HOST") |> result.unwrap("http://127.0.0.1:8081")
  let username = envoy.get("NEXTCLOUD_USERNAME") |> result.unwrap("shogging")
  let password = envoy.get("NEXTCLOUD_PASSWORD") |> result.unwrap("shogging")

  // The scheme follows the host: an explicit "http://" prefix selects plain
  // HTTP (the local dev server), anything else is HTTPS.
  let #(scheme, base_host) = case string.split_once(host, "://") {
    Ok(#("http", rest)) -> #(client.http, rest)
    Ok(#("https", rest)) -> #(client.https, rest)
    _ -> #(client.https, host)
  }

  let c =
    client.new_client(scheme, host: base_host, username:, password:)
    |> client.set_io(hackney.send)

  case client.fetch_server_info(c) {
    // Connection refused: no instance is running, nothing to integrate with.
    Error(SendError(_)) ->
      io.println(
        "Nextcloud is not reachable at "
        <> host
        <> " — skipping the integration test (start it with `devenv --profile nextcloud up`)",
      )
    discovered -> full_path(c, discovered)
  }
}

fn full_path(
  c: client.Client(client.IO(e)),
  discovered: Result(client.ServerInfo, ShoggError(e)),
) -> Nil {
  let assert Ok(server) = discovered

  // Discovery: current user principal, then that principal's calendar home,
  // then everything in it.
  let assert Ok(info) = client.fetch_user_info(c, server)
  let assert Ok(home_set) = client.fetch_calendar_home_set(c, info)
  let assert Ok(calendars) = calendar.fetch_calendars(c, home_set)

  // Find both calendars this test cares about.
  let assert Ok(test_cal) =
    list.find(calendars, fn(cal) { cal.name == "Shogging Test" })
  case list.find(calendars, fn(cal) { cal.name == "Shogging Empty" }) {
    Error(Nil) ->
      io.println(
        "nextcloud integration: the Shogging Empty calendar is missing — "
        <> "seed with `devenv --profile nextcloud tasks run nextcloud:seed`, skipping",
      )
    Ok(empty_cal) -> lifecycle(c, empty_cal, test_cal)
  }
}

fn lifecycle(
  c: client.Client(client.IO(e)),
  empty_cal: calendar.Calendar,
  test_cal: calendar.Calendar,
) -> Nil {
  // A calendar fetched moments ago agrees with its own ctag response.
  let assert Ok(calendar.Unchanged) = calendar.has_changed(c, empty_cal)

  // Read: the seeded calendar holds tasks, the empty one holds none yet.
  let assert Ok(seeded_tasks) = task.fetch_tasks(c, test_cal)
  list.is_empty(seeded_tasks) |> should.equal(False)
  let assert Ok(current) = task.fetch_tasks(c, empty_cal)

  // Remove the task of an interrupted previous run, if there is one.
  list.each(list.filter(current, fn(t) { t.uid == task_uid }), fn(left) {
    let _ = task.send_delete_task(c, left)
    Nil
  })
  let assert Ok(before) = task.fetch_tasks(c, empty_cal)
  let assert [] = before

  // Create: a PUT with If-None-Match: * answers 201 with the new object's
  // path, and the task comes back from the next REPORT with that href.
  let create_request =
    task.create_task_request_with(
      c,
      empty_cal,
      "Integration task",
      task_uid,
      timestamp.system_time(),
    )
  let assert Ok(create_response) = create_request |> c.io.send
  let assert Ok(created_path) =
    task.parse_create_task(create_response, create_request)

  let assert Ok(after_create) = task.fetch_tasks(c, empty_cal)
  let assert Ok(created) = list.find(after_create, fn(t) { t.uid == task_uid })
  created.meta.href |> should.equal(created_path)
  created.summary |> should.equal(Some("Integration task"))
  created.status |> should.equal(Some("NEEDS-ACTION"))

  // Update: rewrite it with the etag the read just returned.
  let assert Ok(updated) =
    task.send_update_task(
      c,
      task.Task(..created, summary: Some("Integration task updated")),
    )
  updated.meta.etag |> should.not_equal(created.meta.etag)

  // The superseded etag must not be able to write any more.
  task.send_update_task(c, task.Task(..created, summary: Some("Stale write")))
  |> should.be_error()

  // Read again: the update landed and the etag matches what we hold.
  let assert Ok(after_update) = task.fetch_tasks(c, empty_cal)
  let assert Ok(refetched) =
    list.find(after_update, fn(t) { t.uid == task_uid })
  refetched.summary |> should.equal(Some("Integration task updated"))
  refetched.meta.etag |> should.equal(updated.meta.etag)

  // The writes moved the calendar's sync token on.
  let assert Ok(calendar.Changed(changed)) = calendar.has_changed(c, empty_cal)
  changed.ctag |> should.not_equal(empty_cal.ctag)

  // Delete with the current etag, then the task is gone.
  let assert Ok(Nil) = task.send_delete_task(c, updated)
  let assert Ok(after_delete) = task.fetch_tasks(c, empty_cal)
  let assert Error(Nil) = list.find(after_delete, fn(t) { t.uid == task_uid })

  io.println("nextcloud integration: full path OK (create → update → delete)")
}
