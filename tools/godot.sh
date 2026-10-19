#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# The managed environment already provides the matching engine and templates.
if [[ -f /workspace/.environment/activate.sh ]]; then
  source /workspace/.environment/activate.sh
fi
engine=${GODOT_BIN:-godot}
version=$("$engine" --version)
if [[ "$version" != 4.7.2.stable.* ]]; then
  printf 'Godot 4.7.2 stable is required; found %s. Set GODOT_BIN to the matching executable.\n' "$version" >&2
  exit 1
fi
exec "$engine" --path "$root" "$@"
