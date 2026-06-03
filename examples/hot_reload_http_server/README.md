# Hot Reload HTTP Server

This example is a small localhost HTTP server. It demonstrates a request loop
instead of a frame loop: production `main.odin` listens on
`http://127.0.0.1:8099`, accepts requests, and calls reloadable routing logic.

The reload adapter serves one request, then calls `probe_reload.checkpoint`.
When code has been rebuilt, the current request finishes first and the next
request uses the new route logic.

From the Probe repo root:

```sh
odin build cmd/probe -out:probe
odin run examples/hot_reload_http_server
curl http://127.0.0.1:8099/status
```

For reload:

```sh
./probe reload run examples/hot_reload_http_server/reload/reload.conf
```

In another terminal:

```sh
./probe reload watch examples/hot_reload_http_server/reload/reload.conf
```

Edit `server.odin`, save, then make another request with `curl`. The server
preserves request counters and route metrics across reloads. The listener is
stored in durable state and is closed only when the process exits.
