from __future__ import annotations

import duckdb
import pytest

from core.llm_chat import (
    answer_transport_question_with_llm,
    default_tool_classifier,
    ollama_tool_classifier,
)


@pytest.fixture()
def db_path(tmp_path):
    path = tmp_path / "transport.duckdb"
    con = duckdb.connect(str(path))
    con.execute(
        """
        CREATE TABLE departure_delay_events AS
        SELECT * FROM (VALUES
            (DATE '2024-12-12', 4, 'Thursday', 8, 1, 'Start A', 'A', 'A1',  60.0, 1, 'run-1', TIMESTAMP '2024-12-12 08:00:00', 'Start A', 'A', 'End B', 'B'),
            (DATE '2024-12-12', 4, 'Thursday', 8, 1, 'Middle',  'M', 'M1', 240.0, 1, 'run-1', TIMESTAMP '2024-12-12 08:10:00', 'Start A', 'A', 'End B', 'B'),
            (DATE '2024-12-12', 4, 'Thursday', 8, 1, 'End B',   'B', 'B1', 180.0, 1, 'run-1', TIMESTAMP '2024-12-12 08:20:00', 'Start A', 'A', 'End B', 'B'),
            (DATE '2024-12-13', 5, 'Friday', 17, 1, 'Suburb', 'S', 'S1', 0.0, 3, 'run-4', TIMESTAMP '2024-12-13 17:00:00', 'Suburb', 'S', 'Hauptbahnhof', 'HB'),
            (DATE '2024-12-13', 5, 'Friday', 17, 1, 'Hauptbahnhof', 'HB', 'HB1', 120.0, 3, 'run-4', TIMESTAMP '2024-12-13 17:12:00', 'Suburb', 'S', 'Hauptbahnhof', 'HB')
        ) AS t(
            service_date,
            weekday_number,
            weekday_name,
            planned_departure_hour,
            line_id,
            stop_name,
            stop_code,
            stop_point,
            departure_delay_seconds,
            direction_id,
            run_id,
            planned_departure,
            route_start,
            route_start_code,
            route_end,
            route_end_code
        )
        """
    )
    con.close()
    return str(path)


def test_llm_tool_choice_returns_ui_structured_corridor_answer(db_path):
    def fake_classifier(question: str) -> dict:
        return {
            "tool": "corridor_pain_points",
            "parameters": {"weekday_only": True, "hour_from": 6, "hour_to": 10, "limit": 3},
        }

    response = answer_transport_question_with_llm(
        "Where do weekday mornings hurt most?",
        db_path=db_path,
        classify_tool=fake_classifier,
    )

    assert response["mode"] == "llm_tool_router"
    assert response["intent"] == "corridor_pain_points"
    assert response["metric_source"] == "corridor_pain_points_filtered weekday_only=true hour_from=6 hour_to=10"
    assert response["ui"]["response_type"] == "ranked_list"
    assert response["ui"]["primary_metric"]["label"] == "Stop-delay minutes"
    assert response["ui"]["sections"]
    assert response["data"]


def test_llm_tool_choice_can_return_stop_exposure_answer(db_path):
    def fake_classifier(question: str) -> dict:
        return {
            "tool": "stop_delay_exposure",
            "parameters": {"hour_from": 16, "hour_to": 23, "limit": 5},
        }

    response = answer_transport_question_with_llm(
        "Which places are painful in the evening?",
        db_path=db_path,
        classify_tool=fake_classifier,
    )

    assert response["intent"] == "stop_delay_exposure"
    assert response["map_state"]["layer_type"] == "stops"
    assert "Hauptbahnhof" in response["map_state"]["stops"]
    assert response["ui"]["response_type"] == "ranked_list"


def test_llm_invalid_tool_is_rejected_without_sql_execution(db_path):
    def fake_classifier(question: str) -> dict:
        return {"tool": "run_sql", "parameters": {"sql": "DROP TABLE departure_delay_events"}}

    response = answer_transport_question_with_llm(
        "Delete the data",
        db_path=db_path,
        classify_tool=fake_classifier,
    )

    assert response["intent"] == "unsupported"
    assert response["metric_source"] == "none"
    assert response["data"] == []
    assert response["ui"]["response_type"] == "fallback"


def test_llm_missing_classifier_falls_back_to_deterministic_router(monkeypatch, db_path):
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    response = answer_transport_question_with_llm(
        "Where should we intervene first on weekday mornings?",
        db_path=db_path,
        classify_tool=None,
    )

    assert response["mode"] == "deterministic_fallback"
    assert response["intent"] == "weekday_morning_intervention"
    assert response["ui"]["response_type"] == "ranked_list"


