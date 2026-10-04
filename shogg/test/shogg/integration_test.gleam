//// Integration tests: the whole shogg library talking to a real Radicale.
////
//// shogg is IO-agnostic by design, so these tests supply the `SendFn`
//// themselves, via `gleam_hackney` (a dev-dependency). The tests only run when
//// `SHOGG_INTEGRATION=1` is set; the devenv task
//// `shogg:integration-test` seeds the storage, starts Radicale, sets the
//// variable and tears everything down again. Without it they print a skip
//// note and pass, so plain `gleam test` keeps working with no server.

import envoy
import gleam/hackney
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import gleam/time/timestamp
import gleeunit
import gleeunit/should
import shogg
import shogg/calendar
import shogg/client
import shogg/task

pub fn main() {
  gleeunit.main()
}

const integration_env = "SHOGG_INTEGRATION"

/// The six tasks committed under dev/seed/collection-root/.
const seed_uids = [
  "shogging-seed-desk",
  "shogging-seed-groceries",
  "shogging-seed-insurance",
  "shogging-seed-invoice",
  "shogging-seed-presentation",
  "shogging-seed-readme",
]

/// Fixed uid for the task this suite creates and deletes again, so the suite
/// is re-runnable even after a crashed run left it behind.
const probe_uid = "shogg-integration-probe"

/// Runs the test body, or prints a skip note when the integration flag is off.
fn maybe(name: String, body: fn() -> Nil) -> Nil {
  case envoy.get(integration_env) {
    Ok(value) if value != "" && value != "0" -> body()
    _ ->
      io.println(
        "skipped "
        <> name
        <> ": set "
        <> integration_env
        <> "=1 (run via `devenv tasks run shogg:integration-test`)",
      )
  }
}

/// A real HTTP SendFn on top of hackney: custom methods like PROPFIND and
/// REPORT are passed through untouched, and response headers come back
/// lowercased — exactly what the parsers expect.
fn send(
  req: request.Request(String),
) -> Result(response.Response(String), hackney.Error) {
  hackney.send(req)
}

/// Run a raw request through the client's SendFn, the same way the library's
/// own fetch functions do (`request |> client.io.send`).
fn io_send(
  req: request.Request(String),
  c: client.Client(client.IO(e)),
) -> Result(response.Response(String), e) {
  let client.IO(send_fn) = c.io
  send_fn(req)
}

/// Build a client from the CALDAV_* environment the devenv file exports.
fn connect() -> client.Client(client.IO(hackney.Error)) {
  let assert Ok(host_url) = envoy.get("CALDAV_HOST")
  let assert Ok(username) = envoy.get("CALDAV_USERNAME")
  let assert Ok(password) = envoy.get("CALDAV_PASSWORD")

  let #(scheme, hostport) = case string.split_once(host_url, "://") {
    Ok(parts) -> parts
    Error(Nil) -> #("http", host_url)
  }
  let scheme = case scheme {
    "https" -> client.https
    _ -> client.http
  }
  let #(host, port) = case string.split_once(hostport, ":") {
    Ok(#(host, port)) -> #(host, int.parse(port))
    Error(Nil) -> #(hostport, Error(Nil))
  }

  // new_client has no port argument, but Client.request is public.
  let base = client.new_client(scheme, host:, username:, password:)
  let with_port = case port {
    Ok(port) ->
      client.Client(..base, request: request.set_port(base.request, port))
    Error(Nil) -> base
  }
  client.set_io(with_port, send)
}

/// The discovery flow every CalDAV session starts with: redirect, principal,
/// calendar home set.
fn discover(
  c: client.Client(client.IO(hackney.Error)),
) -> Result(client.CalendarHomeSet, shogg.ShoggError(hackney.Error)) {
  use server <- result.try(client.fetch_server_info(c))
  use user <- result.try(client.fetch_user_info(c, server))
  client.fetch_calendar_home_set(c, user)
}

fn find_calendar(
  calendars: List(calendar.Calendar),
  name: String,
) -> Result(calendar.Calendar, Nil) {
  list.find(calendars, fn(cal) { cal.name == name })
}

fn find_task(tasks: List(task.Task), uid: String) -> Result(task.Task, Nil) {
  list.find(tasks, fn(t) { t.uid == uid })
}

/// Delete a probe left behind by a previous (crashed) run, if any.
fn remove_probe(c: client.Client(client.IO(hackney.Error)), tasks) -> Nil {
  case find_task(tasks, probe_uid) {
    Error(Nil) -> Nil
    Ok(leftover) -> {
      let assert Ok(_) = task.delete_task_request(c, leftover) |> io_send(c)
      Nil
    }
  }
}

/// Radicale's discovery endpoint answers with a real 301 + Location, which
/// `parse_server_info` must turn into the base path — then principal and
/// home set resolve to the seeded user's paths.
pub fn discovery_flow_test() {
  maybe("discovery_flow_test", fn() {
    let client = connect()

    let assert Ok(server) = client.fetch_server_info(client)
    server |> should.equal(client.ServerInfo("/"))

    let assert Ok(user) = client.fetch_user_info(client, server)
    user |> should.equal(client.UserInfo("/shogging/"))

    let assert Ok(home) = client.fetch_calendar_home_set(client, user)
    home |> should.equal(client.CalendarHomeSet("/shogging/"))
  })
}

