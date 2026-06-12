package reload

import game ".."
import olive_reload "../.olive/reload/runtime/olive_reload"
import ray "vendor:raylib"

// Avoid colliding with Raylib's own `raylib.dll` on Windows.
Olive_Module_Name :: "olive_raylib"
Olive_Odin_Args :: "-define:RAYLIB_SHARED=true"

Reload_State :: game.Game_State

host_init :: proc() {
  if !ray.IsWindowReady() {
    ray.InitWindow(game.WINDOW_WIDTH, game.WINDOW_HEIGHT, "Olive Raylib")
    ray.SetTargetFPS(60)
  }
}

host_shutdown :: proc() {
  if ray.IsWindowReady() {
    ray.CloseWindow()
  }
}

init :: proc(state: ^Reload_State) {
  game.init(state)
}

on_load :: proc(state: ^Reload_State) {
  state.hud.reloads += 1
  state.hud.message = "code reloaded"
}

on_unload :: proc(state: ^Reload_State) {
  state.hud.message = "unloading"
}

run :: proc(state: ^Reload_State, host: ^olive_reload.Run_Host) {
  if ray.WindowShouldClose() {
    olive_reload.request_exit(host)
    return
  }
  game.frame(state)
}

force_reload :: proc(state: ^Reload_State) -> bool {
  return game.force_reload(state)
}

force_restart :: proc(state: ^Reload_State) -> bool {
  return game.force_restart(state)
}
