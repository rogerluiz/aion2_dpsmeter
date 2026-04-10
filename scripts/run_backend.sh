#!/usr/bin/env bash
set -euo pipefail
# Usage: ./scripts/run_backend.sh [--mock] [extra args...]
# Tries to find a python executable (env PYTHON, .venv, or system python)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PY=""
if [ -n "${PYTHON:-}" ]; then
  PY="$PYTHON"
elif [ -x "$ROOT_DIR/.venv/bin/python" ]; then
  PY="$ROOT_DIR/.venv/bin/python"
elif [ -x "$ROOT_DIR/.venv/Scripts/python.exe" ]; then
  PY="$ROOT_DIR/.venv/Scripts/python.exe"
else
  if command -v python3 >/dev/null 2>&1; then
    PY="$(command -v python3)"
  elif command -v python >/dev/null 2>&1; then
    PY="$(command -v python)"
  fi
fi

if [ -z "$PY" ]; then
  echo "No python executable found. Set PYTHON or create .venv." >&2
  exit 1
fi

ARGS=()
while [ $# -gt 0 ]; do
  ARGS+=("$1")
  shift
done

echo "Using python: $PY"
echo "Running: $PY backend/main.py ${ARGS[*]}"
cd "$ROOT_DIR"
exec "$PY" backend/main.py "${ARGS[@]}"
