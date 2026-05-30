# Hackathon 2026 Transport Intelligence Backend

Python backend for the Ratisbonalyzer/Kurt prototype.

It provides two local entrypoints over the same DuckDB analytics database:

- Backend API: FastAPI/uvicorn HTTP server used by the Flutter app chat.
- MCP server: stdio FastMCP server used by MCP clients such as Hermes.

## Database choice

Use DuckDB first.

Database file:

```text
data/processed/transport.duckdb
```

Raw CSV input folder:

```text
data/raw
```

Raw CSVs and generated database files are intentionally ignored by git.

## Setup

Run these commands from the repository root:

```bash
cd mcp-server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

Note: MCP requires a newer Python than macOS system Python 3.9. Use Python 3.12+ if your system Python cannot install the `mcp` package.

## Ingest data

Put CSV files into:

```text
data/raw
```

Inspect first:

```bash
python scripts/inspect_csvs.py data/raw
```

Ingest into DuckDB and build the analytics views:

```bash
python scripts/ingest_csvs.py data/raw data/processed/transport.duckdb
python scripts/create_views.py data/processed/transport.duckdb
```

One-line rebuild after replacing files in `data/raw`:

```bash
python scripts/inspect_csvs.py data/raw \
  && python scripts/ingest_csvs.py data/raw data/processed/transport.duckdb \
  && python scripts/create_views.py data/processed/transport.duckdb
```

This rewrites `data/processed/transport.duckdb` from the CSV files currently in `data/raw`. The newer raw export format with `departure_delay` in minutes is supported; positive values are interpreted as late departures and converted to seconds for the analytics views.

## Start the backend API server

Use this for the Flutter app and for HTTP chat testing.

From the repository root:

```bash
./scripts/run-backend.sh
```

Optional overrides:

```bash
PORT=8124 OLLAMA_MODEL=gemma4:26b-mlx ./scripts/run-backend.sh
```

Equivalent manual commands from `mcp-server/`:

```bash
source .venv/bin/activate
export TRANSPORT_DB_PATH="$PWD/data/processed/transport.duckdb"
export LLM_PROVIDER=ollama
export OLLAMA_BASE_URL=http://127.0.0.1:11434
export OLLAMA_MODEL=gemma4:26b-mlx
export OLLAMA_TIMEOUT_SECONDS=180
python -m uvicorn api.server:app --host 127.0.0.1 --port 8123
```

Health check from another terminal:

```bash
curl http://127.0.0.1:8123/health
```

Test a deterministic chat query without the LLM:

```bash
curl -sS http://127.0.0.1:8123/chat/query \
  -H 'Content-Type: application/json' \
  -d '{"question":"Which stops have the highest delays?","use_llm":false}'
```

If startup fails with `address already in use`, another backend is already listening on port 8123:

```bash
lsof -nP -iTCP:8123 -sTCP:LISTEN
```

Stop that process or run uvicorn on a different port.

## Start the MCP server manually

Use this for a local stdio MCP session. The MCP server is not an HTTP server, so it does not expose a browser URL or `/health` endpoint.

From the repository root:

```bash
./scripts/run-mcp-server.sh
```

Equivalent manual commands from `mcp-server/`:

```bash
source .venv/bin/activate
export TRANSPORT_DB_PATH="$PWD/data/processed/transport.duckdb"
python -m mcp_server.server
```

Important: start it with `python -m mcp_server.server`, not `python mcp_server/server.py`. The root script handles this for you. The module form keeps the repository package root on Python's import path so imports like `core.analytics` work correctly.

For a quick import smoke test that exits immediately:

```bash
python -c "import mcp_server.server; print('MCP server imports OK')"
```

## Hermes MCP config example

Because Hermes MCP stdio config has `command`, `args`, and `env` but no project `cwd`, use a small shell wrapper that changes into `mcp-server/` before starting the module.

Replace `/path/to/repo` with the absolute path to this repository:

```yaml
mcp_servers:
  hackathon_2026_transport:
    command: "/bin/bash"
    args:
      - "-lc"
      - "cd /path/to/repo/mcp-server && exec .venv/bin/python -m mcp_server.server"
    env:
      TRANSPORT_DB_PATH: "/path/to/repo/mcp-server/data/processed/transport.duckdb"
    timeout: 120
    connect_timeout: 30
```

For this checkout, the paths are:

```yaml
mcp_servers:
  hackathon_2026_transport:
    command: "/bin/bash"
    args:
      - "-lc"
      - "cd /Users/2an/Documents/Github/hackaburg2026-kurt/mcp-server && exec .venv/bin/python -m mcp_server.server"
    env:
      TRANSPORT_DB_PATH: "/Users/2an/Documents/Github/hackaburg2026-kurt/mcp-server/data/processed/transport.duckdb"
    timeout: 120
    connect_timeout: 30
```

Restart Hermes after changing MCP config so it reconnects and discovers the tools.

## Current approach

Phase 1 creates raw DuckDB tables named after CSV files, e.g.:

```text
raw_some_file_name
```

This avoids guessing the final schema before inspecting the real CSV columns. Derived analytics views then normalize stop-level delay events and daily metrics for MCP tools.

## Useful checks

```bash
# From mcp-server/
.venv/bin/python -m pytest -q
.venv/bin/python -c "import api.server; import mcp_server.server; print('imports OK')"
```
