package reload

import server ".."
import probe_reload "../../../src/probe_reload"

Server_State :: server.Server_State

init :: proc(state: ^Server_State) {
    server.init(state)
}

on_load :: proc(state: ^Server_State, is_reload: bool) {
    server.on_load(state, is_reload)
}

on_unload :: proc(state: ^Server_State) {
    server.on_unload(state)
}

run :: proc(state: ^Server_State, host: ^probe_reload.Run_Host) {
    server.handle_one_request(&state.routes)
    state.metrics.jobs += 1
    server.print_status(state)

    if probe_reload.checkpoint(host) {
        return
    }
}

force_reload :: proc(state: ^Server_State) -> bool {
    return server.force_reload(state)
}

force_restart :: proc(state: ^Server_State) -> bool {
    return server.force_restart(state)
}
