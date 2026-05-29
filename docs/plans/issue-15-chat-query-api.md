# Issue 15 Chat Query API Implementation Plan

> **For Hermes:** Use subagent-driven-development or Claude Code to implement this plan task-by-task. Keep changes small, test after each task, and do not push directly to `main`.

**GitHub issue:** https://github.com/andreaseckner/hackaburg2026-kurt/issues/15

**Branch:** `feat/issue-15-chat-query-api`

**Goal:** Build a constrained chat-style query path for map-based transport reliability questions.

**Architecture:** The user asks a natural-language question, but the backend routes it through a deterministic intent router to known analytics functions. The system returns an answer card, metric source, supporting data, suggestions, and optional map filter/layer state. For now, do **not** use an LLM and do **not** allow unrestricted LLM-generated SQL.

**Tech Stack:** Python, DuckDB, FastAPI, pytest, MCP server, Flutter/Dart, flutter_bloc, http package.

---

## 0. Product and Safety Decisions

### Non-negotiable constraints

1. No LLM in the first implementation.
2. No unrestricted generated SQL.
3. User questions must route only to a whitelist of supported intents.
4. Unsupported questions must return a helpful fallback and suggested supported questions.
5. Every successful answer must include `metric_source` so the demo can explain how the answer was computed.
6. Backend responses should include optional map state so the frontend can highlight the relevant corridor, stop, or segment.

### Supported first-version questions

The first version should support exactly these three intents:

1. `weekday_morning_intervention`
   - Example: "Where should we intervene first on weekday mornings?"
   - Analytics: corridor pain points filtered to weekdays and morning hours.
   - Map layer: corridor.

2. `city_center_delay_growth_segment`
   - Example: "Which segment creates the most delay toward the city center?"
   - Analytics: stop-to-stop delay growth hotspots, filtered toward city center when possible.
   - Map layer: segment.

3. `passenger_delay_exposure_after_16`
   - Example: "Which stops expose passengers to the most delay after 16:00?"
   - Analytics: stop-level delay exposure filtered to hour >= 16.
   - Map layer: stops.

Everything else should return `unsupported`.

### Important analytics wording

Use these distinctions in answer text:

- Stop-level delay counts delay at every stop. It is good for passenger exposure and system burden, but can overcount if interpreted as "one bus delay".
- Trip-level delay counts each trip/departure once using the maximum delay reached. It is better for human questions like "how delayed was one bus?".
- Delay-growth segments show where delay is added between two stops. This is best for intervention planning.

---

## 1. Recommended Build Sequence

Build in this order to keep the work reviewable and demo-safe:

1. Backend filtered analytics.
2. Backend deterministic chat router.
3. MCP chat tool.
4. FastAPI HTTP API.
5. Flutter chat client and answer panel.
6. Flutter map overlay integration.
7. Documentation and demo script.

Recommended PR split:

- PR 1: Backend analytics + deterministic chat router + MCP tool + tests.
- PR 2: FastAPI API endpoint + tests + docs.
- PR 3: Flutter chat UI + map overlay.

If time is short, combine PR 1 and PR 2, but keep Flutter separate.

---

## 2. Backend Response Contract

Create a stable JSON shape that both MCP and HTTP can return.

### Chat request

```json
{
  "question": "Which stops expose passengers to the most delay after 16:00?"
}
```

### Chat response

```json
{
  "intent": "passenger_delay_exposure_after_16",
  "confidence": 1.0,
  "title": "Passenger delay exposure after 16:00",
  "answer": "After 16:00, passengers see the most accumulated stop-level delay at ...",
  "bullets": [
    "Stop A: 123.4 stop-delay minutes, 42 events delayed 3+ minutes",
    "Stop B: 98.1 stop-delay minutes, 31 events delayed 3+ minutes"
  ],
  "metric_source": "stop_delay_exposure_filtered hour_from=16 hour_to=23",
  "data": [],
  "map_state": {
    "layer_type": "stops",
    "stops": ["Stop A", "Stop B"],
    "segments": [],
    "route_start": null,
    "route_end": null,
    "hour_from": 16,
    "hour_to": 23,
    "severity_metric": "total_stop_delay_minutes"
  },
  "suggested_questions": [
    "Where should we intervene first on weekday mornings?",
    "Which segment creates the most delay toward the city center?",
    "Which stops expose passengers to the most delay after 16:00?"
  ],
  "unsupported_reason": null
}
```

