#!/usr/bin/env bash
set -euo pipefail

# The prepared workspace keeps its engine and templates outside default paths.
if [[ -f /workspace/.environment/activate.sh ]]; then
    source /workspace/.environment/activate.sh
fi
cd "$(dirname "${BASH_SOURCE[0]}")/.."
version="$(godot --version)"
if [[ "$version" != 4.7.2.stable* ]]; then
    printf 'Expected Godot 4.7.2.stable; found %s. Check environment activation.\n' "$version" >&2
    exit 1
fi
printf 'Using Godot %s\n' "$version"
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/test_smoke.gd
mkdir -p build/web
godot --headless --path . --export-release Web build/web/index.html
test -s build/web/index.html
test -s build/web/index.wasm
printf 'Import, smoke test, and Web export passed.\n'
