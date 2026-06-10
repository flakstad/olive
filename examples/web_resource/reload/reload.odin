package reload

import web ".."
import olive_reload "../.olive/reload/runtime/olive_reload"

Reload_State :: web.Web_State

Olive_Watch_Resources :: "../public"
Olive_Watch_Debounce_MS :: "50"

init :: proc(state: ^Reload_State) {
  web.init(state)
}

run :: proc(state: ^Reload_State, host: ^olive_reload.Run_Host) {
  _ = host
  web.serve_tick(state)
}

on_resource_change :: proc(state: ^Reload_State, path: string) {
  web.reload_resource(state, path)
}