### Unsupported response

```json
{
  "intent": "unsupported",
  "confidence": 0.0,
  "title": "Question not supported yet",
  "answer": "I can only answer verified historical reliability questions for the current dataset. Try one of the suggested questions below.",
  "bullets": [],
  "metric_source": "none",
  "data": [],
  "map_state": null,
  "suggested_questions": [
    "Where should we intervene first on weekday mornings?",
    "Which segment creates the most delay toward the city center?",
    "Which stops expose passengers to the most delay after 16:00?"
  ],
  "unsupported_reason": "No supported intent matched the question."
}
```

---

## 3. Backend Task Plan

### Task 1: Add filtered stop delay exposure analytics

**Objective:** Add a deterministic function for questions like "Which stops expose passengers to the most delay after 16:00?"

**Files:**
- Modify: `mcp-server/core/analytics.py`
- Modify: `mcp-server/tests/test_analytics.py`

**Function to add:**

```python
def get_stop_delay_exposure_filtered(
    db_path: str | None = None,
    limit: int = 10,
    hour_from: int | None = None,
    hour_to: int | None = None,
    weekday_only: bool | None = None,
) -> list[dict[str, Any]]:
    ...
```

**Implementation requirements:**

- Use parameterized DuckDB queries.
- Clamp `limit` with existing `_limit()`.
- Validate hours: 0 <= hour <= 23.
- If `hour_from` is set, filter `planned_departure_hour >= hour_from`.
- If `hour_to` is set, filter `planned_departure_hour <= hour_to`.
- If `weekday_only is True`, filter `weekday_number BETWEEN 1 AND 5`.
- Group by stop fields.
- Return:
  - `stop_name`
  - `stop_code`
  - `stop_point`
  - `event_count`
  - `total_stop_delay_minutes`
  - `avg_positive_delay_seconds`
  - `delayed_3min_events`
  - `pct_delayed_3min`

**Test:**

Add test using existing fixture:

```python
def test_get_stop_delay_exposure_filtered_after_16_returns_stop_hotspots(db_path):
    rows = get_stop_delay_exposure_filtered(db_path, hour_from=16, hour_to=23, limit=5)
    assert isinstance(rows, list)
```

The existing fixture may need one or two rows after 16:00 so the result is non-empty.

**Verify:**

```bash
cd mcp-server
source .venv/bin/activate
pytest tests/test_analytics.py -q
```

---

### Task 2: Add filtered corridor pain point analytics

**Objective:** Support weekday morning intervention questions.

**Files:**
- Modify: `mcp-server/core/analytics.py`
- Modify: `mcp-server/tests/test_analytics.py`

**Function to add:**

```python
def get_corridor_pain_points_filtered(
    db_path: str | None = None,
    limit: int = 10,
    weekday_only: bool | None = None,
    hour_from: int | None = None,
    hour_to: int | None = None,
) -> list[dict[str, Any]]:
    ...
```

**Implementation requirements:**

- Reuse logic from `get_corridor_pain_points` where possible.
- Use explicit filters instead of generic SQL string from the user.
- Return:
  - `direction_id`
  - `route_start`
  - `route_end`
  - `event_count`
  - `service_days`
  - `total_stop_delay_minutes`
  - `avg_positive_delay_seconds`
  - `delayed_3min_events`
  - `pct_delayed_3min`
  - optional `worst_hour`
  - optional `worst_day`

**Question mapping:**

For "Where should we intervene first on weekday mornings?" call:

```python
get_corridor_pain_points_filtered(
    db_path=db_path,
    weekday_only=True,
    hour_from=6,
    hour_to=10,
    limit=3,
)
```

**Verify:**

```bash
cd mcp-server
source .venv/bin/activate
pytest tests/test_analytics.py -q
```

---

### Task 3: Add filtered segment delay-growth analytics

**Objective:** Support "Which segment creates the most delay toward the city center?"

