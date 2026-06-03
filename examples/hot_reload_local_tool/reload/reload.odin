package reload

import tool ".."
import probe_reload "../../../src/probe_reload"
import "core:time"

Tool_State :: tool.Tool_State

init :: proc(state: ^Tool_State) {
    tool.init(state)
}

on_load :: proc(state: ^Tool_State, is_reload: bool) {
    tool.on_load(state, is_reload)
}

run :: proc(state: ^Tool_State, host: ^probe_reload.Run_Host) {
    _ = host
    tool.process_batch(state)

    time.sleep(300 * time.Millisecond)
}
