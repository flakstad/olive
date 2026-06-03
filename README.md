# Olive

`olive` is live-development tooling for Odin. Its main feature is a generic
hot-reload workflow for normal Odin programs. It also keeps the older
scratch-eval tools for quick package-context experiments.

Odin remains the source of truth: Olive generates ordinary Odin wrappers and
uses the real Odin compiler.

## Build

```sh
odin build cmd/probe -out:olive
```

## Hot Reload

Create a starter program:

```sh
./olive init scratch
cd scratch
odin run .
```

Run the resident reload host:

```sh
../olive run reload/reload.conf
```

In another terminal, rebuild manually:

```sh
../olive rebuild reload/reload.conf
```

Or keep a watcher running:

```sh
../olive watch reload/reload.conf
```

Other reload commands:

```sh
./olive check reload/reload.conf
./olive generate reload/reload.conf
./olive paths reload/reload.conf
./olive paths reload/reload.conf --json
./olive clean reload/reload.conf
```

`check` validates the config, writes generated wrappers, and runs `odin check`
on both the reloadable module wrapper and the resident host wrapper.

`run --json` emits structured reload events for editor integrations:

```sh
./olive run reload/reload.conf --json
```

Generated host/module wrappers and build outputs live under `.probe/reload/`.
Module rebuilds compile to a temporary library first and publish the watched
library only after the build succeeds, so the resident host never observes a
half-written dynamic library.

State layout changes are rejected. If you change the root state layout, stop
and restart `olive run`. Any `olive watch` process can stay running.

## Reload Adapter

For an existing program, add a `reload/` directory beside your normal Odin
package:

```text
my_program/
  main.odin
  state.odin
  game.odin
  reload/
    reload.odin
    reload.conf
```

The adapter package is where reload-only code lives:

```odin
package reload

import "core:fmt"
import program ".."
import probe_reload "../path/to/olive/src/probe_reload"

Program_State :: program.Program_State

init :: proc(state: ^Program_State) {
    program.init(state)
}

on_load :: proc(state: ^Program_State) {
    _ = state
    fmt.println("reloaded")
}

run :: proc(state: ^Program_State, host: ^probe_reload.Run_Host) {
    _ = host
    program.tick(state)
}
```

Minimal `reload.conf`:

```text
package=.
runtime=/path/to/olive/src/probe_reload
state=Program_State
run=run
init=init
on_load=on_load
module_name=reload
watch=..
generated_dir=../.probe/reload/generated
build_dir=../.probe/reload/build
```

Required adapter proc:

```odin
run :: proc(state: ^Program_State, host: ^probe_reload.Run_Host)
```

Optional adapter procs:

```odin
init :: proc(state: ^Program_State)
on_load :: proc(state: ^Program_State)
on_unload :: proc(state: ^Program_State)
force_reload :: proc(state: ^Program_State) -> bool
force_restart :: proc(state: ^Program_State) -> bool
host_init :: proc()
host_shutdown :: proc()
```

Olive owns the development loop. It calls `run(state, host)` repeatedly and
checks for reloads between calls. Keep `run` to one frame, one request poll, one
small batch, or another short unit of work. If your normal code blocks forever
inside `run`, Olive cannot safely swap code until that proc returns.

Use `probe_reload.request_exit(host)` from `run` when the resident reload host
should stop. Otherwise, return normally and Olive will call `run` again.

The durable state contract is one root state, not one giant flat struct. Compose
smaller subsystem structs inside the root and pass pointers to the subsystem
state each function needs.

## Scratch Eval

Run a package-context expression:

```sh
./olive eval /path/to/package 'target.some_proc()'
```

For void procedures or statement snippets:

```sh
./olive eval /path/to/package 'target.do_work()' --no-print
```

Check without running:

```sh
./olive eval /path/to/package 'target.some_proc()' --check
```

Inspect generated Odin:

```sh
./olive eval /path/to/package 'target.some_proc()' --show
```

Write generated source to a file:

```sh
./olive eval /path/to/package 'target.some_proc()' --generated /tmp/olive-runner.odin
```

Store commands:

```sh
./olive store path /path/to/package
./olive store save /path/to/package answer '42'
./olive store load /path/to/package answer
./olive store list /path/to/package
./olive store rm /path/to/package answer
```

Value slots are plain text files under `/path/to/package/.probe/values/` by
default. Set `PROBE_STORE_DIR` to use a different store location.

## Examples

- `examples/hot_reload_raylib`: Raylib frame loop with input, rendering,
  composed durable state, and reload-only adapter code.
- `examples/hot_reload_http_server`: localhost HTTP request loop with durable
  listener state and reloadable routing logic.
- `examples/hot_reload_local_tool`: worker/tool loop with composed subsystem
  state.

## Emacs

The repo includes an Emacs integration at `emacs/olive.el`.

Minimal setup:

```elisp
(add-to-list 'load-path "<path-to>/olive/emacs")
(require 'olive)

;; If you use odin-mode:
(add-hook 'odin-mode-hook #'olive-setup-odin-mode-keys)
```

Build `./olive` first, or customize `olive-command`.

Default commands:

- `M-x olive-run-expression`
- `M-x olive-check-expression`
- `M-x olive-run-line`
- `M-x olive-run-region`
- `M-x olive-run-comment-block`
- `M-x olive-run-proc`
- `M-x olive-store-save`
- `M-x olive-store-load`
- `M-x olive-init`
- `M-x olive-check`
- `M-x olive-run`
- `M-x olive-run-json`
- `M-x olive-rebuild`
- `M-x olive-watch`
- `M-x olive-stop-run`
- `M-x olive-stop-watch`
- `M-x olive-paths`
- `M-x olive-clean`

Normal Odin package commands should use `odin run`, `odin check`, `odin build`,
and `odin test` directly. Olive no longer forwards those commands.

## Tests

```sh
./scripts/test_tooling.sh
```

That script runs:

```sh
odin check cmd/probe
odin test tests -define:ODIN_TEST_LOG_LEVEL=warning
emacs -Q --batch -f batch-byte-compile emacs/olive.el
```
