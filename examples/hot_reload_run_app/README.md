# Hot Reload Run App

This example demonstrates an app that can run normally or with Probe hot
reload. Production code uses the normal `main` proc; development reload wraps
the root package through `reload/reload.odin` and calls
`probe_reload.checkpoint(host)` at one safe boundary.

From the Probe repo root:

```sh
odin build cmd/probe -out:probe
odin run examples/hot_reload_run_app
./probe reload check examples/hot_reload_run_app/reload/reload.conf
./probe reload run examples/hot_reload_run_app/reload/reload.conf
```

In another terminal:

```sh
./probe reload rebuild examples/hot_reload_run_app/reload/reload.conf
```

Or keep the rebuild watcher running:

```sh
./probe reload watch examples/hot_reload_run_app/reload/reload.conf
```

The adapter `run` handles one request cycle, prints status, then calls
`probe_reload.checkpoint(host)`. If it returns true, `run` returns and the
resident host swaps the reloadable module.

Use this pattern for apps with their own request, event, job, or frame loop.
