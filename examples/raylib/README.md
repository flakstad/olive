# Raylib

This is a small Raylib game-shaped example using Olive hot reload. Production
code is normal Odin: `main.odin` opens the window, owns the process lifetime,
and calls `frame(&state)` until Raylib says the window should close.

The reload workflow is isolated to `reload/reload.odin`. Its `run` proc draws
one frame and returns; Olive checks for reloads between frames. Because the
reload host does not execute production `main.odin`, the reload adapter uses
`host_init`/`host_shutdown` to initialize the Raylib window once in the
resident host.

From the Olive repo root:

```sh
odin build cmd/olive -out:olive
odin run examples/raylib
./olive check examples/raylib/reload/reload.conf
./olive run examples/raylib/reload/reload.conf
```

In another terminal, edit `examples/raylib/main.odin`, then build
only the reloadable module:

```sh
./olive build examples/raylib/reload/reload.conf
```

Or keep the build watcher running:

```sh
./olive watch examples/raylib/reload/reload.conf
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
