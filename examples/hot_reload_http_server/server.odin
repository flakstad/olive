package main

import "core:fmt"
import "core:net"
import "core:strings"

init :: proc(state: ^Server_State) {
    state^ = {}
    listener, err := net.listen_tcp({net.IP4_Loopback, SERVER_PORT}, 16)
    if err != nil {
        fmt.eprintf("failed to listen on http://127.0.0.1:%d: %v\n", SERVER_PORT, err)
        return
    }
    state.listener = listener
    state.listening = true
    fmt.printf("listening on http://127.0.0.1:%d\n", SERVER_PORT)
}

shutdown :: proc(state: ^Server_State) {
    if state.listening {
        net.close(state.listener)
        state.listening = false
    }
}

on_load :: proc(state: ^Server_State, is_reload: bool) {
    if is_reload {
        state.metrics.reloads += 1
        fmt.printf("server code reloaded; accepted=%d reloads=%d\n", state.metrics.accepted, state.metrics.reloads)
    }
}

on_unload :: proc(state: ^Server_State) {
    state.metrics.unloads += 1
}

serve_one :: proc(state: ^Server_State) {
    if !state.listening {
        return
    }

    client, _, accept_err := net.accept_tcp(state.listener)
    if accept_err != nil {
        fmt.eprintf("accept failed: %v\n", accept_err)
        return
    }
    defer net.close(client)

    buffer: [2048]byte
    n, recv_err := net.recv_tcp(client, buffer[:])
    if recv_err != nil || n <= 0 {
        return
    }

    request := string(buffer[:n])
    path := request_path(request)
    body, status := route(state, path)
    response := fmt.tprintf(
        "HTTP/1.1 %s\r\nContent-Type: text/plain\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s",
        status,
        len(body),
        body,
    )
    _, _ = net.send_tcp(client, transmute([]byte)response)
    state.metrics.accepted += 1
    fmt.printf("served %s -> %s\n", path, status)
}

request_path :: proc(request: string) -> string {
    if strings.has_prefix(request, "GET /status ") {
        return "/status"
    }
    if strings.has_prefix(request, "GET / ") {
        return "/"
    }
    return "/missing"
}

route :: proc(state: ^Server_State, path: string) -> (body, status: string) {
    switch path {
    case "/":
        state.routes.home += 1
        return fmt.tprintf("hello from reloadable Odin route\nrequests=%d\n", state.metrics.accepted + 1), "200 OK"
    case "/status":
        state.routes.status += 1
        return fmt.tprintf(
            "accepted=%d\nreloads=%d\nunloads=%d\nhome=%d\nstatus=%d\nmissing=%d\n",
            state.metrics.accepted,
            state.metrics.reloads,
            state.metrics.unloads,
            state.routes.home,
            state.routes.status,
            state.routes.missing,
        ), "200 OK"
    case:
        state.routes.missing += 1
        return "not found\n", "404 Not Found"
    }
}
