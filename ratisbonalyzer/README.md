# Ratisbonalyzer

Ratisbonalyzer is the main Flutter frontend for the Hackaburg 2026 Kurt transport reliability prototype.

It visualizes public transport data for Regensburg and provides a chat assistant for asking transport reliability questions against the local MCP/API backend.

## Features

- Interactive Flutter map based on `flutter_map`.
- GTFS route, stop, trip, stop-time, and shape assets from `assets/gtfs/`.
- RVV record CSV loading from `assets/rec/` for playback controls.
- Bottom-right round Kurt chat button using `assets/img/kurt.jpg`.
- Anchored chat panel with fixed input at the bottom and answers/results above.
- Chat API integration with the local backend at `http://127.0.0.1:8123/chat/query`.
- English and German localization scaffolding.

## Prerequisites

- Flutter SDK
- Dart SDK compatible with `pubspec.yaml`
- Running backend from `../mcp-server` if you want chat answers

## Install dependencies

From this folder:

```bash
flutter pub get
```

## Generate Flutter asset references

The app reads GTFS and RVV record CSV/text files as Flutter assets. After adding, removing, or renaming files under `assets/gtfs/`, `assets/img/`, or `assets/rec/`, regenerate `lib/src/core/assets.gen.dart`:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

If you use FVM locally, prefix the Flutter/Dart commands with `fvm`, for example:

```bash
fvm flutter pub run build_runner build --delete-conflicting-outputs
```

Note: this step does not convert the CSV files. The Flutter app parses the asset CSV/text files at runtime; the command only updates generated Dart asset references.

## Run the app

For web development:

```bash
flutter run -d chrome
```

For macOS desktop, if enabled in your Flutter setup:

```bash
flutter run -d macos
```

## Start the chat backend

The Flutter app expects the chat backend on port `8123`.

From the repository root:

```bash
cd mcp-server
LLM_PROVIDER=ollama \
OLLAMA_BASE_URL=http://127.0.0.1:11434 \
OLLAMA_MODEL=gemma4:26b-mlx \
OLLAMA_TIMEOUT_SECONDS=180 \
TRANSPORT_DB_PATH="$PWD/data/processed/transport.duckdb" \
.venv/bin/python -m uvicorn api.server:app --host 127.0.0.1 --port 8123
```

If the backend is not running, the map still opens, but Kurt chat requests will fail.

## Asset folders

```text
assets/gtfs/   GTFS text files used by the map
assets/img/    UI images, including kurt.jpg
assets/rec/    optional RVV record CSV files for playback controls
```

`assets/rec/` contains a `.gitkeep` so the folder exists even before CSV data is added.

## Common commands

Analyze the app:

```bash
flutter analyze
```

Format Dart files:

```bash
dart format lib
```

Regenerate generated asset/localization files when needed:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

## Project structure

```text
lib/
├── main.dart
└── src/
    ├── app.dart
    ├── core/          # generated assets, localization, theme constants
    └── features/
        ├── chat/      # Kurt chat UI, BLoC, API client, response models
        └── home/      # map screen, GTFS/RVV data services, domain models
```

## Backend data rebuild

If chat answers look stale, rebuild the backend DuckDB from `mcp-server/data/raw/`:

```bash
cd ../mcp-server
python scripts/inspect_csvs.py data/raw \
  && python scripts/ingest_csvs.py data/raw data/processed/transport.duckdb \
  && python scripts/create_views.py data/processed/transport.duckdb
```

Then restart the backend server.
