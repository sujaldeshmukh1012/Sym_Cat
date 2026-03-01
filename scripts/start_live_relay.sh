#!/usr/bin/env bash
set -euo pipefail

cd "/Users/sujalbhakare/Projects/Sym_Cat"

export GEMINI_API_KEY="AIzaSyCRyeI0e2tnYLAW0_GogF0OChH-ud4AfPQ"
export LIVE_WS_PORT="8001"

python api/test_live.py --mode ws-relay &
relay_pid=$!

cleanup() {
  if kill -0 "$relay_pid" 2>/dev/null; then
    kill "$relay_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

sleep 1
ngrok http 8001