**Files:**
- Modify: `mcp-server/core/analytics.py`
- Modify: `mcp-server/tests/test_analytics.py`

**Function to add:**

```python
def get_segment_delay_growth_hotspots_filtered(
    db_path: str | None = None,
    limit: int = 10,
    min_growth_1min_events: int = 10,
    hour_from: int | None = None,
    hour_to: int | None = None,
    toward_city_center: bool = False,
) -> list[dict[str, Any]]:
    ...
```

**Implementation requirements:**

- Use the trip segmentation logic from `get_segment_delay_growth_hotspots`.
- Add hour filters to trip events.
- If `toward_city_center=True`, filter with a small explicit set of city-center stop keywords.
- Start with this constant in `analytics.py`:

```python
_CITY_CENTER_STOP_KEYWORDS = (
    "hauptbahnhof",
    "dachauplatz",
    "arnulfsplatz",
    "albertstraße",
    "albertstrasse",
)
```

- City-center filter can match normalized lower-case text against:
  - `route_end`
  - `current_stop`
  - `previous_stop`

**Return:**

- `route_start`
- `route_end`
- `previous_stop`
- `current_stop`
- `segment_events`
- `avg_growth_seconds`
- `total_positive_growth_minutes`
- `growth_1min_events`

**Verify:**

```bash
cd mcp-server
source .venv/bin/activate
pytest tests/test_analytics.py -q
```

---

### Task 4: Add deterministic chat router

**Objective:** Route supported natural-language questions to deterministic analytics functions.

**Files:**
- Create: `mcp-server/core/chat.py`
- Create: `mcp-server/tests/test_chat.py`

**Core function:**

```python
def answer_transport_question(question: str, db_path: str | None = None) -> dict[str, Any]:
    ...
```

**Router behavior:**

Normalize question:

```python
def _normalize_question(question: str) -> str:
    return " ".join(question.lower().strip().split())
```

Intent rules:

```python
if "intervene" in q and "weekday" in q and "morning" in q:
    return _answer_weekday_morning_intervention(...)

if "segment" in q and ("city center" in q or "city centre" in q):
    return _answer_city_center_delay_growth_segment(...)

if "stops" in q and "passengers" in q and ("after 16" in q or "after 4" in q):
    return _answer_passenger_delay_exposure_after_16(...)

return _unsupported_response(...)
```

**Supported question suggestions:**

```python
SUGGESTED_QUESTIONS = [
    "Where should we intervene first on weekday mornings?",
    "Which segment creates the most delay toward the city center?",
    "Which stops expose passengers to the most delay after 16:00?",
]
```

**Safety test:**

```python
def test_sql_like_question_is_not_executed(db_path):
    response = answer_transport_question("SELECT * FROM departure_delay_events;", db_path)
    assert response["intent"] == "unsupported"
    assert response["metric_source"] == "none"
```

**Required tests:**

1. Weekday morning intervention routes correctly.
2. City-center segment question routes correctly.
3. Passenger delay exposure after 16 routes correctly.
4. Unsupported question returns suggestions.
5. SQL-looking input does not execute.

**Verify:**

```bash
cd mcp-server
source .venv/bin/activate
pytest tests/test_chat.py -q
pytest -q
```

---

### Task 5: Add MCP chat tool

**Objective:** Expose the deterministic chat path as one MCP tool.

**Files:**
- Modify: `mcp-server/mcp_server/server.py`
- Modify: `mcp-server/docs/mcp.md`

**Tool to add:**

```python
@mcp.tool()
def answer_reliability_question(question: str) -> str:
    """Answer a supported natural-language reliability question using deterministic analytics only."""
    response = answer_transport_question(question)
    return json.dumps(response, default=str, ensure_ascii=False, indent=2)
```

**Import:**

```python
from core.chat import answer_transport_question
```

**Docs:**

Add `answer_reliability_question` to available analytics tools and document that it does not use an LLM or generated SQL.

**Verify:**

```bash
cd mcp-server
source .venv/bin/activate
python -m py_compile core/chat.py core/analytics.py mcp_server/server.py
pytest -q
```

---

## 4. HTTP API Task Plan

