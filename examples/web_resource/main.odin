// Copyright (c) Andreas Flakstad and Olive contributors
// SPDX-License-Identifier: MIT

package main

import "core:fmt"
import "core:net"
import "core:os"
import "core:strings"
import "core:time"

PORT :: 8069
MAX_SSE_CLIENTS :: 16

Web_State :: struct {
  listener:       net.TCP_Socket,
  server_started: bool,
  sse_clients:    [MAX_SSE_CLIENTS]net.TCP_Socket,
  sse_count:      int,
  style:          string,
  html:           string,
  generation:     int,
  requests:       int,
}

main :: proc() {
  state := Web_State{}
  init(&state)
  defer shutdown(&state)

  for {
    serve_tick(&state)
  }
}

init :: proc(state: ^Web_State) {
  state^ = {}
  load_style(state, "")
  load_html(state, "")
  start_server(state)
}

shutdown :: proc(state: ^Web_State) {
  for i in 0..<state.sse_count {
    net.close(state.sse_clients[i])
  }
  state.sse_count = 0
  if state.server_started {
    net.close(state.listener)
    state.server_started = false
  }
  if state.style != "" {
    delete(transmute([]byte)state.style)
    state.style = ""
  }
  if state.html != "" {
    delete(transmute([]byte)state.html)
    state.html = ""
  }
}

serve_tick :: proc(state: ^Web_State) {
  if !state.server_started {
    start_server(state)
  }
  accept_ready_clients(state)
  time.sleep(15 * time.Millisecond)
}

start_server :: proc(state: ^Web_State) {
  endpoint, ok := net.parse_endpoint(fmt.tprintf("127.0.0.1:%d", PORT))
  if !ok {
    fmt.println("failed to parse listen endpoint")
    return
  }

  listener, err := net.listen_tcp(endpoint, 128)
  if err != nil {
    fmt.printf("failed to listen on http://127.0.0.1:%d\n", PORT)
    return
  }
  if block_err := net.set_blocking(listener, false); block_err != nil {
    net.close(listener)
    fmt.println("failed to make listener nonblocking")
    return
  }

  state.listener = listener
  state.server_started = true
  fmt.printf("open http://127.0.0.1:%d\n", PORT)
}

accept_ready_clients :: proc(state: ^Web_State) {
  for _ in 0..<8 {
    client, _, err := net.accept_tcp(state.listener)
    if err == nil {
      handle_client(state, client)
      continue
    }
    if err != .Would_Block {
      fmt.println("accept failed")
    }
    return
  }
}

handle_client :: proc(state: ^Web_State, client: net.TCP_Socket) {
  buffer: [4096]byte
  n, recv_err := net.recv_tcp(client, buffer[:])
  if recv_err != nil || n <= 0 {
    net.close(client)
    return
  }

  request := string(buffer[:n])
  state.requests += 1
  switch {
  case strings.has_prefix(request, "GET /events "):
    attach_sse_client(state, client)
  case strings.has_prefix(request, "GET /style.css"):
    if state.style == "" {
      respond(client, "404 Not Found", "text/plain; charset=utf-8", "missing public/style.css\n")
      net.close(client)
      return
    }
    respond(client, "200 OK", "text/css; charset=utf-8", state.style)
    net.close(client)
  case strings.has_prefix(request, "GET / "):
    if state.html == "" {
      respond(client, "500 Internal Server Error", "text/plain; charset=utf-8", "missing public/index.html\n")
      net.close(client)
      return
    }
    page := render_page(state)
    defer delete(transmute([]byte)page)
    respond(client, "200 OK", "text/html; charset=utf-8", page)
    net.close(client)
  case:
    respond(client, "404 Not Found", "text/plain; charset=utf-8", "not found\n")
    net.close(client)
  }
}

respond :: proc(client: net.TCP_Socket, status, content_type, body: string) {
  response := fmt.tprintf(
    "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s",
    status,
    content_type,
    len(body),
    body,
  )
  _, _ = net.send_tcp(client, transmute([]byte)response)
}

