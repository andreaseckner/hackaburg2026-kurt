# Ratisbonalyzer / Kurt

Ratisbonalyzer is a Hackaburg 2026 transport intelligence prototype for exploring public transport reliability in Regensburg.

The project combines:

- a Flutter map app (`ratisbonalyzer/`) for visual exploration of routes, stops, GTFS data, playback controls, and the Kurt chat assistant
- a Python MCP/API backend (`mcp-server/`) that ingests raw transport CSV data into DuckDB and answers reliability questions

## What can it do?

- Show RVV/GTFS stops and routes on an interactive map.
- Load recorded transport data from CSV assets for playback-oriented UI controls.
- Rebuild a local DuckDB analytics database from raw CSV files.
- Answer chat questions such as delay rankings, daily delay summaries, and weekday morning intervention candidates.
- Use deterministic analytics first and optionally route flexible questions through a local Ollama model.

## Repository layout

```text
.
├── ratisbonalyzer/   # Flutter app
├── mcp-server/       # Python analytics API + MCP tools + DuckDB ingest scripts
└── docs/             # Planning and project notes
```

## Prerequisites

- Flutter SDK with Dart matching the app constraints.
- Python 3.12+ for the MCP backend.
- A running Ollama server if you want LLM-based chat routing.
- Raw transport CSV files placed under `mcp-server/data/raw/` when rebuilding the database.

## Backend quick start

From the repository root:

```bash
cd mcp-server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Rebuild the local DuckDB database from raw CSV files:

```bash
python scripts/inspect_csvs.py data/raw \
  && python scripts/ingest_csvs.py data/raw data/processed/transport.duckdb \
  && python scripts/create_views.py data/processed/transport.duckdb
```

Start the backend API for the Flutter chat:

```bash
LLM_PROVIDER=ollama \
OLLAMA_BASE_URL=http://127.0.0.1:11434 \
OLLAMA_MODEL=gemma4:26b-mlx \
OLLAMA_TIMEOUT_SECONDS=180 \
TRANSPORT_DB_PATH="$PWD/data/processed/transport.duckdb" \
.venv/bin/python -m uvicorn api.server:app --host 127.0.0.1 --port 8123
```

Health check:

```bash
curl http://127.0.0.1:8123/health
```

For more backend details, see `mcp-server/README.md`.

## Flutter app quick start

In a second terminal, from the repository root:

```bash
cd ratisbonalyzer
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter run -d chrome
```

The `build_runner` step regenerates Flutter asset references after CSV/text/image assets change. If you use FVM locally, run the same commands as `fvm flutter ...` / `fvm dart ...`.

The chat button in the bottom-right corner calls the backend at:

```text
http://127.0.0.1:8123/chat/query
```

Start the backend first if you want Kurt chat answers to work.

For more Flutter app details, see `ratisbonalyzer/README.md`.

## Useful development checks

Backend:

```bash
cd mcp-server
.venv/bin/python -m pytest -q
```

Flutter:

```bash
cd ratisbonalyzer
flutter analyze
```

## Data notes

Generated files are intentionally not committed:

- `mcp-server/data/raw/` CSV inputs
- `mcp-server/data/processed/transport.duckdb`

The database can always be rebuilt from the raw files using the ingest commands above.
