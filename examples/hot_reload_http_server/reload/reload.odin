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
    server.serve_one(state)

    if probe_reload.checkpoint(host) {
        return
    }
}
