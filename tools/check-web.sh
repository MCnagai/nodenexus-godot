#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$root/build/web"
touch "$root/build/.gdignore"
if [[ -d "$root/node_modules" ]]; then
  touch "$root/node_modules/.gdignore"
fi
run_godot() {
  local log
  log=$(mktemp)
  if ! timeout --kill-after=5s 180s "$root/tools/godot.sh" "$@" 2>&1 | tee "$log"; then
    rm -f "$log"
    return 1
  fi
  # Some engine/import errors are logged despite an exit status of zero.
  if grep -Eq '^(ERROR:|SCRIPT ERROR:|Parse Error:)' "$log"; then
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
}
run_godot --headless --import
run_godot --headless --script res://tests/test_smoke.gd
run_godot --headless --script res://tests/test_combat.gd
run_godot --headless --export-release Web "$root/build/web/index.html"
for artifact in index.html index.js index.wasm index.pck; do
  test -s "$root/build/web/$artifact"
done
python3 "$root/tools/prepare-pages.py" "$root/build/web"
printf 'WEB_CHECK_PASSED\n'