### Task 6: Add FastAPI dependencies

**Objective:** Prepare backend HTTP API for Flutter.

**Files:**
- Modify: `mcp-server/requirements.txt`

**Add:**

```text
fastapi>=0.115.0
uvicorn>=0.30.0
```

**Verify:**

```bash
cd mcp-server
source .venv/bin/activate
pip install -r requirements.txt
python - <<'PY'
import fastapi, uvicorn
print("fastapi ok")
PY
```

---

### Task 7: Add FastAPI app

**Objective:** Provide an HTTP endpoint for the frontend.

**Files:**
- Create: `mcp-server/api/__init__.py`
- Create: `mcp-server/api/server.py`
- Create: `mcp-server/tests/test_api.py`

**API shape:**

`GET /health`

Response:

```json
{
  "status": "ok"
}
```

`POST /chat/query`

Request:

```json
{
  "question": "Where should we intervene first on weekday mornings?"
}
```

Response: same ChatResponse shape returned by `answer_transport_question`.

**Implementation sketch:**

```python
from __future__ import annotations

from typing import Any

from fastapi import FastAPI
from pydantic import BaseModel, Field

from core.chat import answer_transport_question
from core.db import resolve_db_path

app = FastAPI(title="Hackaburg Transport Reliability API")

class ChatQueryRequest(BaseModel):
    question: str = Field(..., min_length=1, max_length=500)

@app.get("/health")
def health() -> dict[str, Any]:
    db_path = resolve_db_path()
    return {
        "status": "ok",
        "database_path": str(db_path),
        "database_exists": db_path.exists(),
    }

@app.post("/chat/query")
def chat_query(request: ChatQueryRequest) -> dict[str, Any]:
    return answer_transport_question(request.question)
```

**Tests:**

Use FastAPI TestClient:

```python
from fastapi.testclient import TestClient
from api.server import app


def test_health_returns_ok():
    client = TestClient(app)
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_chat_query_returns_supported_answer():
    client = TestClient(app)
    response = client.post("/chat/query", json={"question": "Where should we intervene first on weekday mornings?"})
    assert response.status_code == 200
    assert "intent" in response.json()
```

If the TestClient needs a fixture DB path, set `TRANSPORT_DB_PATH` in the test environment or allow the chat tests to focus on unsupported response. Prefer proper fixture DB if time permits.

**Run API locally:**

```bash
cd mcp-server
source .venv/bin/activate
uvicorn api.server:app --reload --host 127.0.0.1 --port 8123
```

**Manual check:**

```bash
curl -s http://127.0.0.1:8123/health | python -m json.tool
curl -s -X POST http://127.0.0.1:8123/chat/query \
  -H 'Content-Type: application/json' \
  -d '{"question":"Which stops expose passengers to the most delay after 16:00?"}' \
  | python -m json.tool
```

---

## 5. Flutter Frontend Task Plan

### Task 8: Add frontend HTTP dependency

**Objective:** Allow Flutter app to call backend API.

**Files:**
- Modify: `rvv_analyzer/pubspec.yaml`

**Add dependency:**

```yaml
http: ^1.2.2
```

**Verify:**

```bash
cd rvv_analyzer
flutter pub get
```

If Flutter is managed by FVM in the environment:

```bash
fvm flutter pub get
```

---

### Task 9: Add ChatResponse model

**Objective:** Parse backend chat responses in Flutter.

**Files:**
- Create: `rvv_analyzer/lib/features/chat/models/chat_response.dart`

**Minimum model fields:**

```dart
class ChatResponse {
  final String intent;
  final double confidence;
  final String title;
  final String answer;
  final List<String> bullets;
  final String metricSource;
  final Map<String, dynamic>? mapState;
  final List<String> suggestedQuestions;
  final String? unsupportedReason;

  const ChatResponse({
    required this.intent,
    required this.confidence,
    required this.title,
    required this.answer,
    required this.bullets,
    required this.metricSource,
    required this.mapState,
    required this.suggestedQuestions,
    required this.unsupportedReason,
  });

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    return ChatResponse(
      intent: json['intent'] as String? ?? 'unsupported',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      title: json['title'] as String? ?? '',
      answer: json['answer'] as String? ?? '',
      bullets: (json['bullets'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      metricSource: json['metric_source'] as String? ?? 'none',
      mapState: json['map_state'] as Map<String, dynamic>?,
      suggestedQuestions: (json['suggested_questions'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      unsupportedReason: json['unsupported_reason'] as String?,
    );
  }
}
```

