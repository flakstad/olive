package main

import "core:fmt"

init :: proc(state: ^Game_State) {
    state.world = World_State{
        frame = 0,
        width = 28,
        player = Player_State{x = 0, velocity = 1, energy = 10},
    }
    state.hud = Hud_State{
        reloads = 0,
        unloads = 0,
        last_message = "boot",
    }
    state.assets = Asset_State{
        sprite = "@",
        trail = ".",
    }
}

on_load :: proc(state: ^Game_State, is_reload: bool) {
    if is_reload {
        state.hud.reloads += 1
        state.hud.last_message = "code reloaded"
        fmt.printf("\n-- reload %d at frame=%d --\n", state.hud.reloads, state.world.frame)
    } else {
        state.hud.last_message = "started"
        fmt.println("-- hot reload game started --")
    }
}

on_unload :: proc(state: ^Game_State) {
    state.hud.unloads += 1
    state.hud.last_message = "unloading generation"
}

tick :: proc(state: ^Game_State) {
    update_world(&state.world)
    update_hud(&state.hud, &state.world)
    draw(&state.world, &state.hud, &state.assets)
}

update_world :: proc(world: ^World_State) {
    world.frame += 1
    player := &world.player
    player.x += player.velocity
    player.energy -= 1

    if player.x >= world.width {
        player.x = world.width
        player.velocity = -1
    } else if player.x <= 0 {
        player.x = 0
        player.velocity = 1
    }

    if player.energy <= 0 {
        player.energy = 10
    }
}

update_hud :: proc(hud: ^Hud_State, world: ^World_State) {
    if world.player.energy == 10 {
        hud.last_message = "energy restored"
    } else {
        hud.last_message = "running"
    }
}

draw :: proc(world: ^World_State, hud: ^Hud_State, assets: ^Asset_State) {
    fmt.printf(
        "frame=%03d reloads=%d unloads=%d energy=%02d %-16s |",
        world.frame,
        hud.reloads,
        hud.unloads,
        world.player.energy,
        hud.last_message,
    )
    for x in 0..=world.width {
        if x == world.player.x {
            fmt.print(assets.sprite)
        } else {
            fmt.print(assets.trail)
        }
    }
    fmt.println("|")
}

force_reload :: proc(state: ^Game_State) -> bool {
    return false
}

force_restart :: proc(state: ^Game_State) -> bool {
    return false
}
