package main

import "core:fmt"
import "core:strings"

init :: proc(state: ^Tool_State) {
    state^ = {}
    state.documents = {
        Document{"notes.md", "reload keeps state while code changes"},
        Document{"todo.txt", "ship examples with distinct workflows"},
        Document{"ops.log", "worker processed request and updated cache"},
        Document{"readme.md", "durable state is composed from subsystems"},
        Document{},
        Document{},
        Document{},
        Document{},
    }
    state.report.summary = "started"
}

process_batch :: proc(state: ^Tool_State) {
    doc := next_document(state)
    words := parse_document(&state.parser, doc)
    index_document(&state.index, doc, words)
    update_report(&state.report, doc, words)

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

parse_document :: proc(parser: ^Parser_State, doc: Document) -> int {
    parser.documents_seen += 1
    return count_words(doc.text)
}

index_document :: proc(index: ^Index_State, doc: Document, words: int) {
    index.total_words += words
    index.last_name = doc.name
}

update_report :: proc(report: ^Report_State, doc: Document, words: int) {
    report.batches += 1
    report.summary = fmt.tprintf("%s: %d words", doc.name, words)
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
