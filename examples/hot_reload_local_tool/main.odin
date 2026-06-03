package main

main :: proc() {
    state := Tool_State{}
    init(&state)
    on_load(&state, false)

    for _ in 0..<8 {
        process_batch(&state)
    }
}
