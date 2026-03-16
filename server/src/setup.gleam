// This is setup code for server_component from the lustre-server-components basic example
// https://github.com/lustre-labs/lustre/tree/main/examples/06-server-components/01-basic-setup

import gleam/bytes_tree
import gleam/erlang/application
import gleam/erlang/process.{type Selector, type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{type Option, None, Some}
import lustre
import lustre/attribute
import lustre/element
import lustre/element/html.{html}
import lustre/server_component
import mist.{type Connection, type ResponseData}
import todo_message

// HTML ------------------------------------------------------------------------

pub fn serve_static(from module, serve file, as_ content_type) {
  let assert Ok(priv_path) = application.priv_directory(module)
  let static_path = priv_path <> "/static/" <> file
  case mist.send_file(static_path, offset: 0, limit: None) {
    Ok(file) ->
      response.new(200)
      |> response.prepend_header("content-type", content_type)
      |> response.set_body(file)

    Error(_) ->
      response.new(404)
      |> response.set_body(mist.Bytes(bytes_tree.new()))
  }
}

pub fn serve_html() -> Response(ResponseData) {
  let html =
    html([attribute.lang("en")], [
      html.head([], [
        html.meta([attribute.charset("utf-8")]),
        html.meta([
          attribute.name("viewport"),
          attribute.content("width=device-width, initial-scale=1"),
        ]),
        html.title([], "Shogging"),
        html.script(
          [attribute.type_("module"), attribute.src("/lustre/runtime.mjs")],
          "",
        ),
        html.script(
          [
            attribute.src(
              "https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js",
            ),
            attribute.attribute("defer", ""),
          ],
          "",
        ),
        html.script(
          [],
          "
            console.log('asd')
            document.addEventListener('alpine:init', () => {
              console.log('asd')
              customElements.whenDefined('lustre-server-component').then(() => {
                console.log('asd')
                const host = document.querySelector('lustre-server-component');
                setTimeout(()=>{
                console.log(host.shadowRoot)
                if (host?.shadowRoot) {
                  console.log('asd')
                  Alpine.initTree(host.shadowRoot);
                }
              }, 1000)
              });
            });
          ",
        ),
        html.link([
          attribute.rel("stylesheet"),
          attribute.href(
            "https://cdn.jsdelivr.net/npm/@picocss/pico@2/css/pico.orange.min.css",
          ),
        ]),
      ]),
      html.body(
        [attribute.styles([#("max-width", "32rem"), #("margin", "3rem auto")])],
        [server_component.element([server_component.route("/ws")], [])],
      ),
    ])
    |> element.to_document_string_tree
    |> bytes_tree.from_string_tree

  response.new(200)
  |> response.set_body(mist.Bytes(html))
  |> response.set_header("content-type", "text/html")
}

// JAVASCRIPT ------------------------------------------------------------------

pub fn serve_runtime() -> Response(ResponseData) {
  serve_static(
    from: "lustre",
    serve: "lustre-server-component.mjs",
    as_: "application/javascript",
  )
}

// WEBSOCKET -------------------------------------------------------------------

pub fn serve_component(
  request: Request(Connection),
  component,
) -> Response(ResponseData) {
  mist.websocket(
    request:,
    on_init: init_component_socket(_, component),
    handler: loop_component_socket,
    on_close: close_component_socket,
  )
}

type ComponentSocket {
  ComponentSocket(
    component: lustre.Runtime(todo_message.Msg),
    self: Subject(server_component.ClientMessage(todo_message.Msg)),
  )
}

type ComponentSocketMessage =
  server_component.ClientMessage(todo_message.Msg)

type ComponentSocketInit =
  #(ComponentSocket, Option(Selector(ComponentSocketMessage)))

fn init_component_socket(_, component) -> ComponentSocketInit {
  // The server component runtime communicates to the websocket process using
  // Gleam's standard process messaging. We construct a new subject that the
  // runtime can send messages to, and then we initialise a selector so that we
  // can handle those messages in `loop_component_socket`.
  let self = process.new_subject()
  let selector =
    process.new_selector()
    |> process.select(self)

  // Calling `register_subject` is how the runtime knows to send messages to
  // this process when it wants to communicate with the client. In Lustre, server
  // components are not opinionated about the transport layer or your network
  // setup: instead the runtime broadcasts messages to any registered subjects
  // and lets you handle the transport layer yourself.
  server_component.register_subject(self)
  |> lustre.send(to: component)

  #(ComponentSocket(component:, self:), Some(selector))
}

fn loop_component_socket(
  state: ComponentSocket,
  message: mist.WebsocketMessage(ComponentSocketMessage),
  connection: mist.WebsocketConnection,
) -> mist.Next(ComponentSocket, ComponentSocketMessage) {
  case message {
    // The client runtime will send us JSON-encoded text frames that we need to
    // decode and pass to the server component runtime.
    mist.Text(json) -> {
      case json.parse(json, server_component.runtime_message_decoder()) {
        Ok(runtime_message) -> lustre.send(state.component, runtime_message)
        // This case will only be hit if something other than Lustre's client
        // runtime sends us a message.
        Error(_) -> Nil
      }

      mist.continue(state)
    }

    mist.Binary(_) -> {
      mist.continue(state)
    }

    // We hit this case when the server component runtime sends us a message that
    // we need to forward to the client. Because Lustre does not control your
    // network connection, it's our app's responsibility to make sure these messages
    // are encoded and sent to the client.
    mist.Custom(client_message) -> {
      let json = server_component.client_message_to_json(client_message)
      let assert Ok(_) = mist.send_text_frame(connection, json.to_string(json))

      mist.continue(state)
    }

    mist.Closed | mist.Shutdown -> mist.stop()
  }
}

fn close_component_socket(state: ComponentSocket) -> Nil {
  server_component.deregister_subject(state.self)
  |> lustre.send(to: state.component)
}
