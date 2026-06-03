# Hot Reload Local Tool

This example is a long-running local worker/tool, not a game and not a server.
It processes small documents into an index and report.

It demonstrates composed durable state without forcing the whole program into
one large flat struct. `Tool_State` owns `Parser_State`, `Index_State`, and
`Report_State`, and worker functions take pointers to the specific subsystem
they need.

Production run:

```sh
odin run examples/hot_reload_local_tool
```

Reload run:

```sh
odin build cmd/probe -out:probe
./probe reload run examples/hot_reload_local_tool/reload/reload.conf
```

In another terminal:

```sh
./probe reload watch examples/hot_reload_local_tool/reload/reload.conf
```

Edit `tool.odin` to change parsing/reporting behavior. The durable parser,
index, and report state continue across reloads.
