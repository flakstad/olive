package main

Player_State :: struct {
    x:        int,
    velocity: int,
    energy:   int,
}

World_State :: struct {
    frame:  int,
    player: Player_State,
    width:  int,
}

Hud_State :: struct {
    reloads:      int,
    unloads:      int,
    last_message: string,
}

Asset_State :: struct {
    sprite: string,
    trail:  string,
}

Game_State :: struct {
    world:  World_State,
    hud:    Hud_State,
    assets: Asset_State,
}
