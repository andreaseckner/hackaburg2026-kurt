from __future__ import annotations

import duckdb
import pytest

from core.chat import SUGGESTED_QUESTIONS, answer_transport_question


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


def test_weekday_morning_intervention_routes_to_corridor_answer(db_path):
    response = answer_transport_question("Where should we intervene first on weekday mornings?", db_path)

    assert response["intent"] == "weekday_morning_intervention"
    assert response["confidence"] == 1.0
    assert response["metric_source"] == "corridor_pain_points_filtered weekday_only=true hour_from=6 hour_to=10"
    assert response["map_state"]["layer_type"] == "corridor"
    assert response["data"]


def test_city_center_segment_question_routes_to_delay_growth_answer(db_path):
    response = answer_transport_question("Which segment creates the most delay toward the city center?", db_path)

    assert response["intent"] == "city_center_delay_growth_segment"
    assert response["metric_source"] == "segment_delay_growth_filtered toward_city_center=true"
    assert response["map_state"]["layer_type"] == "segment"
    assert response["map_state"]["segments"]


def test_passenger_delay_exposure_after_16_routes_to_stop_answer(db_path):
    response = answer_transport_question("Which stops expose passengers to the most delay after 16:00?", db_path)

    assert response["intent"] == "passenger_delay_exposure"
    assert response["metric_source"] == "stop_delay_exposure_filtered hour_from=16 hour_to=23"
    assert response["map_state"]["layer_type"] == "stops"
    assert "Hauptbahnhof" in response["map_state"]["stops"]


def test_passenger_delay_exposure_after_17_routes_to_stop_answer(db_path):
    response = answer_transport_question("Which stops expose passengers to the most delay after 17:00?", db_path)

    assert response["intent"] == "passenger_delay_exposure"
    assert response["metric_source"] == "stop_delay_exposure_filtered hour_from=17 hour_to=23"
    assert response["map_state"]["hour_from"] == 17
    assert response["map_state"]["layer_type"] == "stops"
    assert "Hauptbahnhof" in response["map_state"]["stops"]


def test_unsupported_question_returns_suggestions(db_path):
    response = answer_transport_question("Will it rain tomorrow?", db_path)

    assert response["intent"] == "unsupported"
    assert response["metric_source"] == "none"
    assert response["map_state"] is None
    assert response["suggested_questions"] == SUGGESTED_QUESTIONS


def test_lowest_delay_station_question_routes_to_stop_extremes(db_path):
    response = answer_transport_question("what station has the lowest delay overall?", db_path)

    assert response["intent"] == "stop_delay_extremes"
    assert response["metric_source"] == "stop_delay_extremes order=lowest"
    assert response["map_state"]["layer_type"] == "stops"
    assert response["map_state"]["severity_metric"] == "avg_positive_delay_seconds"
    assert response["data"][0]["stop_name"] == "Suburb"


def test_date_delay_question_uses_end_to_end_trip_metrics(db_path):
    response = answer_transport_question("What was the most delay on 12.12.2024?", db_path)

    assert response["intent"] == "trip_delay_for_date"
    assert response["metric_source"] == "trip_delay_summary max positive delay per end-to-end trip"
    assert response["map_state"]["severity_metric"] == "total_trip_delay_minutes"
    assert response["data"][0]["total_trip_delay_minutes"] == 4.0
    assert response["data"][0]["worst_trip_delay_minutes"] == 4.0
    assert response["data"][0]["total_stop_delay_minutes"] == 8.0
    assert "Stop-level burden, for context only" in response["bullets"][-1]


def test_iso_date_delay_question_uses_end_to_end_trip_metrics(db_path):
    response = answer_transport_question("How much delay on 2024-12-12?", db_path)

    assert response["intent"] == "trip_delay_for_date"
    assert response["data"][0]["total_trip_delay_minutes"] == 4.0


def test_sql_like_question_is_not_executed(db_path):
    response = answer_transport_question("SELECT * FROM departure_delay_events;", db_path)

    assert response["intent"] == "unsupported"
    assert response["metric_source"] == "none"
    assert response["data"] == []
