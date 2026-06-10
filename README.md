<p align="center">
  <img src="olive.png" alt="Olive logo" width="96">
</p>

# Olive

Olive is live-development tooling for Odin. It gives you hot reload for
long-running Odin programs: change code, let Olive rebuild it, and load it into
the running process without losing the program state you were testing.

All that's required is adding a tiny development-only `reload/reload.odin` file to
your project. During development, you start the program with `olive run`
instead of `odin run .`, and Olive uses that reload file as the dev entry
point.

You do not have to change your `main` proc or regular Odin build. Olive only
reads the reload adapter you point it at.

The workflow is inspired by Lisp/Clojure-style live development and Karl
Zylinski's Odin Raylib hot-reload template.

## Install

Build the CLI:

```sh
odin build cmd/olive
```

## Quickstart

Create a small starter program:

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

Now edit the printed text in `main.odin`. Olive rebuilds the changed code and
loads it into the running program. The tick counter keeps going.

![Olive simple demo](olive-simple-demo.gif)

`olive init` creates a small Odin program plus a `reload` directory. `main.odin`
has the real `main`, state, and app logic. `reload/reload.odin` is dev wiring:
it names the state type and gives Olive a small `run` proc to call while the
host is alive.

Treat the generated `reload` package as glue. Most iteration should happen in
your program files.

## When Olive Helps

Olive helps when the state you want to test is annoying to recreate: a player
moved to a specific place in a game, an editor opened on a deep document state,
a UI navigated to a nested screen, or a simulation evolved to an interesting
moment.

For small CLIs, libraries, batch jobs, and programs whose state already lives
outside the process, plain stop/build/run may still be better.

## How Hot Reload Works

Development uses two processes:

- `olive run` starts the host, builds the first reloadable module, and keeps
  calling your reload adapter's `run` proc.
- `olive watch` rebuilds the reloadable module whenever watched Odin files
  change.

Use `olive build` instead of `olive watch` when you want manual rebuilds.

Olive is opt-in: it only runs when you start the reload adapter through the
CLI.

## Add Olive To An Existing Project

1. Keep your existing `main` proc as the production entry point.
2. Put long-lived program data in one root state type, for example
   `Program_State`.
3. Add a small `reload` directory that wires Olive to your program. Start with
   `olive init` in a temporary directory and copy the generated `reload` shape.
4. In `reload/reload.odin`, define `Reload_State :: your_package.Program_State`
   and a `run` proc that advances the app by one frame, tick, poll, or UI
   update.

Then run the host from the project root:

```sh
olive run
```

In another terminal, leave the watcher running:

```sh
olive watch
```

`olive run`, `olive build`, and `olive watch` use `reload/` by default. Pass a
reload directory only when your project uses a different location.

## Durable State

Olive preserves one root state value across reloads. Use that root for the
state you care about keeping: world data, simulation state, loaded documents,
UI state, and pointers to subsystems that should survive code reloads.

The root does not need to be one flat struct. It can own or point to smaller
subsystem structs:

```odin
Program_State :: struct {
  world:    World_State,
  renderer: ^Renderer_State,
  assets:   ^Asset_Cache,
}
```

Changing proc bodies is the easy case: the host stays alive, the next build is
loaded, and state continues. Changing the layout of the root state type means
you need to restart `olive run`, because the host owns memory with the old
layout. Any `olive watch` process can stay running.

## Minimal Reload Adapter

`reload/reload.odin` is the only file Olive reads for reload setup. Keep it
small: import your app package, name the state type, and forward Olive's calls
to regular app procs.

```odin
package reload

import app ".."
import olive_reload "../../../src/olive_reload"

Reload_State :: app.Program_State

run :: proc(state: ^Reload_State, host: ^olive_reload.Run_Host) {
  _ = host
  app.frame_or_tick(state)
}
```

Required declarations:

- `Reload_State :: app.Program_State`: the one root state type preserved by the
  resident host.
- `run :: proc(state: ^Reload_State, host: ^olive_reload.Run_Host)`: one small
  unit of work. Return regularly so Olive can check for rebuilt code.

## Examples

![Olive raylib demo](olive-raylib-demo.gif)

- [`examples/raylib`](examples/raylib): a Raylib game loop demonstrates using some extra
  procs for managing the host state.
- [`examples/local_tool`](examples/local_tool): an example showing composed
  durable state.

```sh
odin build cmd/olive
./olive run examples/raylib/reload
```

```sh
./olive watch examples/raylib/reload
```

## Adapter Reference

Optional lifecycle hooks are detected by name:

- `init :: proc(state: ^Reload_State)`: called for the initial load and after a
  forced restart. Use it to mirror production startup.
- `on_load :: proc(state: ^Reload_State)`: called after a successful reload, not
  on the initial load.
