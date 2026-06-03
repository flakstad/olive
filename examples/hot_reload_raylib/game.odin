package main

import "core:math"
import ray "vendor:raylib"

init :: proc(state: ^Game_State) {
  state^ = {}
  state.player = Player_State{
    position = ray.Vector2{WINDOW_WIDTH / 2, WINDOW_HEIGHT / 2},
    speed = 280,
    size = 24,
  }
  state.world.arena = ray.Rectangle{x = 32, y = 48, width = WINDOW_WIDTH - 64, height = WINDOW_HEIGHT - 96}
  state.world.spawn_timer = 0.35
  state.hud.message = "normal run"
}

frame :: proc(state: ^Game_State) {
  dt := f32(ray.GetFrameTime())
  if dt <= 0 || dt > 0.05 {
    dt = 1.0 / 60.0
  }

  read_input(&state.input)
  update_player(&state.player, &state.input, state.world.arena, dt)
  update_bullets(&state.world, dt)
  update_drones(&state.world, &state.player, dt)
  update_collisions(&state.world, &state.hud)

  if state.input.fire_pressed {
    spawn_bullet(&state.world, state.player.position)
  }
  if state.input.reset_pressed {
    score := state.hud.score
    reloads := state.hud.reloads
    init(state)
    state.hud.score = score
    state.hud.reloads = reloads
    state.hud.resets += 1
    state.hud.message = "state reset"
  }

  state.world.frame += 1
  state.world.elapsed += dt
  draw(state)
}

read_input :: proc(input: ^Input_State) {  
  input^ = {}
  if ray.IsKeyDown(.A) || ray.IsKeyDown(.LEFT) {
    input.move[0] -= 1
  }
  if ray.IsKeyDown(.D) || ray.IsKeyDown(.RIGHT) {
    input.move[0] += 1
  }
  if ray.IsKeyDown(.W) || ray.IsKeyDown(.UP) {
    input.move[1] -= 1
  }
  if ray.IsKeyDown(.S) || ray.IsKeyDown(.DOWN) {
    input.move[1] += 1
  }
  input.fire_pressed = ray.IsKeyPressed(.SPACE)
  input.reset_pressed = ray.IsKeyPressed(.R)
  
}

update_player :: proc(player: ^Player_State, input: ^Input_State, arena: ray.Rectangle, dt: f32) {
  move := normalize_or_zero(input.move)
  player.velocity = ray.Vector2{move[0] * player.speed, move[1] * player.speed}
  player.position[0] += player.velocity[0] * dt
  player.position[1] += player.velocity[1] * dt
  player.position[0] = clamp_f32(player.position[0], arena.x + player.size, arena.x + arena.width - player.size)
  player.position[1] = clamp_f32(player.position[1], arena.y + player.size, arena.y + arena.height - player.size)
}

spawn_bullet :: proc(world: ^World_State, position: ray.Vector2) {
  for i in 0..<MAX_BULLETS {
    if !world.bullets[i].active {
      world.bullets[i] = Bullet_State{
        active = true,
        position = position,
        velocity = ray.Vector2{520, 0},
        ttl = 1.4,
      }
      return
    }
  }
}

update_bullets :: proc(world: ^World_State, dt: f32) {
  for i in 0..<MAX_BULLETS {
    bullet := &world.bullets[i]
    if !bullet.active {
      continue
    }
    bullet.position[0] += bullet.velocity[0] * dt
    bullet.position[1] += bullet.velocity[1] * dt
    bullet.ttl -= dt
    if bullet.ttl <= 0 || bullet.position[0] > world.arena.x + world.arena.width + 32 {
      bullet.active = false
    }
  }
}

update_drones :: proc(world: ^World_State, player: ^Player_State, dt: f32) {
  world.spawn_timer -= dt
  if world.spawn_timer <= 0 {
    spawn_drone(world)
    world.spawn_timer = 0.65
  }

  for i in 0..<MAX_DRONES {
    drone := &world.drones[i]
    if !drone.active {
      continue
    }
    to_player := ray.Vector2{player.position[0] - drone.position[0], player.position[1] - drone.position[1]}
    dir := normalize_or_zero(to_player)
    drone.velocity = ray.Vector2{dir[0] * 75, dir[1] * 75}
    drone.position[0] += drone.velocity[0] * dt
    drone.position[1] += drone.velocity[1] * dt
  }
}

