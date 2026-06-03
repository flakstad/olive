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

## Hot Reload

Olive is meant to make the normal edit-build-run cycle feel more like a live
development loop. Keep the program running, edit ordinary Odin files, and let
the reload host pick up the rebuilt module without throwing away state. This is
useful for games, local tools, servers, simulations, editors, and other programs
where restarting the whole process interrupts the work.

Create a starter project:

```sh
./olive init scratch
cd scratch
odin run .
```

Run the reload host:

```sh
../olive run
```

In another terminal, keep the reloadable module rebuilding as you save files:

```sh
../olive watch
```

Or build manually:

```sh
../olive build
```

The reload adapter's `run` proc should return regularly. Olive calls it
repeatedly and checks for reloads between calls. For a game that usually means
one frame; for a server, one request poll; for a worker, one small batch.

If you change the root state layout, restart `olive run`. The watcher can stay
running.

## Scratch Eval

Scratch eval is mostly intended for editor integrations. From Emacs, or another
editor integration, you can run a selected expression, the current line, a proc
call, or a comment block without editing your program's `main`.

Comment blocks are a convenient way to keep small experiments near the code:

```odin
/*
add(5, 2)
some_package_local_proc(1, 2)
*/
```

Olive temporarily generates an Odin runner for the selected code, compiles it
with `odin`, and shows the result back in the editor.

You can also run eval from the CLI:

```sh
./olive eval /path/to/package 'target.some_proc()'
./olive eval /path/to/package 'target.some_proc()' --check
```

## Examples

The examples are the best way to see the reload pattern in context:

- [`examples/hot_reload_raylib`](examples/hot_reload_raylib/README.md): a Raylib game loop.
- [`examples/hot_reload_http_server`](examples/hot_reload_http_server/README.md): an idle-friendly local HTTP server.
- [`examples/hot_reload_local_tool`](examples/hot_reload_local_tool/README.md): a long-running local worker with composed durable state.

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
