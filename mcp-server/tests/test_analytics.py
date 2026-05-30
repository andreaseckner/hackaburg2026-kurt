from __future__ import annotations

from datetime import date

import duckdb
import pytest

from core.analytics import (
    compare_directions,
    explain_pain_points_for_day,
    get_bottleneck_stops,
    get_corridor_pain_points,
    get_corridor_pain_points_filtered,
    get_days_with_most_delays,
    get_delay_attribute_values,
    get_delay_event_records,
    get_delay_ranking,
    get_delays_by_hour,
    get_delays_by_weekday,
    get_early_departures,
    get_segment_delay_growth_hotspots,
    get_segment_delay_growth_hotspots_filtered,
    get_stop_delay_exposure_filtered,
    get_stop_delay_extremes,
    get_trip_delay_summary,
    get_worst_stops,
    run_readonly_sql,
)


@pytest.fixture()
def db_path(tmp_path):
    path = tmp_path / "transport.duckdb"
    con = duckdb.connect(str(path))
    con.execute(
        """
        CREATE TABLE daily_delay_metrics AS
        SELECT * FROM (VALUES
            (DATE '2024-12-12', 'Thursday', 1, 6, 12.0, 120.0, 3, 1),
            (DATE '2024-12-13', 'Friday', 1, 4, 6.0, 90.0, 1, 2)
        ) AS t(
            service_date,
            weekday_name,
            line_id,
            event_count,
            total_positive_delay_minutes,
            avg_positive_delay_seconds,
            delayed_3min_events,
            early_1min_events
        )
        """
    )
    con.execute(
        """
        CREATE TABLE departure_delay_events AS
        SELECT * FROM (VALUES
            (DATE '2024-12-12', 4, 'Thursday', 8, 1, 'Start A', 'A', 'A1',  60.0, 1, 'run-1', TIMESTAMP '2024-12-12 08:00:00', 'Start A', 'A', 'End B', 'B'),
            (DATE '2024-12-12', 4, 'Thursday', 8, 1, 'Middle',  'M', 'M1', 240.0, 1, 'run-1', TIMESTAMP '2024-12-12 08:10:00', 'Start A', 'A', 'End B', 'B'),
            (DATE '2024-12-12', 4, 'Thursday', 8, 1, 'End B',   'B', 'B1', 180.0, 1, 'run-1', TIMESTAMP '2024-12-12 08:20:00', 'Start A', 'A', 'End B', 'B'),
            (DATE '2024-12-12', 4, 'Thursday', 9, 1, 'End B',   'B', 'B1', -90.0, 2, 'run-2', TIMESTAMP '2024-12-12 09:00:00', 'End B', 'B', 'Start A', 'A'),
            (DATE '2024-12-12', 4, 'Thursday', 9, 1, 'Middle',  'M', 'M1', 120.0, 2, 'run-2', TIMESTAMP '2024-12-12 09:10:00', 'End B', 'B', 'Start A', 'A'),
            (DATE '2024-12-12', 4, 'Thursday', 9, 1, 'Start A', 'A', 'A1', 300.0, 2, 'run-2', TIMESTAMP '2024-12-12 09:20:00', 'End B', 'B', 'Start A', 'A'),
            (DATE '2024-12-13', 5, 'Friday', 10, 1, 'Start A', 'A', 'A1', 30.0, 1, 'run-3', TIMESTAMP '2024-12-13 10:00:00', 'Start A', 'A', 'End B', 'B'),
            (DATE '2024-12-13', 5, 'Friday', 10, 1, 'End B',   'B', 'B1', 90.0, 1, 'run-3', TIMESTAMP '2024-12-13 10:20:00', 'Start A', 'A', 'End B', 'B'),
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


def test_get_days_with_most_delays_returns_ranked_days(db_path):
    rows = get_days_with_most_delays(db_path, limit=2)

    assert len(rows) == 2
    assert rows[0]["service_date"] == date(2024, 12, 12)
    assert rows[0]["total_trip_delay_minutes"] >= rows[1]["total_trip_delay_minutes"]
    assert rows[0]["total_stop_delay_minutes"] > rows[0]["total_trip_delay_minutes"]
    assert rows[0]["line_id"] == 1


def test_get_delays_by_weekday_returns_weekday_metrics_sorted_by_delay(db_path):
    rows = get_delays_by_weekday(db_path)

    assert rows
    assert {"weekday_name", "event_count", "total_stop_delay_minutes", "avg_daily_stop_delay_minutes", "delayed_3min_events"} <= rows[0].keys()
    assert rows[0]["total_stop_delay_minutes"] >= rows[-1]["total_stop_delay_minutes"]


def test_get_delays_by_hour_returns_hour_buckets(db_path):
    rows = get_delays_by_hour(db_path)

    hours = {row["hour"] for row in rows}
    assert min(hours) >= 0
    assert max(hours) <= 23
    assert {"hour", "event_count", "total_stop_delay_minutes", "avg_delay_seconds"} <= rows[0].keys()


def test_get_worst_stops_returns_stop_delay_hotspots(db_path):
    rows = get_worst_stops(db_path, limit=2)

    assert len(rows) == 2
    assert rows[0]["stop_name"]
    assert rows[0]["total_stop_delay_minutes"] >= rows[1]["total_stop_delay_minutes"]
    assert "avg_daily_stop_delay_minutes" in rows[0]
    assert "delayed_3min_events" in rows[0]


def test_get_worst_stops_can_filter_to_one_day(db_path):
    rows = get_worst_stops(db_path, limit=2, service_date="2024-12-12")

    assert len(rows) == 2
    assert rows[0]["service_days"] == 1
    assert rows[0]["total_stop_delay_minutes"] == rows[0]["avg_daily_stop_delay_minutes"]


def test_get_early_departures_returns_early_departure_hotspots(db_path):
    rows = get_early_departures(db_path, limit=2)

    assert rows
    assert rows[0]["early_1min_events"] > 0
    assert rows[0]["avg_early_seconds"] > 0


def test_get_bottleneck_stops_returns_delay_growth_hotspots(db_path):
    rows = get_bottleneck_stops(db_path, limit=2)

    assert rows
    assert rows[0]["stop_name"]
    assert rows[0]["avg_delay_growth_seconds"] >= rows[-1]["avg_delay_growth_seconds"]


def test_compare_directions_returns_direction_level_metrics(db_path):
    rows = compare_directions(db_path)

    assert rows
    assert {"direction_id", "route_start", "route_end", "total_stop_delay_minutes"} <= rows[0].keys()


def test_get_trip_delay_summary_returns_user_friendly_trip_metrics(db_path):
    summary = get_trip_delay_summary(db_path, service_date="2024-12-12")

    assert summary["service_date"] == date(2024, 12, 12)
    assert summary["approx_trips"] == 2
    assert summary["total_trip_delay_minutes"] == 9.0
    assert summary["total_trip_delay_hours"] == 0.15
    assert summary["avg_max_delay_per_trip_minutes"] == 4.5
    assert summary["trips_delayed_3min"] == 2
    assert summary["trips_delayed_5min"] == 1
    assert summary["total_stop_delay_minutes"] > summary["total_trip_delay_minutes"]
    assert "plain_language_summary" in summary


def test_get_corridor_pain_points_ranks_directional_route_problems(db_path):
    rows = get_corridor_pain_points(db_path, limit=2)

    assert len(rows) == 2
    assert rows[0]["route_start"] == "Start A"
    assert rows[0]["route_end"] == "End B"
    assert rows[0]["total_stop_delay_minutes"] == 10.0
    assert rows[0]["pct_delayed_3min"] == 40.0
    assert rows[0]["worst_hour"]["hour"] == 8
    assert rows[0]["worst_day"]["service_date"] == date(2024, 12, 12)


def test_get_segment_delay_growth_hotspots_finds_where_delay_is_added(db_path):
    rows = get_segment_delay_growth_hotspots(db_path, limit=2, min_growth_1min_events=1)

    assert len(rows) == 2
    assert rows[0]["previous_stop"] == "B"
    assert rows[0]["current_stop"] == "M"
    assert rows[0]["route_start"] == "End B"
    assert rows[0]["route_end"] == "Start A"
    assert rows[0]["avg_growth_seconds"] == 210.0
    assert rows[0]["growth_1min_events"] == 1


def test_get_stop_delay_exposure_filtered_after_16_returns_stop_hotspots(db_path):
    rows = get_stop_delay_exposure_filtered(db_path, hour_from=16, hour_to=23, limit=5)

    assert rows
    assert rows[0]["stop_name"] == "Hauptbahnhof"
    assert rows[0]["total_stop_delay_minutes"] == 2.0
    assert rows[0]["pct_delayed_3min"] == 0.0


def test_get_stop_delay_extremes_returns_lowest_average_delay_stops(db_path):
    rows = get_stop_delay_extremes(db_path, order="lowest", limit=3)

    assert len(rows) == 3
    assert rows[0]["stop_name"] == "Suburb"
    assert rows[0]["avg_positive_delay_seconds"] == 0.0
    assert rows[0]["total_stop_delay_minutes"] == 0.0
    assert rows[0]["pct_delayed_3min"] == 0.0
    assert rows[0]["ranking_metric"] == "avg_positive_delay_seconds"


def test_get_stop_delay_extremes_returns_highest_average_delay_stops(db_path):
    rows = get_stop_delay_extremes(db_path, order="highest", limit=1)

    assert rows[0]["stop_name"] == "Middle"
    assert rows[0]["avg_positive_delay_seconds"] == 180.0


def test_get_corridor_pain_points_filtered_supports_weekday_morning(db_path):
    rows = get_corridor_pain_points_filtered(
        db_path,
        weekday_only=True,
        hour_from=6,
        hour_to=10,
        limit=2,
    )

    assert len(rows) == 2
    assert rows[0]["route_start"] == "End B"
    assert rows[0]["route_end"] == "Start A"
    assert rows[0]["avg_daily_stop_delay_minutes"] == 7.0
    assert rows[0]["avg_daily_stop_events"] == 3.0
    assert rows[0]["worst_hour"]["hour"] == 9
    assert rows[0]["worst_day"]["service_date"] == date(2024, 12, 12)


def test_get_segment_delay_growth_hotspots_filtered_toward_city_center(db_path):
    rows = get_segment_delay_growth_hotspots_filtered(
        db_path,
        limit=3,
        min_growth_1min_events=1,
        toward_city_center=True,
    )

    assert rows
    assert rows[0]["route_end"] == "Hauptbahnhof"
    assert rows[0]["previous_stop"] == "S"
    assert rows[0]["current_stop"] == "HB"
    assert rows[0]["avg_growth_seconds"] == 120.0


def test_explain_pain_points_for_day_returns_demo_ready_day_story(db_path):
    story = explain_pain_points_for_day(db_path, service_date="2024-12-12")

    assert story["service_date"] == date(2024, 12, 12)
    assert story["trip_summary"]["approx_trips"] == 2
    assert story["worst_corridor"]["route_start"] == "Start A"
    assert story["worst_corridor"]["route_end"] == "End B"
    assert story["worst_hour"]["hour"] == 8
    assert story["worst_stops"][0]["stop_name"] == "A"
    assert "Start A → End B" in story["plain_language_summary"]


def test_readonly_sql_rejects_multiple_statements(db_path):
    with pytest.raises(ValueError, match="single SQL statement"):
        run_readonly_sql("SELECT 1; SELECT 2", db_path)


def test_readonly_sql_disables_external_file_access(db_path):
    with pytest.raises(Exception):
        run_readonly_sql("SELECT * FROM read_csv_auto('/etc/passwd')", db_path)


# ---------------------------------------------------------------------------
# get_delay_ranking tests
# ---------------------------------------------------------------------------


def test_delay_attribute_values_lists_lines_with_counts(db_path):
    rows = get_delay_attribute_values("line_id", db_path=db_path)

    assert rows == [{"value": "1", "event_count": 10}]


def test_delay_event_records_selects_attributes_and_filters(db_path):
    rows = get_delay_event_records(
        attributes=["service_date", "line_id", "stop_name", "departure_delay_minutes"],
        filters={"line_id": "1", "stop_name": "Middle"},
        order_by="departure_delay_minutes",
        limit=2,
        db_path=db_path,
    )

    assert rows == [
        {
            "service_date": "2024-12-12",
            "line_id": "1",
            "stop_name": "Middle",
            "departure_delay_minutes": 4.0,
        },
        {
            "service_date": "2024-12-12",
            "line_id": "1",
            "stop_name": "Middle",
            "departure_delay_minutes": 2.0,
        },
    ]


def test_delay_event_records_rejects_unsupported_attributes(db_path):
    with pytest.raises(ValueError):
        get_delay_event_records(attributes=["secret"], db_path=db_path)


def test_delay_ranking_by_stop_highest(db_path):
    rows = get_delay_ranking(group_by="stop", order="highest", limit=2, db_path=db_path)
    assert len(rows) == 2
    assert rows[0]["stop_name"] is not None
    assert rows[0]["total_stop_delay_minutes"] >= rows[1]["total_stop_delay_minutes"]


def test_delay_ranking_by_stop_lowest(db_path):
    rows = get_delay_ranking(group_by="stop", order="lowest", limit=2, db_path=db_path)
    assert len(rows) == 2
    assert rows[0]["total_stop_delay_minutes"] <= rows[1]["total_stop_delay_minutes"]


def test_delay_ranking_by_date(db_path):
    rows = get_delay_ranking(group_by="date", limit=5, db_path=db_path)
    assert len(rows) >= 1
    assert "service_date" in rows[0]
    assert "weekday_name" in rows[0]


def test_delay_ranking_date_filter(db_path):
    rows = get_delay_ranking(group_by="stop", date_from="2024-12-12", date_to="2024-12-12", db_path=db_path)
    assert all(r["service_days"] == 1 for r in rows)


def test_delay_ranking_weekday_only(db_path):
    rows = get_delay_ranking(group_by="weekday", weekday_only=True, db_path=db_path)
    weekday_names = {r["weekday_name"] for r in rows}
    assert "Sunday" not in weekday_names
    assert "Saturday" not in weekday_names


def test_delay_ranking_hour_filter(db_path):
    rows = get_delay_ranking(group_by="stop", hour_from=8, hour_to=9, db_path=db_path)
    assert len(rows) >= 1


def test_delay_ranking_line_filter(db_path):
    rows = get_delay_ranking(group_by="date", line_id=1, limit=5, db_path=db_path)
    assert len(rows) == 2
    assert {str(row["service_date"]) for row in rows} == {"2024-12-12", "2024-12-13"}
    assert sum(row["event_count"] for row in rows) == 10


def test_delay_ranking_overall_line_and_hour_filter(db_path):
    rows = get_delay_ranking(group_by="overall", line_id=1, hour_from=8, hour_to=9, db_path=db_path)
    assert len(rows) == 1
    assert rows[0]["scope"] == "overall"
    assert rows[0]["event_count"] == 6
    assert rows[0]["service_days"] == 1


def test_delay_ranking_by_corridor(db_path):
    rows = get_delay_ranking(group_by="corridor", limit=5, db_path=db_path)
    assert len(rows) >= 1
    assert "route_start" in rows[0]
    assert "route_end" in rows[0]


def test_delay_ranking_invalid_group_by(db_path):
    with pytest.raises(ValueError, match="group_by must be one of"):
        get_delay_ranking(group_by="invalid", db_path=db_path)
