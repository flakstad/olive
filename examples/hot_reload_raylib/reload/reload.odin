package reload

import game ".."
import probe_reload "../../../src/probe_reload"
import ray "vendor:raylib"

Game_State :: game.Game_State

host_init :: proc() {
  if !ray.IsWindowReady() {
    ray.InitWindow(game.WINDOW_WIDTH, game.WINDOW_HEIGHT, "Probe Raylib Hot Reload")
    ray.SetTargetFPS(60)
  }
}

host_shutdown :: proc() {
  if ray.IsWindowReady() {
    ray.CloseWindow()
  }
}

init :: proc(state: ^Game_State) {
  game.init(state)
}

on_load :: proc(state: ^Game_State) {
  state.hud.reloads += 1
  state.hud.message = "code reloaded"
}

on_unload :: proc(state: ^Game_State) {
  state.hud.message = "unloading"
}

run :: proc(state: ^Game_State, host: ^probe_reload.Run_Host) {
  if ray.WindowShouldClose() {
    probe_reload.request_exit(host)
    return
  }
  game.frame(state)
}

force_reload :: proc(state: ^Game_State) -> bool {
  return game.force_reload(state)
}

force_restart :: proc(state: ^Game_State) -> bool {
  return game.force_restart(state)
}
