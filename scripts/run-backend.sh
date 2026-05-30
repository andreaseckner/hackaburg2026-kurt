#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/mcp-server"
PYTHON="$BACKEND_DIR/.venv/bin/python"
DEFAULT_DB_PATH="$BACKEND_DIR/data/processed/transport.duckdb"
if [[ -n "${TRANSPORT_DB_PATH:-}" && -f "$TRANSPORT_DB_PATH" ]]; then
  DB_PATH="$TRANSPORT_DB_PATH"
else
  DB_PATH="$DEFAULT_DB_PATH"
fi
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8123}"

if [[ ! -x "$PYTHON" ]]; then
  echo "Missing backend venv: $PYTHON" >&2
  echo "Run first:" >&2
  echo "  cd mcp-server" >&2
  echo "  python3 -m venv .venv" >&2
  echo "  source .venv/bin/activate" >&2
  echo "  pip install -r requirements.txt" >&2
  exit 1
fi

cd "$BACKEND_DIR"

export TRANSPORT_DB_PATH="$DB_PATH"
export LLM_PROVIDER="${LLM_PROVIDER:-ollama}"
export OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://127.0.0.1:11434}"
export OLLAMA_MODEL="${OLLAMA_MODEL:-gemma4:26b-mlx}"
export OLLAMA_TIMEOUT_SECONDS="${OLLAMA_TIMEOUT_SECONDS:-180}"

echo "Starting backend API on http://$HOST:$PORT"
echo "Database: $TRANSPORT_DB_PATH"
exec "$PYTHON" -m uvicorn api.server:app --host "$HOST" --port "$PORT"