---

### Task 10: Add Chat API client

**Objective:** Encapsulate HTTP call to backend.

**Files:**
- Create: `rvv_analyzer/lib/features/chat/data/chat_api_client.dart`

**Implementation sketch:**

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rvv_analyzer/features/chat/models/chat_response.dart';

class ChatApiClient {
  final http.Client _client;
  final Uri _chatUri;

  ChatApiClient({
    http.Client? client,
    String baseUrl = 'http://127.0.0.1:8123',
  })  : _client = client ?? http.Client(),
        _chatUri = Uri.parse('$baseUrl/chat/query');

  Future<ChatResponse> ask(String question) async {
    final response = await _client.post(
      _chatUri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'question': question}),
    );

    if (response.statusCode != 200) {
      throw Exception('Chat API failed: ${response.statusCode}');
    }

    return ChatResponse.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
```

**Note for Android emulator:** use `http://10.0.2.2:8123` instead of `127.0.0.1`.

For hackathon demo, hardcode base URL initially. Later move to config.

---

### Task 11: Add chat BLoC or simple controller

**Objective:** Manage chat loading/error/result state.

**Files:**
- Create: `rvv_analyzer/lib/features/chat/bloc/chat_event.dart`
- Create: `rvv_analyzer/lib/features/chat/bloc/chat_state.dart`
- Create: `rvv_analyzer/lib/features/chat/bloc/chat_bloc.dart`

**Keep simple:**

States:
- initial
- loading
- loaded
- error

Events:
- ChatQuestionSubmitted
- ChatSuggestedQuestionSelected
- ChatCleared

Since the app already uses `flutter_bloc`, use BLoC for consistency.

---

### Task 12: Add chat panel UI

**Objective:** Let the user ask supported questions from the map screen.

**Files:**
- Create: `rvv_analyzer/lib/features/chat/widgets/chat_panel.dart`
- Modify: `rvv_analyzer/lib/features/map/map_screen.dart`

**UI behavior:**

- Add chat icon button to `AppBar`.
- Tapping opens a bottom sheet.
- Bottom sheet shows:
  - text input
  - ask button
  - suggested question chips
  - answer card
  - metric source line
  - fallback text for unsupported questions

**Suggested chips:**

- "Where should we intervene first on weekday mornings?"
- "Which segment creates the most delay toward the city center?"
- "Which stops expose passengers to the most delay after 16:00?"

**Do not build full chat history yet.**
One question -> one answer card is enough for the first demo.

---

## 6. Map Overlay Task Plan

### Task 13: Add map overlay model

**Objective:** Store backend map hints in MapState.

**Files:**
- Create: `rvv_analyzer/lib/features/map/models/reliability_map_overlay.dart`
- Modify: `rvv_analyzer/lib/features/map/bloc/map_state.dart`
- Modify: `rvv_analyzer/lib/features/map/bloc/map_event.dart`
- Modify: `rvv_analyzer/lib/features/map/bloc/map_bloc.dart`

**Model sketch:**

```dart
enum ReliabilityLayerType { none, corridor, stops, segment }

class ReliabilitySegment {
  final String previousStop;
  final String currentStop;
  final double? severity;

  const ReliabilitySegment({
    required this.previousStop,
    required this.currentStop,
    this.severity,
  });
}

class ReliabilityMapOverlay {
  final ReliabilityLayerType layerType;
  final String? routeStart;
  final String? routeEnd;
  final List<String> stops;
  final List<ReliabilitySegment> segments;
  final int? hourFrom;
  final int? hourTo;
  final String? severityMetric;

  const ReliabilityMapOverlay({
    required this.layerType,
    this.routeStart,
    this.routeEnd,
    this.stops = const [],
    this.segments = const [],
    this.hourFrom,
    this.hourTo,
    this.severityMetric,
  });
}
```

