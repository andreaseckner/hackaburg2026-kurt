# Hackathon 2026 Transport Intelligence

Minimal first version for ingesting CSV bus data into DuckDB and exposing it to analytics/MCP code.

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

## Setup

```bash
cd /Users/2an/Documents/Github/hackathon-2026
/opt/homebrew/bin/python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Note: MCP requires a newer Python than macOS system Python 3.9. Use Python 3.12 here.

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
```

## Current approach

Phase 1 creates raw DuckDB tables named after CSV files, e.g.:

```text
raw_some_file_name
```

This avoids guessing the final schema before we inspect the real CSV columns.

After inspection, create derived analytics tables/views such as:

```text
stop_events
daily_delay_metrics
line_delay_metrics
stop_delay_metrics
```
