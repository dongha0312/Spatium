#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"

cd "$ROOT_DIR"
exec "$ROOT_DIR/.venv/bin/python" -m uvicorn app.main:app --host "$HOST" --port "$PORT"
