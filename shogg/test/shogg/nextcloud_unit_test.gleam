import gleam/http/response
import gleam/list
import gleam/option.{None}
import gleeunit
import gleeunit/should
import shogg/calendar
import shogg/client
import shogg/task
import simplifile

pub fn main() {
  gleeunit.main()
}

const responses_path = "test/shogg/responses/nextcloud/"

fn read_response(file: String) {
  let assert Ok(body) = simplifile.read(responses_path <> file)
  response.Response(status: 0, headers: [], body:)
}

pub fn parse_user_info_test() {
  let resp = read_response("user_info.xml")
  let assert Ok(parsed) = client.parse_user_info(resp)

  let user_info = client.UserInfo("/remote.php/dav/principals/users/grt34222/")

  parsed |> should.equal(user_info)
}

pub fn parse_calendar_home_set_test() {
  let resp = read_response("calendar_home_set.xml")
  let assert Ok(parsed) = client.parse_calendar_home_set(resp)

  let home_set = client.CalendarHomeSet("/remote.php/dav/calendars/grt34222/")

  parsed |> should.equal(home_set)
}

pub fn parse_calendars_test() {
  let resp = read_response("calendars.xml")
  let assert Ok(calendars) = calendar.parse_calendars(resp)
  calendars |> list.length |> should.equal(5)

  let assert Ok(cal) = calendars |> list.first()
  cal.name |> should.not_equal("")
  cal.href |> should.not_equal("")
  cal.ctag |> should.not_equal("")
}

pub fn parse_tasks_test() {
  let resp = read_response("tasks.xml")
  let assert Ok(tasks) = task.parse_tasks(resp)
  tasks |> should.equal([])
}

pub fn parse_changed_empty_test() {
  let body =
    "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<multistatus xmlns=\"DAV:\">\n</multistatus>"
  let cal =
    calendar.Calendar(
      href: "/remote.php/dav/calendars/user/calendar/",
      name: "Test",
      ctag: "12345abc",
      components: [],
      color: None,
    )
  let resp = response.Response(status: 207, headers: [], body:)
  calendar.parse_changed(cal, resp) |> should.be_error()
}
