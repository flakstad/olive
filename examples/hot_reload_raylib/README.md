# Hot Reload Raylib

This is a small Raylib game-shaped example using Probe hot reload. Production
code is normal Odin: `main.odin` opens the window, owns the process lifetime,
and calls `frame(&state)` until Raylib says the window should close.

The reload workflow is isolated to `reload/reload.odin`. Its `run` proc owns
the development frame loop and calls `probe_reload.checkpoint(host)` once per
frame after drawing. Because the reload host does not execute production
`main.odin`, the reload adapter uses `host_init`/`host_shutdown` to initialize
the Raylib window once in the resident host.

From the Probe repo root:

```sh
odin build cmd/probe -out:probe
odin run examples/hot_reload_raylib
./probe reload check examples/hot_reload_raylib/reload/reload.conf
./probe reload run examples/hot_reload_raylib/reload/reload.conf
```

In another terminal, edit `examples/hot_reload_raylib/game.odin`, then rebuild
only the reloadable module:

```sh
./probe reload rebuild examples/hot_reload_raylib/reload/reload.conf
```

Or keep the rebuild watcher running:

```sh
./probe reload watch examples/hot_reload_raylib/reload/reload.conf
```

The example keeps durable state in `Game_State`, composed from input, player,
world, and HUD structs. Reloading changes behavior/rendering while preserving
that state. Changing `Game_State` layout requires restarting the resident host.
The reload config passes `-define:RAYLIB_SHARED=true` to generated builds so
the resident host and reloadable module share the same Raylib/GLFW library.

Keys:

- `WASD`/arrows: move
- `Space`: fire
- `R`: reset game state, preserving score/reload counters
- `F5`: force a reload check from the app
- `F6`: reset durable state through the reload host
