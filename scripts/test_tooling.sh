#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

odin check cmd/olive
odin test cmd/olive -define:ODIN_TEST_LOG_LEVEL=warning
odin test tests -define:ODIN_TEST_LOG_LEVEL=warning
emacs -Q --batch -f batch-byte-compile emacs/olive.el
rm -f emacs/olive.elc

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

olive_bin="$tmp/olive"
odin build cmd/olive "-out:$olive_bin"

pkg="$tmp/sample"
mkdir -p "$pkg"
cat > "$pkg/sample.odin" <<'ODIN'
package sample

add :: proc(a: int, b: int) -> int {
    return a + b
}
ODIN

codes=(
  "target.add(4, 6)"
  "target.add(1000, 500)"
  "target.add(8, 9)"
  "target.add(1, 1)"
  "target.add(-3, 5)"
)
expected=(10 1500 17 2 2)
pids=()

for i in "${!codes[@]}"; do
  "$olive_bin" eval "$pkg" "${codes[$i]}" >"$tmp/out-$i" 2>"$tmp/err-$i" &
  pids+=("$!")
done

for pid in "${pids[@]}"; do
  wait "$pid"
done

for i in "${!expected[@]}"; do
  actual="$(tr -d '\r\n' < "$tmp/out-$i")"
  if [[ "$actual" != "${expected[$i]}" ]]; then
    echo "parallel olive $i expected ${expected[$i]}, got '$actual'" >&2
    if [[ -s "$tmp/err-$i" ]]; then
      cat "$tmp/err-$i" >&2
    fi
    exit 1
  fi
done

echo "parallel olive repro returned: ${expected[*]}"
