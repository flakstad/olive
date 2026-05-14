# odineval

`odineval` is an experiment in REPL-like development tooling for Odin without
changing Odin itself.

Odin is compiled and statically checked, so this is not a real REPL. The goal is
to make common exploratory actions cheap:

- run one proc without editing `main`
- evaluate a small package-context expression
- generate a temporary runner package
- compile/run with the real Odin compiler
- show the generated Odin when debugging

The core rule: Odin remains the source of truth. `odineval` generates ordinary
Odin and invokes `odin run` or `odin check`.

## Current MVP

External package eval:

```sh
python3 -m src.odineval run /path/to/package 'target.some_proc()'
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
python3 -m src.odineval run /path/to/package 'target.do_work()' --no-print
```

To inspect generated Odin:

```sh
python3 -m src.odineval run /path/to/package 'target.some_proc()' --show
```

To check without running:

```sh
python3 -m src.odineval check /path/to/package 'target.some_proc()'
```

## Direction

Two modes matter:

- External eval: generate a separate runner package that imports the target
  package as `target`. This works for exported/package-visible APIs.
- Internal eval: copy or shadow the package into a scratch directory and add a
  temporary runner file in the same package. This should allow calling
  package-local helpers without modifying source files.

External eval is the first milestone. Internal eval is likely the feature that
will make the tool feel closest to Lisp-style interactive development.

## Non-Goals

- Do not interpret Odin.
- Do not invent dynamic state or a hidden runtime.
- Do not require a custom Odin syntax.
- Do not hide compiler errors. Generated Odin should be inspectable.

