# Hackathon 2026 Transport Intelligence

Minimal first version for ingesting CSV bus data into DuckDB and exposing transport reliability analytics via MCP.

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

Ingest into DuckDB:

```bash
python scripts/ingest_csvs.py data/raw data/processed/transport.duckdb
python scripts/create_views.py data/processed/transport.duckdb
```

## Current approach

Phase 1 creates raw DuckDB tables named after CSV files, e.g.:

```text
raw_some_file_name
```

This avoids guessing the final schema before inspecting the real CSV columns. Derived analytics views then normalize stop-level delay events and daily metrics for MCP tools.
