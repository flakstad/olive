from __future__ import annotations

import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

from src.odineval import EvalConfig, render_runner


class RenderTests(unittest.TestCase):
    def test_render_printing_runner(self) -> None:
        runner = render_runner(EvalConfig(package=Path("/tmp/pkg"), code="target.answer()", import_path="../pkg"))

        self.assertIn('import "core:fmt"', runner)
        self.assertIn('import target "../pkg"', runner)
        self.assertIn("result := target.answer()", runner)
        self.assertIn("fmt.println(result)", runner)

    def test_render_no_print_runner(self) -> None:
        runner = render_runner(EvalConfig(package=Path("/tmp/pkg"), code="target.run()", print_result=False))

        self.assertIn("    target.run()", runner)
        self.assertNotIn("fmt.println(result)", runner)


@unittest.skipIf(shutil.which("odin") is None, "odin not available")
class OdinIntegrationTests(unittest.TestCase):
    def test_run_external_package_proc(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            pkg = root / "sample"
            pkg.mkdir()
            (pkg / "sample.odin").write_text(
                textwrap.dedent(
                    """\
                    package sample

                    answer :: proc() -> int {
                        return 42
                    }
                    """
                ),
                encoding="utf-8",
            )

            result = subprocess.run(
                ["python3", "-m", "src.odineval", "run", str(pkg), "target.answer()"],
                cwd=Path(__file__).resolve().parents[1],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "42")


if __name__ == "__main__":
    unittest.main()
