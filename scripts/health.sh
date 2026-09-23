#!/usr/bin/env bash
# Report whether each CLI is on PATH and logged in.
# --update runs that CLI's own update command.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
PYTHON=""
for candidate in python python3; do
  if command -v "$candidate" >/dev/null && "$candidate" -c 'import sys; assert sys.version_info.major == 3' 2>/dev/null; then
    PYTHON="$candidate"
    break
  fi
done
[[ -n "$PYTHON" ]] || { echo "health.sh: Python 3 is required" >&2; exit 2; }
exec "$PYTHON" "$ROOT/harness_registry.py" health "$@"
