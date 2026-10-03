import gleeunit
import gleeunit/should
import gleam/list
import model.{queue_push, reconnect_delay}
import shared/api

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn queue_push_appends_test() {
  queue_push([], "a") |> should.equal(["a"])
}

pub fn queue_push_keeps_order_test() {
  queue_push(["a", "b"], "c") |> should.equal(["a", "b", "c"])
}

pub fn queue_push_caps_size_test() {
  let queue = list.repeat("x", 50)
  let queue = queue_push(queue, "new")
  list.length(queue) |> should.equal(50)
  list.first(queue) |> should.equal(Ok("x"))
  list.reverse(queue) |> list.first() |> should.equal(Ok("new"))
}

pub fn reconnect_delay_backoff_test() {
  reconnect_delay(0) |> should.equal(1000)
  reconnect_delay(1) |> should.equal(2000)
  reconnect_delay(2) |> should.equal(4000)
  reconnect_delay(3) |> should.equal(8000)
  reconnect_delay(4) |> should.equal(15000)
  reconnect_delay(99) |> should.equal(15000)
}

pub fn server_msg_decodes_todos_test() {
  api.parse_server_msg("{\"event\":\"todos\",\"todos\":[]}")
  |> should.equal(Ok(api.Todos([])))
}

pub fn server_msg_rejects_unknown_event_test() {
  case api.parse_server_msg("{\"event\":\"nope\"}") {
    Error(_) -> True
    Ok(_) -> False
  }
  |> should.be_true()
}
