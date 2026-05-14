from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, replace
from pathlib import Path


@dataclass(frozen=True)
class EvalConfig:
    package: Path
    code: str
    print_result: bool = True
    extra_imports: tuple[str, ...] = ()
    import_path: str | None = None


def odin_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render_runner(config: EvalConfig) -> str:
    package = config.package.resolve()
    import_path = config.import_path or str(package)
    imports = ['import "core:fmt"', f"import target {odin_string(import_path)}"]
    imports.extend(config.extra_imports)

    body: list[str] = []
    if config.print_result:
        body.append(f"    result := {config.code}")
        body.append("    fmt.println(result)")
    else:
        for line in config.code.splitlines():
            body.append(f"    {line}" if line.strip() else "")

    return "\n".join(
        [
            "package main",
            "",
            *imports,
            "",
            "main :: proc() {",
            *body,
            "}",
            "",
        ]
    )


def write_runner(config: EvalConfig, directory: Path) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    relative_import = os.path.relpath(config.package.resolve(), directory.resolve())
    config = replace(config, import_path=relative_import)
    path = directory / "main.odin"
    path.write_text(render_runner(config), encoding="utf-8")
    return path


def run_odin(action: str, runner_dir: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["odin", action, str(runner_dir)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def command_eval(args: argparse.Namespace, action: str) -> int:
    package = Path(args.package)
    if not package.exists():
        print(f"package path does not exist: {package}", file=sys.stderr)
        return 2

    config = EvalConfig(
        package=package,
        code=args.code,
        print_result=not args.no_print,
        extra_imports=tuple(args.imports or ()),
    )

    keep_dir = Path(args.keep_dir).expanduser().resolve() if args.keep_dir else None
    with tempfile.TemporaryDirectory(prefix="odineval-") as tmp:
        runner_dir = keep_dir or Path(tmp)
        runner = write_runner(config, runner_dir)

        if args.show:
            print(runner.read_text(encoding="utf-8"), end="")

        result = run_odin(action, runner_dir)
        if result.stdout:
            print(result.stdout, end="")
        if result.stderr:
            print(result.stderr, end="", file=sys.stderr)
        return result.returncode


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="odineval")
    subparsers = parser.add_subparsers(dest="command", required=True)

    for name in ("run", "check"):
        p = subparsers.add_parser(name)
        p.add_argument("package", help="Path to the Odin package to import as `target`.")
        p.add_argument("code", help="Odin expression or statement snippet to run.")
        p.add_argument("--no-print", action="store_true", help="Treat code as statements and do not print a result.")
        p.add_argument("--show", action="store_true", help="Print generated Odin before invoking Odin.")
        p.add_argument("--keep-dir", help="Write runner into this directory instead of a temporary directory.")
        p.add_argument(
            "--import",
            dest="imports",
            action="append",
            help='Extra raw Odin import line, e.g. \'import "core:strings"\'.',
        )

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if shutil.which("odin") is None:
        print("odin not found on PATH", file=sys.stderr)
        return 127

    if args.command == "run":
        return command_eval(args, "run")
    if args.command == "check":
        return command_eval(args, "check")

    parser.error(f"unknown command: {args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
