package main

main :: proc() {
    state := Server_State{}
    init(&state)
    defer shutdown(&state)

    for state.listening {
        serve_one(&state)
    }
}
