# probe

`probe` is scratch execution tooling for Odin. It makes small experiments cheap
without changing Odin itself.

Odin is compiled and statically checked, so this is not a REPL or interpreter.
The goal is to make common exploratory actions cheap:

- run one proc without editing `main`
- run a small package-context expression
- generate a temporary runner package
- compile/run with the real Odin compiler
- show the generated Odin when debugging
- persist explicit text values between probes

The core rule: Odin remains the source of truth. `probe` generates ordinary
Odin and invokes `odin run` or `odin check`.

## Current Commands

Build the compiled CLI with:

```sh
odin build cmd/probe -out:probe
```

External package probing:

```sh
./probe eval /path/to/package 'target.some_proc()'
```

This generates a temporary Odin program like:

```odin
package main

import "core:fmt"
import target "/path/to/package"

main :: proc() {
    result := target.some_proc()
    fmt.println(result)
}
```

For void procedures or statement snippets:

```sh
./probe eval /path/to/package 'target.do_work()' --no-print
```

To inspect generated Odin:

```sh
./probe eval /path/to/package 'target.some_proc()' --show
```

Compile diagnostics that point at the generated probe runner are remapped back
to `<probe>:line:column` when the error is inside the probed snippet. Errors in
the target package still report the underlying Odin file.

The compiled Odin CLI also supports writing generated source to a file while
keeping stdout as just the probe result:

```sh
./probe eval /path/to/package 'target.some_proc()' --generated /tmp/probe-runner.odin
```

To check without running:

```sh
./probe eval /path/to/package 'target.some_proc()' --check
```

To save successful stdout into an explicit package-local value slot:

```sh
./probe eval /path/to/package 'target.some_proc()' --save last-result
./probe store load /path/to/package last-result
```

Value slots are plain text files under `/path/to/package/.probe/values/` by
default. Set `PROBE_STORE_DIR` to use a different store location.

Store commands:

```sh
./probe store path /path/to/package
./probe store save /path/to/package answer '42'
./probe store load /path/to/package answer
./probe store list /path/to/package
./probe store rm /path/to/package answer
```

Standard Odin package commands:

```sh
./probe run /path/to/package
./probe build /path/to/package
./probe check /path/to/package
./probe test /path/to/package
```

Hot reload workflow:

```sh
./probe reload init scratch
cd scratch
odin run .
../probe reload run reload/reload.conf
```

`probe reload init` creates a generic starter program and a commented
`reload/reload.conf` with defaults. The starter is a normal Odin program
first: `main.odin`, `state.odin`, and `game.odin` are all `package main` and
can be built or run with ordinary Odin commands. The reload workflow is
optional development tooling in `reload/reload.odin`.

The reload adapter imports the parent package and the Probe reload runtime.
Generated host/module wrappers and build outputs live under `.probe/reload/`.
Module rebuilds compile to a temporary library first and publish the watched
library only after the build succeeds, so the resident host does not observe a
half-written dynamic library.

While the host is running, edit your normal program files and rebuild only the
reloadable library from another terminal:

```sh
../probe reload rebuild reload/reload.conf
```

Or keep a rebuild watcher running in that second terminal:

```sh
../probe reload watch reload/reload.conf
```

`watch` builds the reloadable module once, then polls the configured watch
paths for `.odin` changes. Compile failures are printed, but the watcher keeps
running so the resident host can continue using the last successful generation.
The generated config uses `watch=..` because the config lives in `reload/`.
Set `watch=..,../shared` to include sibling local packages and
`watch_debounce_ms=150` to tune the quiet period before rebuild.

Inspect the generated paths and canonical commands:

```sh
../probe reload check reload/reload.conf
../probe reload paths reload/reload.conf
../probe reload paths reload/reload.conf --json
```

`check` validates the config, writes the generated wrappers, and runs
`odin check` on both the reload module wrapper and the resident host wrapper.
That catches missing or wrongly typed adapter procs before you start the host.

Start the resident host with structured reload events for editor tooling:

```sh
../probe reload run reload/reload.conf --json
```

Structured events are printed as line-delimited records prefixed with
`PROBE_RELOAD_EVENT<TAB>` followed by JSON. `M-x probe-reload-run-json`
parses those records live in Emacs, reports reload status in the minibuffer,
and leaves normal app output visible in `*Probe Reload*`.

Remove generated wrappers, build outputs, temporary libraries, and shadow
copies:

```sh
../probe reload clean reload/reload.conf
```

For an existing program, add a `reload/` directory beside your normal
`main.odin`:

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

import program ".."
import probe_reload "../path/to/probe/src/probe_reload"

Program_State :: program.Program_State

init :: proc(state: ^Program_State) {
    program.init(state)
}

on_load :: proc(state: ^Program_State, is_reload: bool) {
    program.on_load(state, is_reload)
}

