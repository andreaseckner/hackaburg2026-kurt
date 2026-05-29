from __future__ import annotations

import duckdb
import pytest
from fastapi.testclient import TestClient

from api.server import app


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
            (DATE '2024-12-12', 4, 'Thursday', 8, 1, 'End B',   'B', 'B1', 180.0, 1, 'run-1', TIMESTAMP '2024-12-12 08:20:00', 'Start A', 'A', 'End B', 'B')
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


def test_health_returns_ok(monkeypatch, db_path):
    monkeypatch.setenv("TRANSPORT_DB_PATH", db_path)
    client = TestClient(app)

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"
    assert response.json()["database_exists"] is True


def test_chat_query_returns_supported_answer(monkeypatch, db_path):
    monkeypatch.setenv("TRANSPORT_DB_PATH", db_path)
    client = TestClient(app)

    response = client.post("/chat/query", json={"question": "Where should we intervene first on weekday mornings?"})

    assert response.status_code == 200
    assert response.json()["intent"] == "weekday_morning_intervention"


def test_chat_query_rejects_empty_question():
    client = TestClient(app)

    response = client.post("/chat/query", json={"question": ""})

    assert response.status_code == 422
