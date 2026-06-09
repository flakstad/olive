# HTTP Server

This example is a small localhost HTTP server. It demonstrates a request loop
instead of a frame loop: production `main.odin` listens on
`http://127.0.0.1:8099`, accepts requests, and calls reloadable routing logic.

The reload adapter polls for one request and returns. The listener is
nonblocking, so Olive can check for reloads even while the server is idle and
the next request uses the new route logic.

From the Olive repo root:

```sh
odin build cmd/olive -out:olive
odin run examples/http_server
curl http://127.0.0.1:8099/status
```

For reload:

```sh
./olive run examples/http_server/reload
```

In another terminal:

```sh
./olive watch examples/http_server/reload
```

Edit `main.odin` and save. The watcher rebuilds the module, Olive reloads it
while idle, and the next `curl` request uses the new route logic. The server
preserves request counters and route metrics across reloads. The listener is
stored in durable state and is closed only when the process exits.