run :: proc(state: ^Program_State, host: ^probe_reload.Run_Host) {
    for {
        program.tick(state)

        if probe_reload.checkpoint(host) {
            return
        }
    }
}
```

Add `reload/reload.conf`:

```text
package=.
runtime=/path/to/probe/src/probe_reload
state=Program_State
run=run
init=init
on_load=on_load
module_name=reload
watch=..
watch_debounce_ms=150
# odin_args=-define:EXAMPLE=true
force_reload=force_reload
force_restart=force_restart
host_init=host_init
host_shutdown=host_shutdown
on_layout_change=reject
generated_dir=../.probe/reload/generated
build_dir=../.probe/reload/build
```

Required config:

```text
package=.
runtime=/path/to/probe/src/probe_reload
state=Program_State
run=run
```

Required adapter proc:

```odin
run :: proc(state: ^Program_State, host: ^probe_reload.Run_Host)
```

Optional adapter procs:

```odin
init :: proc(state: ^Program_State)
on_load :: proc(state: ^Program_State, is_reload: bool)
on_unload :: proc(state: ^Program_State)
force_reload :: proc(state: ^Program_State) -> bool
force_restart :: proc(state: ^Program_State) -> bool
host_init :: proc()
host_shutdown :: proc()
```

Your reload adapter owns its loop. Probe calls `run(state, host)`. Inside
`run`, call `probe_reload.checkpoint(host)` at a safe boundary. If it returns
`true`, return from `run`; Probe will load the new code generation and call the
new `run`.

If `checkpoint` returns `false`, continue normally. If your production program
blocks on an event, waits for a frame, receives a request, or advances a job,
keep doing that in normal application code and call it from the adapter. Probe
does not own timing.

The durable state contract is one root state, not one giant blob. Compose
smaller structs inside the root and pass pointers to those nested values:

```odin
Game_State :: struct {
    world:  World_State,
    hud:    Hud_State,
    assets: Asset_State,
}