spawn_drone :: proc(world: ^World_State) {
  for i in 0..<MAX_DRONES {
    if !world.drones[i].active {
      y := world.arena.y + 40 + f32((world.frame * 53 + i * 31) % int(world.arena.height - 80))
      world.drones[i] = Drone_State{
        active = true,
        position = ray.Vector2{world.arena.x + world.arena.width - 30, y},
        radius = 14,
      }
      return
    }
  }
}

update_collisions :: proc(world: ^World_State, hud: ^Hud_State) {
  for bullet_index in 0..<MAX_BULLETS {
    bullet := &world.bullets[bullet_index]
    if !bullet.active {
      continue
    }
    for drone_index in 0..<MAX_DRONES {
      drone := &world.drones[drone_index]
      if !drone.active {
        continue
      }
      if ray.CheckCollisionCircles(bullet.position, 5, drone.position, drone.radius) {
        bullet.active = false
        drone.active = false
        hud.score += 10
        hud.message = "hit"
        break
      }
    }
  }
}

draw :: proc(state: ^Game_State) {
  ray.BeginDrawing()
  defer ray.EndDrawing()

  ray.ClearBackground(ray.Color{18, 20, 24, 255})
  ray.DrawRectangleRec(state.world.arena, ray.Color{31, 36, 44, 255})
  ray.DrawRectangleLinesEx(state.world.arena, 2, ray.Color{96, 113, 128, 255})

  for drone in state.world.drones {
    if drone.active {
      ray.DrawCircleV(drone.position, drone.radius, ray.Color{224, 83, 83, 255})
      ray.DrawCircleLinesV(drone.position, drone.radius + 3, ray.Color{255, 180, 110, 255})
    }
  }

  for bullet in state.world.bullets {
    if bullet.active {
      ray.DrawCircleV(bullet.position, 5, ray.Color{255, 214, 102, 255})
    }
  }

  player_rect := ray.Rectangle{
    x = state.player.position[0] - state.player.size,
    y = state.player.position[1] - state.player.size,
    width = state.player.size * 2,
    height = state.player.size * 2,
  }
  ray.DrawRectangleRec(player_rect, ray.Color{82, 170, 255, 255})
  ray.DrawRectangleLinesEx(player_rect, 2, ray.WHITE)

  ray.DrawText("Olive Raylib Hot Reload", 32, 16, 24, ray.RAYWHITE)
  ray.DrawText("WASD/arrows move   Space fires   R resets state   Esc exits", 32, WINDOW_HEIGHT - 36, 18, ray.LIGHTGRAY)
  ray.DrawText(ray.TextFormat("score %04d", state.hud.score), 720, 18, 22, ray.RAYWHITE)
  ray.DrawText(ray.TextFormat("reloads %d  resets %d", state.hud.reloads, state.hud.resets), 720, 44, 18, ray.LIGHTGRAY)
  ray.DrawText(ray.TextFormat("frame %d  %s", state.world.frame, state.hud.message), 32, 46, 18, ray.LIGHTGRAY)
  ray.DrawFPS(WINDOW_WIDTH - 88, WINDOW_HEIGHT - 32)
}

force_reload :: proc(state: ^Game_State) -> bool {
  return ray.IsKeyPressed(.F5)
}

force_restart :: proc(state: ^Game_State) -> bool {
  return ray.IsKeyPressed(.F6)
}

normalize_or_zero :: proc(v: ray.Vector2) -> ray.Vector2 {
  len_sq := v[0] * v[0] + v[1] * v[1]
  if len_sq <= 0.0001 {
    return {}
  }
  inv_len := 1.0 / math.sqrt(len_sq)
  return ray.Vector2{v[0] * inv_len, v[1] * inv_len}
}

clamp_f32 :: proc(value, low, high: f32) -> f32 {
  if value < low {
    return low
  }
  if value > high {
    return high
  }
  return value
}