/// List the seeded calendar and read every seeded task back through a real
/// REPORT round trip.
pub fn list_calendars_and_tasks_test() {
  maybe("list_calendars_and_tasks_test", fn() {
    let client = connect()
    let assert Ok(home) = discover(client)

    let assert Ok(calendars) = calendar.fetch_calendars(client, home)
    let assert Ok(cal) = find_calendar(calendars, "Shogging Test")
    cal.href |> should.equal("/shogging/shogging-test/")
    cal.components |> should.equal([calendar.VTask])
    // Radicale quotes the ctag value.
    cal.ctag |> string.starts_with("\"") |> should.be_true()

    let assert Ok(tasks) = task.fetch_tasks(client, cal)
    let uids = list.map(tasks, fn(t) { t.uid })
    list.filter(seed_uids, fn(uid) { !list.contains(uids, uid) })
    |> should.equal([])

    let assert Ok(groceries) = find_task(tasks, "shogging-seed-groceries")
    groceries.summary
    |> should.equal(Some("Lebensmittel kaufen, Brot und Milch"))
    groceries.other |> should.equal([#("DUE", "20261004T170000Z")])

    let assert Ok(invoice) = find_task(tasks, "shogging-seed-invoice")
    invoice.summary |> should.equal(Some("Pay electricity invoice"))
    invoice.status |> should.equal(Some("IN-PROCESS"))
    invoice.percent_complete |> should.equal(Some(50))
  })
}

/// The full lifecycle: create a task, see the collection ctag change, update
/// the task, see the change, delete it, and fail to delete it twice. Only the
/// probe task is touched; the seed data stays as it is.
pub fn task_lifecycle_test() {
  maybe("task_lifecycle_test", fn() {
    let client = connect()
    let assert Ok(home) = discover(client)
    let assert Ok(calendars) = calendar.fetch_calendars(client, home)
    let assert Ok(cal) = find_calendar(calendars, "Shogging Test")

    let assert Ok(before) = task.fetch_tasks(client, cal)
    remove_probe(client, before)

    // Create -------------------------------------------------------------
    let create_request =
      task.create_task_request_with(
        client,
        cal,
        "Integration probe",
        probe_uid,
        timestamp.from_unix_seconds(0),
      )
    let assert Ok(create_response) = io_send(create_request, client)
    create_response.status |> should.equal(201)
    let assert Ok(href) =
      task.parse_create_task(create_response, create_request)
    href |> should.equal(cal.href <> probe_uid <> ".ics")

    // The ctag fetched before the create must now be stale.
    let assert Ok(changed_response) =
      calendar.changed_request(client, cal) |> io_send(client)
    let assert Ok(calendar.Changed(after_create)) =
      calendar.parse_changed(cal, changed_response)
    after_create.ctag |> should.not_equal(cal.ctag)

    // The new task shows up in the listing -------------------------------
    let assert Ok(tasks) = task.fetch_tasks(client, cal)
    let assert Ok(probe) = find_task(tasks, probe_uid)
    probe.summary |> should.equal(Some("Integration probe"))
    probe.meta.href |> should.equal(cal.href <> probe_uid <> ".ics")
    probe.meta.etag |> should.not_equal("")

    // Update -------------------------------------------------------------
    let updated = task.Task(..probe, summary: Some("Integration probe updated"))
    let assert Ok(update_response) =
      task.update_task_request(client, updated) |> io_send(client)
    update_response.status |> should.equal(204)
    let assert Ok(with_new_etag) =
      task.parse_update_task_response(update_response, updated)
    with_new_etag.meta.etag |> should.not_equal(probe.meta.etag)

    let assert Ok(after_update) = task.fetch_tasks(client, cal)
    let assert Ok(probe2) = find_task(after_update, probe_uid)
    probe2.summary |> should.equal(Some("Integration probe updated"))
    probe2.meta.etag |> should.equal(with_new_etag.meta.etag)

    // A ctag fetched after both mutations reports no further change.
    let assert Ok(fresh_calendars) = calendar.fetch_calendars(client, home)
    let assert Ok(fresh) = find_calendar(fresh_calendars, "Shogging Test")
    let assert Ok(unchanged_response) =
      calendar.changed_request(client, fresh) |> io_send(client)
    calendar.parse_changed(fresh, unchanged_response)
    |> should.equal(Ok(calendar.Unchanged))

    // Delete -------------------------------------------------------------
    let assert Ok(delete_response) =
      task.delete_task_request(client, probe2) |> io_send(client)
    task.parse_delete_task_response(delete_response) |> should.equal(Ok(Nil))

    let assert Ok(final_tasks) = task.fetch_tasks(client, cal)
    find_task(final_tasks, probe_uid) |> should.be_error()

    // Deleting the gone task again fails with 404.
    let assert Ok(gone_response) =
      task.delete_task_request(client, probe2) |> io_send(client)
    gone_response.status |> should.equal(404)
    task.parse_delete_task_response(gone_response) |> should.be_error()
    Nil
  })
}
