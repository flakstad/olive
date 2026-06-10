package reload

import tool ".."
import olive_reload "../.olive/reload/runtime/olive_reload"
import "core:time"

Reload_State :: tool.Tool_State

init :: proc(state: ^Reload_State) {
  tool.init(state)
}

on_load :: proc(state: ^Reload_State) {
  state.report.reloads += 1
  state.report.summary = "code reloaded; durable subsystem state preserved"
}

run :: proc(state: ^Reload_State, host: ^olive_reload.Run_Host) {
  _ = host
  tool.process_batch(state)

  time.sleep(300 * time.Millisecond)
}
