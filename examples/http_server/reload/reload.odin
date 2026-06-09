package reload

import server ".."
import olive_reload "../../../src/olive_reload"
import "core:fmt"

Reload_State :: server.Server_State

init :: proc(state: ^Reload_State) {
    server.init(state)
}

on_load :: proc(state: ^Reload_State) {
    state.metrics.reloads += 1
    fmt.printf("server code reloaded; accepted=%d reloads=%d\n", state.metrics.accepted, state.metrics.reloads)
}

on_unload :: proc(state: ^Reload_State) {
    state.metrics.unloads += 1
}

run :: proc(state: ^Reload_State, host: ^olive_reload.Run_Host) {
    _ = host
    server.serve_one(state)
}