**Events:**

```dart
class MapReliabilityOverlayApplied extends MapEvent {
  final ReliabilityMapOverlay overlay;
  const MapReliabilityOverlayApplied(this.overlay);
}

class MapReliabilityOverlayCleared extends MapEvent {
  const MapReliabilityOverlayCleared();
}
```

---

### Task 14: Render highlighted stops and segments

**Objective:** Reflect chat answer on the map.

**Files:**
- Modify: `rvv_analyzer/lib/features/map/map_screen.dart`

**Minimum viable behavior:**

- If overlay layer type is `stops`, render matching stop markers in orange/red and slightly larger.
- If overlay layer type is `segment`, highlight the two matching stops and optionally draw a simple line between them if both coordinates are found.
- If overlay layer type is `corridor`, show a banner/card and, if route matching is available, filter/highlight the route.

**Stop matching helper:**

Normalize names:

```dart
String normalizeStopName(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9äöüß]'), '');
}
```

Then match backend stop names against `GtfsStop.name`.

**Known risk:**
Backend stop names/codes may not exactly match GTFS stop names. Start with normalized name matching, then improve later with explicit stop IDs.

---

## 7. Claude Code Implementation Strategy

Use Claude Code for implementation, but keep Hermes as the orchestrator and verifier.

### Recommended Claude Code sequence

Run Claude Code one phase at a time, not for the whole feature at once.

#### Claude Task A: Backend analytics filters

Prompt:

```text
Implement Tasks 1-3 from docs/plans/issue-15-chat-query-api.md.
Only modify mcp-server/core/analytics.py and mcp-server/tests/test_analytics.py.
Do not add an LLM. Do not generate SQL from user questions. Use parameterized DuckDB queries.
After implementing, run: cd mcp-server && source .venv/bin/activate && pytest tests/test_analytics.py -q
Report changed files and test results.
```

Suggested command:

```bash
claude -p "Implement Tasks 1-3 from docs/plans/issue-15-chat-query-api.md. Only modify mcp-server/core/analytics.py and mcp-server/tests/test_analytics.py. Do not add an LLM. Do not generate SQL from user questions. Use parameterized DuckDB queries. Run tests and report results." --allowedTools "Read,Edit,Write,Bash" --max-turns 15
```

#### Claude Task B: Chat router + MCP tool

Prompt:

```text
Implement Tasks 4-5 from docs/plans/issue-15-chat-query-api.md.
Create mcp-server/core/chat.py and mcp-server/tests/test_chat.py.
Modify mcp-server/mcp_server/server.py and mcp-server/docs/mcp.md.
Do not use an LLM. The router must be deterministic and whitelist-only.
Run: cd mcp-server && source .venv/bin/activate && pytest -q && python -m py_compile core/chat.py core/analytics.py mcp_server/server.py
Report changed files and test results.
```

#### Claude Task C: FastAPI API

Prompt:

```text
Implement Tasks 6-7 from docs/plans/issue-15-chat-query-api.md.
Add FastAPI dependencies, create mcp-server/api/server.py, and add API tests.
The endpoint POST /chat/query must call core.chat.answer_transport_question.
Run backend tests and a small curl/manual check if practical.
Report changed files and test results.
```

#### Claude Task D: Flutter chat UI

Prompt:

```text
Implement Tasks 8-12 from docs/plans/issue-15-chat-query-api.md.
Add the Flutter chat response model, API client, chat BLoC, chat panel, and a chat button on the map screen.
Do not implement map overlays yet.
Keep UI simple: suggested chips, one input, one answer card, metric source.
Run flutter analyze if available.
Report changed files and results.
```

#### Claude Task E: Map overlays

Prompt:

```text
Implement Tasks 13-14 from docs/plans/issue-15-chat-query-api.md.
Add ReliabilityMapOverlay model and map events/state. Highlight stops and segments from backend map_state.
Use normalized stop-name matching. Keep the implementation minimal and demo-safe.
Run flutter analyze if available.
Report changed files and results.
```

### Hermes verification after each Claude task

After each Claude Code run, Hermes should verify:

```bash
git diff --stat
git diff --check
cd mcp-server && source .venv/bin/activate && pytest -q
cd mcp-server && source .venv/bin/activate && python -m py_compile core/*.py mcp_server/server.py
```

For Flutter tasks:

```bash
cd rvv_analyzer
flutter analyze
```

or, if FVM is used:

```bash
cd rvv_analyzer
fvm flutter analyze
```

---

## 8. Final Verification Checklist

Backend:

- [ ] `pytest -q` passes in `mcp-server`.
- [ ] `python -m py_compile core/chat.py core/analytics.py mcp_server/server.py api/server.py` passes.
- [ ] `answer_transport_question("Where should we intervene first on weekday mornings?")` returns `weekday_morning_intervention`.
- [ ] `answer_transport_question("Which segment creates the most delay toward the city center?")` returns `city_center_delay_growth_segment`.
- [ ] `answer_transport_question("Which stops expose passengers to the most delay after 16:00?")` returns `passenger_delay_exposure_after_16`.
- [ ] Unsupported question returns `unsupported` and suggested questions.
- [ ] SQL-looking question returns `unsupported`.
- [ ] Every supported response includes `metric_source`.
- [ ] MCP server imports successfully.
- [ ] FastAPI `/health` works.
- [ ] FastAPI `POST /chat/query` works.

Frontend:

- [ ] `flutter pub get` passes.
- [ ] `flutter analyze` passes.
- [ ] Map screen shows chat button.
- [ ] Chat panel opens from map screen.
- [ ] Suggested question chips submit questions.
- [ ] Answer card shows title, answer, bullets, and metric source.
- [ ] Unsupported question shows fallback.
- [ ] Map overlay can highlight stops at minimum.

Security:

- [ ] No LLM dependency added.
- [ ] No code path accepts generated SQL from the chat question.
- [ ] Existing `run_readonly_sql` protections remain unchanged.
- [ ] Backend API validates max question length.
- [ ] No credentials or local absolute secrets added to committed files.

---

## 9. Demo Script

Start backend:

```bash
cd mcp-server
source .venv/bin/activate
uvicorn api.server:app --reload --host 127.0.0.1 --port 8123
```

Run app:

```bash
cd rvv_analyzer
flutter run
```

Demo flow:

1. Open map.
2. Tap chat button.
3. Tap suggested question: "Where should we intervene first on weekday mornings?"
4. Show answer card and metric source.
5. Explain: deterministic router, no LLM, no generated SQL.
6. Ask: "Which stops expose passengers to the most delay after 16:00?"
7. Show highlighted stops if overlay is implemented.
8. Ask unsupported question, e.g. "Will it rain tomorrow?"
9. Show safe fallback and suggestions.

---

## 10. Commit Strategy

Use small commits:

```bash
git add mcp-server/core/analytics.py mcp-server/tests/test_analytics.py
git commit -m "feat: add filtered reliability analytics for chat"

git add mcp-server/core/chat.py mcp-server/tests/test_chat.py mcp-server/mcp_server/server.py mcp-server/docs/mcp.md
git commit -m "feat: add deterministic reliability question router"

git add mcp-server/api mcp-server/requirements.txt mcp-server/tests/test_api.py
git commit -m "feat: add reliability chat HTTP API"

git add rvv_analyzer/pubspec.yaml rvv_analyzer/lib/features/chat rvv_analyzer/lib/features/map/map_screen.dart
git commit -m "feat: add reliability chat panel"

git add rvv_analyzer/lib/features/map
# include only overlay-related files after reviewing diff
git commit -m "feat: show reliability chat overlays on map"
```

PR body should include:

```markdown
## Summary
- Adds deterministic natural-language reliability question router for issue #15
- Adds backend API endpoint for frontend chat queries
- Adds optional map state in responses
- Avoids LLM-generated SQL and unsupported free-form queries

## Test Plan
- [ ] cd mcp-server && source .venv/bin/activate && pytest -q
- [ ] cd mcp-server && source .venv/bin/activate && python -m py_compile core/chat.py core/analytics.py mcp_server/server.py api/server.py
- [ ] cd rvv_analyzer && flutter analyze

Closes #15
```