run :: proc(state: ^Game_State, host: ^probe_reload.Run_Host) {
    for {
        update_world(&state.world)
        draw(&state.world, &state.hud, &state.assets)
        if probe_reload.checkpoint(host) {
            return
        }
    }
}
```

Examples:

- `examples/hot_reload_raylib`: Raylib frame loop with input, rendering,
  composed durable state, and reload-only adapter code.
- `examples/hot_reload_http_server`: localhost HTTP request loop with durable
  listener state and reloadable routing logic.
- `examples/hot_reload_local_tool`: worker/tool loop with subsystem pointers
  rewired in `on_load`.

Optional hooks:

- `force_reload`: return true to request a reload even when the library mtime
  has not changed. A game might wire this to F5.
- `force_restart`: return true to reset durable state with the current
  compatible layout. A game might wire this to F6.
- `host_init`/`host_shutdown`: called by the resident host outside reloadable
  generations. Use these for process-owned resources such as a Raylib window.

Probe keeps old dynamic-library generations loaded until the session shuts
down. This mirrors the practical game-template pattern where durable state may
still point at string literals or static data from an older generation.
`examples/hot_reload_raylib` intentionally keeps a `cstring` HUD message in
durable state to demonstrate that pattern.

State layout changes are still rejected. Because the generated host owns a
typed `state := program.State{}` value, changing the state layout requires
rebuilding and restarting the host.

## Tests

The feedback loop now puts the compiled Odin CLI first:

```sh
./scripts/test_tooling.sh
```

That script runs the full local loop:

```sh
odin check cmd/probe
odin test tests -define:ODIN_TEST_LOG_LEVEL=warning
emacs -Q --batch -f batch-byte-compile emacs/probe.el
```

`odin test tests` covers the core renderer/helpers and builds/runs the compiled
CLI for Odin-owned behavior: external probing, internal probing, scratch-line
commenting, package commands, generated-file output, and value storage.
The script also builds a temporary compiled CLI and runs five probes in parallel
to catch output-binary collisions.

## Emacs

The repo includes a small Emacs integration at `emacs/probe.el`. It requires the
compiled Odin `probe` CLI and displays command output in `*Probe*`.

Minimal setup:

```elisp
(add-to-list 'load-path "<path-to>/probe/emacs")
(require 'probe)

;; If you use odin-mode:
(add-hook 'odin-mode-hook #'probe-setup-odin-mode-keys)
```

Build `./probe` first.

Default commands:

Reload commands use `reload/reload.conf` automatically when it exists. Call
them with a prefix argument to choose a different config file.

- `M-x probe-run-expression`: prompt for an Odin expression and print result
- `M-x probe-run-expression-save`: run an expression and save stdout to a value slot
- `M-x probe-run-line`: run current line, or whole `/* ... */` block at point
- `M-x probe-run-region`: run selected expression; with prefix, run as statements
- `M-x probe-check-expression`: compile-check a generated runner
- `M-x probe-run-comment-block`: run a contiguous `/* ... */` comment block as code
- `M-x probe-run-proc`: call `target.<proc>(<args>)`
- `M-x probe-run-proc-no-args`: call `target.<symbol-at-point>()`
- `M-x probe-store-save`: write a named plain-text value
- `M-x probe-store-load`: print a named value in `*Probe*`
- `M-x probe-store-list`: list value slots
- `M-x probe-store-remove`: remove a value slot
- `M-x probe-store-path`: show the active store directory
- `M-x probe-run-package`: run `probe run .` in the current package
- `M-x probe-build-package`: run `probe build .` in the current package, even when it is not a `main` package
- `M-x probe-check-package`: run `probe check .` in the current package, even when it is not a `main` package
- `M-x probe-test-package`: run `probe test .` in the current package
- `M-x probe-reload-init`: create a generic hot-reload starter directory
- `M-x probe-reload-check`: check a reload config without building
- `M-x probe-reload-run`: build and run `probe reload run reload/reload.conf`
- `M-x probe-reload-run-json`: build and run with live structured reload events in `*Probe Reload Run*`
- `M-x probe-reload-rebuild`: rebuild only the reloadable library
- `M-x probe-reload-watch`: watch configured paths and rebuild the reloadable library in `*Probe Reload Watch*`
- `M-x probe-reload-stop-run`: stop the live reload host
- `M-x probe-reload-stop-watch`: stop the live reload watcher
- `M-x probe-reload-paths`: show generated reload paths
- `M-x probe-reload-clean`: remove generated reload files and build outputs
- `M-x probe-run-project`: run `probe run .` at the detected project root
- `M-x probe-build-project`: run `probe build .` at the detected project root
- `M-x probe-check-project`: run `probe check .` at the detected project root
- `M-x probe-test-project`: run `probe test .` at the detected project root
- `M-x probe-toggle-test-after-build`: optionally test after successful package builds
- `M-x probe-toggle-show-generated`: also show generated Odin

Default `odin-mode` keys installed by `probe-setup-odin-mode-keys`:

- `C-c C-e`: run current call, line, or `/* ... */` block and show result inline
- `C-c C-p`: run current call, line, or `/* ... */` block and open the result buffer
- `C-c C-i`: insert result as a `// => ...` comment below the probed unit
- `C-c C-r`: run region
- `C-c C-c`: run the whole current line inline, ignoring cursor subexpression
- `C-c C-x`: run uncommented `/* ... */` block at point
- `C-c C-k`: check prompted expression
- `C-c C-a`: run package main via `probe run .`
- `C-c C-b`: build package via `probe build .`
- `C-c C-v`: check package via `probe check .`
- `C-c C-t`: test package via `probe test .`
- `C-c C-l c`: check reload config, defaulting to `reload/reload.conf`
- `C-c C-l r`: run reload host with structured events
- `C-c C-l w`: run reload watcher
- `C-c C-l b`: rebuild reload module once
- `C-c C-l k`: stop reload host
- `C-c C-l K`: stop reload watcher
- `C-c C-s`: toggle generated Odin display
- `C-c C-z`: switch to result buffer

Build/check/test commands only open `*Probe*` on failure. On success they
report in the minibuffer and leave your window layout alone. Test commands are
an exception in one useful way: successful `odin test .` output is compacted and
shown in the minibuffer, because the test runner's summary is the result you
usually want to see. The default Emacs test command is:

```sh
probe test . -define:ODIN_TEST_LOG_LEVEL=warning
```

That suppresses Odin's verbose successful test-runner info logs while preserving
warnings, errors, and the final summary. Customize `probe-test-args` if you
want different test runner flags.

The package directory defaults to the directory of the current `.odin` file.
That matches Odin's package model for the external probing MVP. The project
directory is detected by walking up to `ols.json`, `odin.json`, or `.git`,
falling back to the current package directory.

Odin has tests out of the box via `odin test .`. Test procedures use Odin's
test attribute, for example:

```odin
import "core:testing"

@(test)
sample_test :: proc(t: ^testing.T) {
    testing.expect_value(t, 2 + 2, 4)
}
```

For scratch calls, keep ordinary Odin calls inside a multiline
comment block and run that block:

```odin
/*
add(5, 2)
some_package_local_proc(1, 2)
*/
```

Place point inside the block and run `C-c C-e` for an inline result, `C-c C-p`
for the result buffer, or `C-c C-i` to insert the result below the block as a
comment. With a prefix argument, the block is treated as statements and
`--no-print` is passed to the CLI.

Inserted result comments look like this and are ignored by later block probes:

```odin
// x := 1
// add(x, 3)
// => 4
```

For ordinary Odin code, if point is just after a call expression, that call is
used instead of the whole line:

```odin
fmt.println(add(5, 2)|)
```

`C-c C-e` runs `add(5, 2)`, not the full `fmt.println(...)` line.

If point is inside a call just after an atom, that atom is used:

```odin
add(5, 2|)
```

`C-c C-e` runs `2`.

Block-comment probing uses internal mode: the package is copied to a scratch
directory, an existing entry `main` is renamed, and the generated probe `main`
runs inside the same package. That means scratch comments can call local names
directly instead of going through `target.`.
