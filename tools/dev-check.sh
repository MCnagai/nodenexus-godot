#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
scope=${1:-code}
session=${NN_SESSION:-$(date -u +%Y%m%dT%H%M%S)-$$}
audit=(python3 tools/process.py "$session")
"${audit[@]}" start
trap '"${audit[@]}" summary' EXIT
case "$scope" in
  code)
    "${audit[@]}" run godot-web ./tools/check-web.sh
    "${audit[@]}" skip browser-full 'CI runs full regression after build, in parallel with protected preview deployment.'
    ;;
  smoke|combat)
    "${audit[@]}" run "godot-$scope" ./tools/godot.sh --headless --script "res://tests/test_$scope.gd"
    "${audit[@]}" skip browser-full 'Targeted local check; final export and regression run once in CI.'
    ;;
  preview)
    "${audit[@]}" run browser-preview npm run test:preview
    "${audit[@]}" skip browser-full 'Quick mobile startup only; full regression runs separately in CI.'
    ;;
  blocks)
    WEB_TEST_PROFILE=${WEB_TEST_PROFILE:-mobile} WEB_TEST_SCENARIO=blocks "${audit[@]}" run browser-blocks npm run test:web
    "${audit[@]}" skip browser-full 'Packaged block interactions only; camera, reload and loader failure scenarios run in full CI regression.'
    ;;
  full)
    "${audit[@]}" run godot-web ./tools/check-web.sh
    "${audit[@]}" run browser-full npm run test:web
    ;;
  docs)
    "${audit[@]}" run whitespace git diff --check
    "${audit[@]}" skip game-checks 'Documentation-only change; game/build/runtime files unchanged.'
    ;;
  *) echo 'Use code, smoke, combat, preview, blocks, full, or docs' >&2; exit 2 ;;
esac
