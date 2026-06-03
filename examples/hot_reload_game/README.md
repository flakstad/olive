# Hot Reload Game

This is a small text-mode game that can run normally or with Probe hot reload.
The reload workflow is optional: production code uses the normal `main` proc,
while development reload uses the small adapter in `reload/reload.odin`.

From the Probe repo root:

```sh
odin build cmd/probe -out:probe
odin run examples/hot_reload_game
./probe reload check examples/hot_reload_game/reload/reload.conf
./probe reload run examples/hot_reload_game/reload/reload.conf
```

In another terminal, edit `examples/hot_reload_game/game.odin`, then rebuild
only the reloadable module:

```sh
./probe reload rebuild examples/hot_reload_game/reload/reload.conf
```

For a tighter loop, keep the module watcher running instead:

```sh
./probe reload watch examples/hot_reload_game/reload/reload.conf
```

The normal `main` calls the game code directly. Reload mode calls the adapter's
`run` proc, which calls `probe_reload.checkpoint(host)` at a safe frame
boundary; when a new module is ready it returns so Probe can swap code.

Behavior changes in `run`, `update_world`, or `draw` appear after rebuild.
Changing `Game_State` layout requires restarting the host.
