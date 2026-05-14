# odineval Agent Notes

This repo explores REPL-like tooling for Odin by generating temporary Odin code
and invoking the real Odin compiler.

## Direction

- Preserve Odin semantics exactly.
- Prefer generated Odin plus `odin run` / `odin check` over interpretation.
- Keep generated code boring and easy to inspect.
- Start with external package eval using the import alias `target`.
- Add internal same-package eval later for package-local functions.

## Non-Goals

- Do not create a new language or syntax layer.
- Do not build hidden persistent runtime state.
- Do not swallow Odin diagnostics.
- Do not edit user source files for eval.

## Implementation

- CLI entry point: `python3 -m src.odineval`.
- Tests: `python3 -m unittest discover -s tests`.
- Use real `odin check` / `odin run` in integration tests when Odin is
  available.

