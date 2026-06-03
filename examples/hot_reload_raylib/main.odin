package main

import ray "vendor:raylib"

main :: proc() {
    ray.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Olive Raylib Hot Reload")
    defer ray.CloseWindow()
    ray.SetTargetFPS(60)

    state := Game_State{}
    init(&state)

    for !ray.WindowShouldClose() {
        frame(&state)
    }
}