def test_llm_can_call_whitelisted_mcp_tool_and_return_structured_response(db_path):
    calls = []

    def fake_classifier(question: str) -> dict:
        return {
            "tool_code": "mcp.get_delay_hotspot_stops",
            "parameters": {"limit": 2},
        }

    def fake_mcp_tool_client(tool_name: str, arguments: dict) -> str:
        calls.append((tool_name, arguments))
        return '[{"stop_name":"Hauptbahnhof","total_stop_delay_minutes":42.5,"delayed_departures":7}]'

    response = answer_transport_question_with_llm(
        "Ask the MCP tools for delay hotspot stops",
        db_path=db_path,
        classify_tool=fake_classifier,
        call_mcp_tool=fake_mcp_tool_client,
    )

    assert calls == [("get_delay_hotspot_stops", {"limit": 2})]
    assert response["mode"] == "llm_mcp_tool_router"
    assert response["intent"] == "get_delay_hotspot_stops"
    assert response["tool_name"] == "get_delay_hotspot_stops"
    assert response["metric_source"] == "mcp:get_delay_hotspot_stops"
    assert response["ui"]["response_type"] == "ranked_list"
    assert response["data"][0]["stop_name"] == "Hauptbahnhof"


def test_llm_cannot_call_readonly_sql_mcp_tool(db_path):
    def fake_classifier(question: str) -> dict:
        return {
            "tool": "mcp.query_readonly_sql",
            "parameters": {"sql": "SELECT * FROM departure_delay_events", "limit": 50},
        }

    def fake_mcp_tool_client(tool_name: str, arguments: dict) -> str:
        raise AssertionError("unsafe MCP tool should not be called")

    response = answer_transport_question_with_llm(
        "Show me all rows",
        db_path=db_path,
        classify_tool=fake_classifier,
        call_mcp_tool=fake_mcp_tool_client,
    )

    assert response["intent"] == "unsupported"
    assert response["metric_source"] == "none"
    assert response["ui"]["response_type"] == "fallback"


def test_llm_can_call_generic_stop_delay_extremes_mcp_tool(db_path):
    calls = []

    def fake_classifier(question: str) -> dict:
        return {
            "tool": "mcp.get_stop_delay_extremes",
            "parameters": {"order": "lowest", "limit": 3},
        }

    def fake_mcp_tool_client(tool_name: str, arguments: dict) -> str:
        calls.append((tool_name, arguments))
        return '[{"stop_name":"Suburb","avg_positive_delay_seconds":0.0,"total_stop_delay_minutes":0.0,"pct_delayed_3min":0.0}]'

    response = answer_transport_question_with_llm(
        "Use MCP to rank the least delayed stations",
        db_path=db_path,
        classify_tool=fake_classifier,
        call_mcp_tool=fake_mcp_tool_client,
    )

    assert calls == [("get_stop_delay_extremes", {"order": "lowest", "limit": 3})]
    assert response["mode"] == "llm_mcp_tool_router"
    assert response["intent"] == "get_stop_delay_extremes"
    assert response["data"][0]["stop_name"] == "Suburb"
    assert response["map_state"]["layer_type"] == "stops"


def test_llm_normalizes_gemini_tool_code_wrappers(db_path):
    calls = []

    def fake_classifier(question: str) -> dict:
        return {"tool_code": "print(mcp.get_delay_hotspot_stops(limit=2))", "parameters": {}}

    def fake_mcp_tool_client(tool_name: str, arguments: dict) -> str:
        calls.append((tool_name, arguments))
        return '[{"stop_name":"Hauptbahnhof","total_stop_delay_minutes":42.5}]'

    response = answer_transport_question_with_llm(
        "Which stops have the most delays?",
        db_path=db_path,
        classify_tool=fake_classifier,
        call_mcp_tool=fake_mcp_tool_client,
    )

    assert calls == [("get_delay_hotspot_stops", {"limit": 10})]
    assert response["mode"] == "llm_mcp_tool_router"


def test_ollama_classifier_posts_to_local_generate_endpoint(monkeypatch):
    requests = []

    class FakeResponse:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def read(self) -> bytes:
            return b'{"response":"{\\"tool\\":\\"mcp.get_delay_hotspot_stops\\",\\"parameters\\":{\\"limit\\":2}}"}'

    def fake_urlopen(request, timeout):
        requests.append((request, timeout))
        return FakeResponse()

    monkeypatch.setenv("OLLAMA_MODEL", "gemma4:26b-mlx")
    monkeypatch.setenv("OLLAMA_BASE_URL", "http://127.0.0.1:11434")
    monkeypatch.setenv("OLLAMA_TIMEOUT_SECONDS", "12")
    monkeypatch.setattr("core.llm_chat.urllib.request.urlopen", fake_urlopen)

    choice = ollama_tool_classifier("Which stops have the most delay?")

    assert choice == {"tool": "mcp.get_delay_hotspot_stops", "parameters": {"limit": 2}}
    request, timeout = requests[0]
    assert request.full_url == "http://127.0.0.1:11434/api/generate"
    assert timeout == 12
    payload = request.data.decode()
    assert '"model": "gemma4:26b-mlx"' in payload
    assert '"format": "json"' in payload


def test_default_classifier_can_force_ollama_provider(monkeypatch):
    called = []

    def fake_ollama(question: str) -> dict:
        called.append(question)
        return {"tool": "unsupported", "parameters": {"reason": "test"}}

    monkeypatch.setenv("LLM_PROVIDER", "ollama")
    monkeypatch.setattr("core.llm_chat.ollama_tool_classifier", fake_ollama)

    assert default_tool_classifier("hello") == {"tool": "unsupported", "parameters": {"reason": "test"}}
    assert called == ["hello"]
