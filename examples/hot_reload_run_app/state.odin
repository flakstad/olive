package main

Route_State :: struct {
    request_count: int,
    last_path:     string,
    last_response: string,
}

Metrics_State :: struct {
    reloads: int,
    unloads: int,
    jobs:    int,
}

Server_State :: struct {
    routes:  Route_State,
    metrics: Metrics_State,
}
