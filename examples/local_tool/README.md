# Local Tool

This example is a long-running local worker/tool, not a game and not a server.
It processes small documents into an index and report.

It demonstrates composed durable state without forcing the whole program into
one large flat struct. `Tool_State` owns `Parser_State`, `Index_State`, and
`Report_State`, and worker functions take pointers to the specific subsystem
they need.

Production run:

```sh
odin run examples/local_tool
```

Reload run:

```sh
odin build cmd/olive -out:olive
./olive run examples/local_tool/reload
```

In another terminal:

```sh
./olive watch examples/local_tool/reload
```

Edit `main.odin` to change parsing/reporting behavior. The durable parser,
index, and report state continue across reloads.
