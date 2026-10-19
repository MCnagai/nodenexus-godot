#!/usr/bin/env bash
set -euo pipefail
# Keep one verification implementation; check-web uses the prepared runtime.
exec "$(dirname "${BASH_SOURCE[0]}")/check-web.sh" "$@"
