package main

import "core:fmt"

init :: proc(state: ^Server_State) {
    state.routes.last_path = "boot"
    state.routes.last_response = "initializing"
    state.metrics = {}
}

on_load :: proc(state: ^Server_State, is_reload: bool) {
    if is_reload {
        state.metrics.reloads += 1
        fmt.printf("\n-- run app reloaded; requests=%d reloads=%d --\n", state.routes.request_count, state.metrics.reloads)
    } else {
        fmt.println("-- hot reload run app started --")
    }
}

on_unload :: proc(state: ^Server_State) {
    state.metrics.unloads += 1
}

handle_one_request :: proc(routes: ^Route_State) {
    routes.request_count += 1
    if routes.request_count == 1 {
        routes.last_path = "/warmup"
    } else if routes.request_count % 3 == 0 {
        routes.last_path = "/assets"
    } else {
        routes.last_path = "/status"
    }
    routes.last_response = "ok"
}

print_status :: proc(state: ^Server_State) {
    fmt.printf(
        "[run] requests=%d jobs=%d reloads=%d unloads=%d path=%s response=%s\n",
        state.routes.request_count,
        state.metrics.jobs,
        state.metrics.reloads,
        state.metrics.unloads,
        state.routes.last_path,
        state.routes.last_response,
    )
}

force_reload :: proc(state: ^Server_State) -> bool {
    return false
}

force_restart :: proc(state: ^Server_State) -> bool {
    return false
}