attach_sse_client :: proc(state: ^Web_State, client: net.TCP_Socket) {
  if state.sse_count >= MAX_SSE_CLIENTS {
    respond(client, "503 Service Unavailable", "text/plain; charset=utf-8", "too many event clients\n")
    net.close(client)
    return
  }
  headers := "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n"
  if !send_all(client, headers) {
    net.close(client)
    return
  }
  state.sse_clients[state.sse_count] = client
  state.sse_count += 1
  send_event(client, "hello", fmt.tprintf("%d", state.generation))
}

send_event :: proc(client: net.TCP_Socket, name, data: string) -> bool {
  return send_all(client, fmt.tprintf("event: %s\ndata: %s\n\n", name, data))
}

send_all :: proc(client: net.TCP_Socket, text: string) -> bool {
  written, err := net.send_tcp(client, transmute([]byte)text)
  return err == nil && written == len(text)
}

reload_resource :: proc(state: ^Web_State, path: string) {
  if strings.has_suffix(path, "style.css") {
    load_style(state, path)
    state.generation += 1
    broadcast_reload(state)
    fmt.printf("style reload generation=%d\n", state.generation)
  } else if strings.has_suffix(path, "index.html") {
    load_html(state, path)
    state.generation += 1
    broadcast_reload(state)
    fmt.printf("html reload generation=%d\n", state.generation)
  }
}

broadcast_reload :: proc(state: ^Web_State) {
  i := 0
  for i < state.sse_count {
    if send_event(state.sse_clients[i], "refresh", fmt.tprintf("%d", state.generation)) {
      i += 1
      continue
    }

    net.close(state.sse_clients[i])
    last := state.sse_count - 1
    state.sse_clients[i] = state.sse_clients[last]
    state.sse_clients[last] = {}
    state.sse_count = last
  }
}

load_style :: proc(state: ^Web_State, changed_path: string) {
  if changed_path != "" && load_style_from(state, changed_path) {
    return
  }
  if load_style_from(state, "examples/web_resource/public/style.css") {
    return
  }
  if load_style_from(state, "public/style.css") {
    return
  }
  set_style(state, "")
  fmt.println("missing public/style.css")
}

load_html :: proc(state: ^Web_State, changed_path: string) {
  if changed_path != "" && load_html_from(state, changed_path) {
    return
  }
  if load_html_from(state, "examples/web_resource/public/index.html") {
    return
  }
  if load_html_from(state, "public/index.html") {
    return
  }
  set_html(state, "")
  fmt.println("missing public/index.html")
}

load_style_from :: proc(state: ^Web_State, path: string) -> bool {
  data, err := os.read_entire_file_from_path(path, context.allocator)
  if err != nil {
    return false
  }
  set_style(state, string(data))
  return true
}

load_html_from :: proc(state: ^Web_State, path: string) -> bool {
  data, err := os.read_entire_file_from_path(path, context.allocator)
  if err != nil {
    return false
  }
  set_html(state, string(data))
  return true
}

set_style :: proc(state: ^Web_State, next: string) {
  if state.style != "" {
    delete(transmute([]byte)state.style)
  }
  state.style = next
}

set_html :: proc(state: ^Web_State, next: string) {
  if state.html != "" {
    delete(transmute([]byte)state.html)
  }
  state.html = next
}

render_page :: proc(state: ^Web_State) -> string {
  b := strings.builder_make()
  defer strings.builder_destroy(&b)

  rest := state.html
  for {
    generation_index := strings.index(rest, "{{generation}}")
    requests_index := strings.index(rest, "{{requests}}")

    if generation_index < 0 && requests_index < 0 {
      strings.write_string(&b, rest)
      break
    }

    use_generation := generation_index >= 0 && (requests_index < 0 || generation_index < requests_index)
    if use_generation {
      strings.write_string(&b, rest[:generation_index])
      fmt.sbprintf(&b, "%d", state.generation)
      rest = rest[generation_index + len("{{generation}}"):]
    } else {
      strings.write_string(&b, rest[:requests_index])
      fmt.sbprintf(&b, "%d", state.requests)
      rest = rest[requests_index + len("{{requests}}"):]
    }
  }

  return strings.clone(strings.to_string(b))
}
