package main

main :: proc() {
    state := Game_State{}
    init(&state)
    on_load(&state, false)

    for _ in 0..<5 {
        tick(&state)
    }

    on_unload(&state)
}
