package reload

import server ".."
import olive_reload "../../../src/olive_reload"
import "core:fmt"

Server_State :: server.Server_State

init :: proc(state: ^Server_State) {
    server.init(state)
}

on_load :: proc(state: ^Server_State) {
    state.metrics.reloads += 1
    fmt.printf("server code reloaded; accepted=%d reloads=%d\n", state.metrics.accepted, state.metrics.reloads)
}

on_unload :: proc(state: ^Server_State) {
    state.metrics.unloads += 1
}

run :: proc(state: ^Server_State, host: ^olive_reload.Run_Host) {
    _ = host
    server.serve_one(state)
}
