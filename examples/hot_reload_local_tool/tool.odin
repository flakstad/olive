package main

import "core:fmt"
import "core:strings"

init :: proc(state: ^Tool_State) {
    state^ = {}
    state.documents = {
        Document{"notes.md", "reload keeps state while code changes"},
        Document{"todo.txt", "ship examples with distinct workflows"},
        Document{"ops.log", "worker processed request and updated cache"},
        Document{"readme.md", "durable state can point at subsystems"},
        Document{},
        Document{},
        Document{},
        Document{},
    }
    wire_subsystems(state)
    state.report.summary = "started"
}

wire_subsystems :: proc(state: ^Tool_State) {
    state.systems.parser = &state.parser
    state.systems.index = &state.index
    state.systems.report = &state.report
}

on_load :: proc(state: ^Tool_State, is_reload: bool) {
    wire_subsystems(state)
    if is_reload {
        state.report.reloads += 1
        state.report.summary = "code reloaded; subsystem pointers rewired"
    }
}

process_batch :: proc(state: ^Tool_State) {
    wire_subsystems(state)
    doc := next_document(state)
    words := count_words(doc.text)

    state.systems.parser.documents_seen += 1
    state.systems.index.total_words += words
    state.systems.index.last_name = doc.name
    state.systems.report.batches += 1
    state.systems.report.summary = fmt.tprintf("%s: %d words", doc.name, words)

    fmt.printf(
        "batch=%d reloads=%d docs=%d total_words=%d last=%s summary=%s\n",
        state.report.batches,
        state.report.reloads,
        state.parser.documents_seen,
        state.index.total_words,
        state.index.last_name,
        state.report.summary,
    )
}

next_document :: proc(state: ^Tool_State) -> Document {
    doc := state.documents[state.cursor % 4]
    state.cursor += 1
    return doc
}

count_words :: proc(text: string) -> int {
    count := 0
    in_word := false
    for ch in text {
        if strings.is_space(ch) {
            in_word = false
        } else if !in_word {
            count += 1
            in_word = true
        }
    }
    return count
}
