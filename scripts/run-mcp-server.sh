#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/mcp-server"
PYTHON="$BACKEND_DIR/.venv/bin/python"
DB_PATH="${TRANSPORT_DB_PATH:-$BACKEND_DIR/data/processed/transport.duckdb}"

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

echo "Starting stdio MCP server" >&2
echo "Database: $TRANSPORT_DB_PATH" >&2
exec "$PYTHON" -m mcp_server.server
