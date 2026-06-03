package main

import "core:net"

SERVER_PORT :: 8099

Route_Metrics :: struct {
    home:    int,
    status:  int,
    missing: int,
}

Server_Metrics :: struct {
    accepted: int,
    reloads:  int,
    unloads:  int,
}

Server_State :: struct {
    listener:  net.TCP_Socket,
    listening: bool,
    routes:    Route_Metrics,
    metrics:   Server_Metrics,
}
