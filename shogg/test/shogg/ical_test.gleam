import gleam/option.{None, Some}
import gleam/result
import gleeunit/should
import shogg/task.{type Task, Task, TaskMeta}

/// Tests for the iCalendar parser in `task.gleam`.
///
/// These are all things a real CalDAV server sends: a timezone block ahead of
/// the todo, lines folded at 75 octets, and parameters on a property name. The
/// parser is the least RFC 5545 conformant part of shogg, so each of these is a
/// case where valid data used to be misread.
fn parse(ical: String) -> Result(Task, String) {
  task.parse_ical(#(TaskMeta(href: "/tasks/1.ics", etag: "\"1\""), ical))
}

fn summary_of(outcome: Result(Task, String)) -> Result(String, String) {
  result.try(outcome, fn(parsed) {
    case parsed.summary {
      Some(summary) -> Ok(summary)
      None -> Error("no summary")
    }
  })
}

fn vcalendar(contents: String) -> String {
  "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n"
  <> contents
  <> "END:VCALENDAR\r\n"
}

pub fn plain_todo_test() {
  let ical =
    vcalendar("BEGIN:VTODO\r\nUID:1\r\nSUMMARY:Buy milk\r\nEND:VTODO\r\n")

  parse(ical) |> summary_of |> should.equal(Ok("Buy milk"))
}

/// A VTIMEZONE before the VTODO, which is how most servers order it. The
/// timezone block is not part of the todo and must be stepped over rather than
/// treated as a parse failure.
pub fn timezone_before_todo_test() {
  let ical =
    vcalendar(
      "BEGIN:VTIMEZONE\r\nTZID:Europe/Berlin\r\n"
      <> "BEGIN:DAYLIGHT\r\nTZOFFSETFROM:+0100\r\nTZOFFSETTO:+0200\r\n"
      <> "DTSTART:19700329T020000\r\nEND:DAYLIGHT\r\n"
      <> "END:VTIMEZONE\r\n",
    )
    <> "BEGIN:VTODO\r\nUID:1\r\nSUMMARY:Buy milk\r\nEND:VTODO\r\n"

  parse(ical) |> summary_of |> should.equal(Ok("Buy milk"))
}

/// A VTIMEZONE after the todo, which already worked.
pub fn timezone_after_todo_test() {
  let ical =
    vcalendar("BEGIN:VTODO\r\nUID:1\r\nSUMMARY:Buy milk\r\nEND:VTODO\r\n")
    <> "BEGIN:VTIMEZONE\r\nTZID:Europe/Berlin\r\nEND:VTIMEZONE\r\n"

  parse(ical) |> summary_of |> should.equal(Ok("Buy milk"))
}

/// RFC 5545 folds long lines at 75 octets, continuing with a single leading
/// space. Unfolding joins them back into one value.
pub fn folded_summary_test() {
  let ical =
    vcalendar(
      "BEGIN:VTODO\r\nUID:1\r\n"
      <> "SUMMARY:This is a very long summary that has been\r\n"
      <> "  folded across lines\r\n"
      <> "END:VTODO\r\n",
    )

  parse(ical)
  |> summary_of
  |> should.equal(Ok(
    "This is a very long summary that has been folded across lines",
  ))
}

/// A folded value must not be mistaken for a property of its own.
pub fn folded_value_is_not_a_property_test() {
  let ical =
    vcalendar(
      "BEGIN:VTODO\r\nUID:1\r\n"
      <> "DESCRIPTION:line one\r\n"
      <> "  line two\r\n"
      <> "END:VTODO\r\n",
    )

  let assert Ok(parsed) = parse(ical)
  parsed.uid |> should.equal("1")
}

/// Properties carry parameters, so the name before the colon is not always a
/// bare `SUMMARY`. The parameters are not interesting here and are dropped.
pub fn parameterised_summary_test() {
  let ical =
    vcalendar(
      "BEGIN:VTODO\r\nUID:1\r\nSUMMARY;LANGUAGE=en:Buy milk\r\nEND:VTODO\r\n",
    )

  parse(ical) |> summary_of |> should.equal(Ok("Buy milk"))
}

/// Parameters and folding together, which is how a long translated summary
/// usually arrives.
pub fn parameterised_folded_summary_test() {
  let ical =
    vcalendar(
      "BEGIN:VTODO\r\nUID:1\r\n"
      <> "SUMMARY;LANGUAGE=en:This is a very long summary that\r\n"
      <> "  has been folded\r\n"
      <> "END:VTODO\r\n",
    )

  parse(ical)
  |> summary_of
  |> should.equal(Ok("This is a very long summary that has been folded"))
}

/// A folded value whose continuation contains a colon, so that unfolding has to
/// happen before the name is split off.
pub fn folded_value_containing_colon_test() {
  let ical =
    vcalendar(
      "BEGIN:VTODO\r\nUID:1\r\n"
      <> "SUMMARY:Buy milk\r\n"
      <> "  and eggs: semi-skimmed\r\n"
      <> "END:VTODO\r\n",
    )

  parse(ical)
  |> summary_of
  |> should.equal(Ok("Buy milk and eggs: semi-skimmed"))
}

/// A fold may be marked with a tab as well as a space.
///
/// RFC 5545 removes the line break and the single whitespace character that
/// marks the fold, and inserts nothing, so a value folded part way through is
/// joined back up exactly as it was.
pub fn tab_folded_summary_test() {
  let ical =
    vcalendar(
      "BEGIN:VTODO\r\nUID:1\r\n"
      <> "SUMMARY:See https://example.com/\r\n"
      <> "\tvery/long/path\r\n"
      <> "END:VTODO\r\n",
    )

  parse(ical)
  |> summary_of
  |> should.equal(Ok("See https://example.com/very/long/path"))
}

/// A property shogg does not model is kept rather than dropped, so that a
/// round trip does not lose it.
pub fn unknown_property_is_kept_test() {
  let ical =
    vcalendar("BEGIN:VTODO\r\nUID:1\r\nX-CUSTOM-THING:hello\r\nEND:VTODO\r\n")

  let assert Ok(parsed) = parse(ical)
  parsed.other
  |> should.equal([#("X-CUSTOM-THING", "hello")])
}

pub fn percent_complete_test() {
  let ical =
    vcalendar("BEGIN:VTODO\r\nUID:1\r\nPERCENT-COMPLETE:50\r\nEND:VTODO\r\n")

  let assert Ok(parsed) = parse(ical)
  parsed.percent_complete |> should.equal(Some(50))
}

pub fn percent_complete_must_be_a_number_test() {
  let ical =
    vcalendar("BEGIN:VTODO\r\nUID:1\r\nPERCENT-COMPLETE:half\r\nEND:VTODO\r\n")

  parse(ical) |> should.be_error()
}

pub fn no_vtodo_test() {
  let ical =
    vcalendar("BEGIN:VEVENT\r\nUID:1\r\nSUMMARY:Standup\r\nEND:VEVENT\r\n")

  parse(ical) |> should.be_error()
}

pub fn empty_test() {
  parse("") |> should.be_error()
}

// --- More edge cases ---------------------------------------------------------

/// A VTODO with nothing in it parses to an empty task rather than failing.
pub fn empty_vtodo_test() {
  parse(vcalendar("BEGIN:VTODO\r\nEND:VTODO\r\n"))
  |> should.equal(
    Ok(Task(
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
      meta: TaskMeta(href: "/tasks/1.ics", etag: "\"1\""),
    )),
  )
}

/// No UID is odd but not fatal; the task keeps the empty one it started with.
pub fn missing_uid_test() {
  let ical = vcalendar("BEGIN:VTODO\r\nSUMMARY:No uid\r\nEND:VTODO\r\n")

  let assert Ok(parsed) = parse(ical)
  parsed.uid |> should.equal("")
  parsed.summary |> should.equal(Some("No uid"))
}

pub fn no_summary_test() {
  let ical = vcalendar("BEGIN:VTODO\r\nUID:1\r\nEND:VTODO\r\n")

  let assert Ok(parsed) = parse(ical)
  parsed.summary |> should.equal(None)
}

/// An empty value is still a value: `SUMMARY:` is an empty string, not an
/// absent property.
pub fn empty_summary_test() {
  let ical = vcalendar("BEGIN:VTODO\r\nUID:1\r\nSUMMARY:\r\nEND:VTODO\r\n")

  parse(ical) |> summary_of |> should.equal(Ok(""))
}

/// A property line without a colon at all cannot be split into name and
/// value; the whole line becomes the name and the value stays empty.
pub fn property_without_colon_test() {
  let ical = vcalendar("BEGIN:VTODO\r\nUID:1\r\nMALFORMED\r\nEND:VTODO\r\n")

  let assert Ok(parsed) = parse(ical)
  parsed.other |> should.equal([#("MALFORMED", "")])
}

/// When a property appears twice the first one wins: the parser applies the
/// lines from the bottom up, so the earliest line is written last.
pub fn duplicate_summary_first_wins_test() {
  let ical =
    vcalendar(
      "BEGIN:VTODO\r\nUID:1\r\nSUMMARY:First\r\nSUMMARY:Second\r\nEND:VTODO\r\n",
    )

  parse(ical) |> summary_of |> should.equal(Ok("First"))
}

/// Servers are supposed to use LF only inside `calendar-data`; the result
/// must be the same as with CRLF.
pub fn lf_only_line_endings_test() {
  let ical = vcalendar("BEGIN:VTODO\nUID:1\nSUMMARY:Buy milk\nEND:VTODO\n")

  parse(ical) |> summary_of |> should.equal(Ok("Buy milk"))
}

/// A value folded over three lines joins back into one.
pub fn summary_folded_three_times_test() {
  let ical =
    vcalendar(
      "BEGIN:VTODO\r\nUID:1\r\n"
      <> "SUMMARY:one\r\n"
      <> "  two\r\n"
      <> "  three\r\n"
      <> "END:VTODO\r\n",
    )

  parse(ical) |> summary_of |> should.equal(Ok("one two three"))
}

/// Unmodelled properties keep the order they had on the wire, so a round trip
/// can reproduce them.
pub fn other_properties_keep_their_order_test() {
  let ical =
    vcalendar(
      "BEGIN:VTODO\r\nUID:1\r\nX-A:1\r\nX-B:2\r\nX-C:3\r\nEND:VTODO\r\n",
    )

  let assert Ok(parsed) = parse(ical)
  parsed.other
  |> should.equal([#("X-A", "1"), #("X-B", "2"), #("X-C", "3")])
}

// --- Round trips --------------------------------------------------------------

fn round_trip(ical: String) -> Result(Task, String) {
  use parsed <- result.try(parse(ical))
  parse(task.serialize_task(parsed))
}

/// A backslash in a value is escaped on the way out (`\\`) and comes back as
/// one on the way in.
pub fn backslash_round_trip_test() {
  let ical =
    vcalendar(
      "BEGIN:VTODO\r\nUID:1\r\nSUMMARY:C:\\Temp\\files\r\nEND:VTODO\r\n",
    )

  let assert Ok(parsed) = parse(ical)
  parsed.summary |> should.equal(Some("C:\\Temp\\files"))

  round_trip(ical) |> summary_of |> should.equal(Ok("C:\\Temp\\files"))
}

/// `Hello\, World` parses as `Hello, World` and serialises back into the
/// escaped form.
pub fn escaped_comma_round_trip_test() {
  let ical =
    vcalendar("BEGIN:VTODO\r\nUID:1\r\nSUMMARY:Hello\\, World\r\nEND:VTODO\r\n")

  parse(ical) |> summary_of |> should.equal(Ok("Hello, World"))
  round_trip(ical) |> summary_of |> should.equal(Ok("Hello, World"))
}

pub fn semicolon_round_trip_test() {
  let ical =
    vcalendar("BEGIN:VTODO\r\nUID:1\r\nSUMMARY:Buy milk; eggs\r\nEND:VTODO\r\n")

  parse(ical) |> summary_of |> should.equal(Ok("Buy milk; eggs"))
  round_trip(ical) |> summary_of |> should.equal(Ok("Buy milk; eggs"))
}

/// Every modelled field plus some unmodelled ones must survive
/// parse -> serialize -> parse unchanged, metadata included.
pub fn full_task_round_trip_test() {
  let ical =
    vcalendar(
      "BEGIN:VTODO\r\n"
      <> "UID:round-trip\r\n"
      <> "DTSTAMP:20260101T120000Z\r\n"
      <> "CREATED:20260101T100000Z\r\n"
      <> "LAST-MODIFIED:20260101T110000Z\r\n"
      <> "STATUS:IN-PROCESS\r\n"
      <> "SUMMARY:Buy milk\\, eggs; and juice\r\n"
      <> "COMPLETED:20260102T080000Z\r\n"
      <> "PERCENT-COMPLETE:40\r\n"
      <> "X-APPLE-SORT-ORDER:7\r\n"
      <> "DUE:20260105T090000Z\r\n"
      <> "X-CUSTOM:hello world\r\n"
      <> "END:VTODO\r\n",
    )

  let assert Ok(parsed) = parse(ical)
  parse(task.serialize_task(parsed)) |> should.equal(Ok(parsed))
}

// --- Known weaknesses ---------------------------------------------------------

/// A `VERSION` inside the VTODO is invalid ical, so the parser rejects it
/// with an error: only `VERSION:2.0` is accepted, anything else fails the
/// task instead of crashing.
pub fn version_other_than_2_inside_vtodo_test() {
  let ical = vcalendar("BEGIN:VTODO\r\nUID:1\r\nVERSION:1.0\r\nEND:VTODO\r\n")

  parse(ical) |> should.be_error()
}
