package main

import ray "vendor:raylib"

main :: proc() {
    ray.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Probe Raylib Hot Reload")
    defer ray.CloseWindow()
    ray.SetTargetFPS(60)

    state := Game_State{}
    init(&state)
    on_load(&state, false)
    defer on_unload(&state)

    for !ray.WindowShouldClose() {
        frame(&state)
    }
}
