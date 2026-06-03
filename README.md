# Olive

Olive is live-development tooling for Odin.

Its main feature is a small, generic hot-reload workflow for ordinary Odin
programs. Your production program stays normal: it can still be built and run
with `odin build` and `odin run`. Olive adds a reload adapter for development,
so code changes can be rebuilt and loaded into a running host while durable
state is preserved.

Olive also includes scratch eval helpers for quick package-context experiments.
They generate ordinary Odin and use the real Odin compiler.

## Install

Build the CLI:

```sh
odin build cmd/olive -out:olive
```

## Quickstart

```sh
./olive init scratch
cd scratch
../olive run
```

In another terminal:

```sh
cd scratch
../olive watch
```

Now edit the printed text in `main.odin`. Olive builds the changed code and
reloads it into the running program without resetting its durable state, so the
tick counter keeps going.

## Hot Reload

Olive is meant to make the normal edit-build-run cycle feel more like a live
development loop. Keep the program running, edit ordinary Odin files, and let
the reload host pick up the rebuilt module without throwing away state. This is
useful for games, local tools, servers, simulations, editors, and other programs
where restarting the whole process interrupts the work.

The development workflow has two moving parts:

- `olive run` starts the program in development mode. It builds a small resident
  host and a reloadable module, then keeps calling your reload adapter's `run`
  proc.
- `olive build` builds the reloadable module manually. `olive watch` does the
  same automatically whenever watched Odin files change.

Your production program stays separate from this. Keep a normal `main` proc and
run it with `odin run .` or build it with `odin build .` when you do not want the
reload workflow involved.

## Getting Started

Start from scratch:

```sh
./olive init scratch
cd scratch
odin run .
../olive run
```

`olive init` creates a small ordinary Odin program plus a `reload` directory.
The ordinary program lives in `main.odin`: it has a durable state type, an
update proc that prints once per second, and a normal production `main`. The
reload directory contains `reload.odin`, which adapts that program to Olive's
development host, and `reload.conf`, which tells Olive what package to build,
what state type to preserve, and where to put generated files.

For the starter, treat `reload/reload.odin` as generated wiring. Edit
`main.odin` and leave the reload package alone unless you are changing how the
development host connects to your program.

The reload adapter contains the development entry point. Its `run` proc is what
Olive calls while the host is alive. In the generated starter that proc advances
the program by one small step, then returns so Olive can check whether a newly
built module is ready to load.

`odin run .` is not required for hot reload. It is there to show that the
generated starter is still a normal Odin program before you run it through
Olive.

Add Olive to an existing project:

1. Keep your existing `main` proc as the production entry point.
2. Put durable program data in one root state type, for example
   `Program_State`.
3. Add a small `reload` directory that wires Olive to your program. Start with
   `olive init` in a temporary directory and copy the generated `reload` shape.
4. Point `reload/reload.conf` at your program package, state type, and update
   proc.

After that setup, normal iteration should happen in your program files, not in
the reload package.

Then run the development host from the project root:

```sh
olive run
```

In another terminal, build the reloadable module when you save changes:

```sh
olive build
```

Or leave the watcher running:

```sh
olive watch
```

`olive run`, `olive build`, and `olive watch` use `reload/reload.conf` by
default. Pass a config path only when your project uses a different location.

## State Management

Olive preserves one root state value across reloads. Model that root state as
the durable state of the running program: world data, loaded documents, server
configuration, caches, UI state, and pointers to subsystems that should survive
code reloads.

You do not have to put everything in one flat struct. Prefer a root state that
owns or points to smaller subsystem structs:

```odin
Program_State :: struct {
    world:    World_State,
    renderer: ^Renderer_State,
    assets:   ^Asset_Cache,
}
```

Initialize durable state in your normal production startup path and mirror that
through the reload adapter's optional `init` proc. Use `on_load` for reload-only
work such as refreshing function tables, logging a reload, or reconnecting code
that depends on the new module generation.

The adapter's `run` proc should return regularly. For a game that usually means
one frame; for a server, one request poll; for a worker, one small batch.

Changing proc bodies is the happy path: run stays alive, the next build is
loaded, and state continues. Changing the layout of the root state type is
different. Olive rejects that reload because the resident host owns the old
memory layout. When that happens, stop and restart `olive run`. Any
`olive watch` process can stay running; it will keep building the new module.

## Examples

The examples are the best way to see the reload pattern in context:

- [`examples/raylib`](examples/raylib/README.md): a Raylib game loop.
- [`examples/http_server`](examples/http_server/README.md): an idle-friendly local HTTP server.
- [`examples/local_tool`](examples/local_tool/README.md): a long-running local worker with composed durable state.

## Scratch Eval

Scratch eval is mostly intended for editor integrations. From Emacs, or another
editor integration, you can run a selected expression, the current line, a proc
call, or a comment block without editing your program's `main`.

It is useful for trying calls near the code they exercise:

```odin
add :: proc(a, b: int) -> int {
    return a + b
}

// add(5, 2)  <cursor>
```

With the cursor on the comment line, an editor command can evaluate just
`add(5, 2)` in the package context and show the result. The comment stays in
your source as a small scratch note.

Multi-line comment blocks work the same way, except Olive evaluates the whole
block:

```odin
/*
first := add(5, 2)
second := add(first, 10)
second
*/  <cursor>
```

Olive temporarily generates an Odin runner for the selected code, compiles it
with `odin`, and shows the result back in the editor. For a single `//` comment
line, Olive evaluates that line. For a `/* ... */` block, it evaluates the whole
block.

Scratch eval can also save successful eval output under a name. This is meant
for editor integrations doing exploratory work: evaluate something expensive or
useful, save the printed result, then load it later without turning that scratch
step into program code. Olive stores these values under the package's `.olive`
directory by default, or under `OLIVE_STORE_DIR` if that environment variable is
set.

You can also run eval from the CLI:

```sh
./olive eval /path/to/package 'target.some_proc()'
./olive eval /path/to/package 'target.some_proc()' --check
./olive eval /path/to/package 'target.some_proc()' --save latest
./olive store load /path/to/package latest
```

## Emacs

The Emacs integration lives in [`emacs/olive.el`](emacs/olive.el).

```elisp
(add-to-list 'load-path "<path-to>/olive/emacs")
(require 'olive)
(add-hook 'odin-mode-hook #'olive-setup-odin-mode-keys)
```

Build `./olive` first, or customize `olive-command`.

## Inspiration

Olive's hot-reload workflow is inspired in part by Karl Zylinski's Odin Raylib
hot reload template:

https://github.com/karl-zylinski/odin-raylib-hot-reload-game-template

The broader motivation comes from Clojure and Lisp development: keeping a
program alive, evaluating small pieces of code, and getting a tight feedback
loop without constantly restarting the whole system. Olive is an Odin-shaped
attempt at that workflow using generated Odin and the real compiler.