- `on_unload :: proc(state: ^Reload_State)`: called before unloading the current
  generation and before a forced restart resets state.
- `on_resource_change :: proc(state: ^Reload_State, path: string)`: called by
  `olive run` when a watched non-code resource changes.
- `force_reload :: proc(state: ^Reload_State) -> bool`: return true to request a
  reload check even if the library timestamp did not change.
- `force_restart :: proc(state: ^Reload_State) -> bool`: return true to reset
  durable state with the current compatible layout.
- `host_init :: proc()`: called once in the resident host before state is
  created. Use this for process-owned resources such as windows.
- `host_shutdown :: proc()`: called once before the resident host exits.

Optional adapter constants:

- `Olive_Module_Name :: "name"`: basename for generated reload binaries.
- `Olive_Odin_Args :: "-define:FOO=true"`: extra args passed to generated
  `odin check` and `odin build` commands.
- `Olive_Watch :: ".."`: comma-separated paths to poll for `.odin` changes,
  relative to the reload directory.
- `Olive_Watch_Resources :: "../assets,../templates"`: comma-separated paths to
  poll for non-code resource changes, relative to the reload directory.
- `Olive_Watch_Ignore :: ".git,.olive,.worktrees"`: comma-separated directory
  names to skip while scanning watched source and resource paths. Names match
  exact path components. Define an empty string to scan all directories.
- `Olive_Watch_Debounce_MS :: "150"`: quiet period after a detected change
  before rebuilding.

Initialize durable state in your app startup path and mirror that through the
adapter's `init` proc when needed. Use `on_load` for reload-only work such as
refreshing function tables, logging a reload, or reconnecting code that depends
on the new module generation.

Host hooks are for resources that should not be recreated on every reload. For
example, the Raylib example opens the window in `host_init`, closes it in
`host_shutdown`, and keeps drawing one frame per `run`.

## Resource Watching

Code reload and resource reload are separate. `olive watch` watches Odin files
and rebuilds the module. `olive run` can also watch external resource files and
notify the running program without rebuilding or swapping the module.

Resource watching is not just for games. Games can reload shaders, textures,
levels, and audio. UI/editor tools can reload themes, templates, documents, or
preview data. Simulations can reload scenarios, parameters, or input data.

Add resource paths and a hook to the adapter:

```odin
Olive_Watch_Resources :: "../assets,../templates"

on_resource_change :: proc(state: ^Reload_State, path: string) {
  app.reload_resource(state, path)
}
```

The hook receives the changed path and decides what to do. Olive ignores `.odin`
files in resource watches; source files should go through `olive watch`.

## Broadcast On Reload

For browser or UI clients connected to a running process, `on_load` is a good
place to push a fresh snapshot after a reload:

```odin
on_load :: proc(state: ^Reload_State) {
  app.broadcast_snapshot_to_connected_clients(state)
}
```

Keep long-lived connections, client lists, and current application data in
durable state or host-owned state. Avoid storing callbacks or function pointers
from reloadable code in those long-lived clients; after a reload, those pointers
can refer to old code. Let the new generation's `on_load` serialize or render
the current state and push it again.

## Experimental: Scratch Eval

![Olive eval demo](olive-eval-demo.gif)

Olive also has experimental scratch eval helpers. The idea is to get some of
the feel of a REPL workflow in Odin: write a small expression next to the code
you are thinking about, run it from the editor, see the result, and keep moving
without making a temporary `main`.

This is not a persistent Odin REPL. Each eval writes a small Odin runner and
calls `odin`. The useful part is the workflow: quick package-context
experiments, selected expressions, comment-block scratchpads, and saved outputs
you can load again later. That saved-output store gives you a small substitute
for the bits of state you would keep around in a REPL session.

For example, try a call next to the code it exercises:

```odin
add :: proc(a, b: int) -> int {
  return a + b
}

// add(5, 2)  <cursor>
```

With the cursor on the comment line, an editor command can evaluate just
`add(5, 2)` in the package context and show the result. Multi-line comment
blocks work the same way:

```odin
/*
first := add(5, 2)
second := add(first, 10)
second
*/  <cursor>
```

Scratch eval can also save successful eval output under a name. Olive stores
these values under the package's `.olive/values` directory by default, or under
`OLIVE_STORE_DIR` if that environment variable is set.

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

## Feedback

Pull requests, issues, and feedback are welcome. Bug reports and notes from
trying Olive in real Odin projects are useful.

## License

MIT. See [`LICENSE`](LICENSE).

## Inspiration

Olive's hot-reload workflow is inspired in part by Karl Zylinski's Odin Raylib
hot reload template:

https://github.com/karl-zylinski/odin-raylib-hot-reload-game-template

The broader motivation comes from Clojure and Lisp development: keep the
program alive, evaluate small pieces of code, and avoid restarting the whole
system all the time.
