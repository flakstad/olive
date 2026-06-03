package main

import ray "vendor:raylib"

WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
MAX_BULLETS :: 64
MAX_DRONES :: 12

Input_State :: struct {
  move:         ray.Vector2,
  fire_pressed: bool,
  reset_pressed: bool,
}

Player_State :: struct {
  position: ray.Vector2,
  velocity: ray.Vector2,
  speed:    f32,
  size:     f32,
}

Bullet_State :: struct {
  active:   bool,
  position: ray.Vector2,
  velocity: ray.Vector2,
  ttl:      f32,
}

Drone_State :: struct {
  active:   bool,
  position: ray.Vector2,
  velocity: ray.Vector2,
  radius:   f32,
}

World_State :: struct {
  frame:        int,
  elapsed:      f32,
  spawn_timer:  f32,
  arena:        ray.Rectangle,
  bullets:      [MAX_BULLETS]Bullet_State,
  drones:       [MAX_DRONES]Drone_State,
}

Hud_State :: struct {
  reloads: int,
  resets:  int,
  score:   int,
  message: cstring,
}

Game_State :: struct {
  input:  Input_State,
  player: Player_State,
  world:  World_State,
  hud:    Hud_State,
}
