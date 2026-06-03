package main

main :: proc() {
    state := Server_State{}
    init(&state)
    on_load(&state, false)

    for _ in 0..<5 {
        handle_one_request(&state.routes)
        state.metrics.jobs += 1
        print_status(&state)
    }

    on_unload(&state)
}
