package main

MAX_DOCUMENTS :: 8

Document :: struct {
    name: string,
    text: string,
}

Parser_State :: struct {
    documents_seen: int,
}

Index_State :: struct {
    total_words: int,
    last_name:   string,
}

Report_State :: struct {
    reloads: int,
    batches: int,
    summary: string,
}

Subsystems :: struct {
    parser: ^Parser_State,
    index:  ^Index_State,
    report: ^Report_State,
}

Tool_State :: struct {
    parser:     Parser_State,
    index:      Index_State,
    report:     Report_State,
    systems:    Subsystems,
    cursor:     int,
    documents:  [MAX_DOCUMENTS]Document,
}
