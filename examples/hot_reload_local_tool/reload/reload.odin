package reload

import tool ".."
import olive_reload "../../../src/olive_reload"
import "core:time"

Tool_State :: tool.Tool_State

init :: proc(state: ^Tool_State) {
    tool.init(state)
}

on_load :: proc(state: ^Tool_State) {
    state.report.reloads += 1
    state.report.summary = "code reloaded; durable subsystem state preserved"
}

run :: proc(state: ^Tool_State, host: ^olive_reload.Run_Host) {
    _ = host
    tool.process_batch(state)

    time.sleep(300 * time.Millisecond)
}
