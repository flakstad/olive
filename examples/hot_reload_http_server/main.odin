package main

main :: proc() {
    state := Server_State{}
    init(&state)
    defer shutdown(&state)
    on_load(&state, false)
    defer on_unload(&state)

    for state.listening {
        serve_one(&state)
    }
}
