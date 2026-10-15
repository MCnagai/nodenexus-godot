#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$root/build/web"
touch "$root/build/.gdignore"
"$root/tools/godot.sh" --headless --import
"$root/tools/godot.sh" --headless --script res://tests/test_smoke.gd
"$root/tools/godot.sh" --headless --export-release Web "$root/build/web/index.html"
for artifact in index.html index.js index.wasm index.pck; do
  test -s "$root/build/web/$artifact"
done
printf 'WEB_CHECK_PASSED\n'
