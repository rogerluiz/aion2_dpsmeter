#!/usr/bin/env bash
set -euo pipefail
# scripts/test_capture.sh
# Start backend (real or mock), collect websocket logs, save outputs and stop backend.

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

# Defaults
MODE="--mock"
DURATION=30
OUT_DIR="$ROOT_DIR/logs"

while [ $# -gt 0 ]; do
  case "$1" in
    --real) MODE=""; shift ;;
    --mock) MODE="--mock"; shift ;;
    --duration) DURATION="$2"; shift 2 ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    --help|-h) echo "Usage: $0 [--real|--mock] [--duration seconds] [--out dir]"; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 2 ;;
  esac
done

mkdir -p "$OUT_DIR"
TS="$(date +%Y%m%d-%H%M%S)"
BACKEND_LOG="$OUT_DIR/backend_$TS.log"
WS_LOG="$OUT_DIR/ws_$TS.log"

echo "Using python: $PY"
echo "Backend mode: ${MODE:-real}"
echo "Duration: $DURATION seconds"
echo "Logs -> $OUT_DIR"

cd "$ROOT_DIR"

# Start backend in background
echo "Starting backend... (logs: $BACKEND_LOG)"
if [ -n "${MODE}" ]; then
  "$PY" backend/main.py $MODE >"$BACKEND_LOG" 2>&1 &
else
  "$PY" backend/main.py >"$BACKEND_LOG" 2>&1 &
fi
BACKEND_PID=$!
echo "Backend PID: $BACKEND_PID"

# Give backend time to start
sleep 2

# Run WS collector (if available)
if [ -f backend/collect_ws_logs.py ]; then
  echo "Collecting websocket logs to $WS_LOG for $DURATION seconds"
  # The collector currently prints for 30s; we run it and timeout if needed
  "$PY" backend/collect_ws_logs.py >"$WS_LOG" 2>&1 &
  WS_PID=$!
  # wait up to DURATION+5 seconds for it to finish
  SECONDS_LEFT=$((DURATION + 5))
  while kill -0 "$WS_PID" >/dev/null 2>&1; do
    if [ $SECONDS_LEFT -le 0 ]; then
      echo "WS collector still running after timeout; killing..."
      kill "$WS_PID" || true
      break
    fi
    sleep 1
    SECONDS_LEFT=$((SECONDS_LEFT - 1))
  done
else
  echo "backend/collect_ws_logs.py not found — skipping websocket capture"
fi

echo "Stopping backend (PID $BACKEND_PID)"
kill "$BACKEND_PID" || true
wait "$BACKEND_PID" 2>/dev/null || true

echo "Logs saved:"
echo " - Backend: $BACKEND_LOG"
echo " - WS:      $WS_LOG"

exit 0
