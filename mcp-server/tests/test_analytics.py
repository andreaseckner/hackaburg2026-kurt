from __future__ import annotations

from datetime import date

from core.analytics import (
    compare_directions,
    get_bottleneck_stops,
    get_days_with_most_delays,
    get_delays_by_hour,
    get_delays_by_weekday,
    get_early_departures,
    get_trip_delay_summary,
    get_worst_stops,
)

DB_PATH = "data/processed/transport.duckdb"


def test_get_days_with_most_delays_returns_ranked_days():
    rows = get_days_with_most_delays(DB_PATH, limit=3)

    assert len(rows) == 3
    assert rows[0]["service_date"] == date(2024, 12, 12)
    assert rows[0]["total_delay_minutes"] >= rows[1]["total_delay_minutes"]
    assert rows[0]["line_id"] == 1


def test_get_delays_by_weekday_returns_weekday_metrics_sorted_by_delay():
    rows = get_delays_by_weekday(DB_PATH)

    assert rows
    assert {"weekday_name", "event_count", "total_delay_minutes", "delayed_3min_events"} <= rows[0].keys()
    assert rows[0]["total_delay_minutes"] >= rows[-1]["total_delay_minutes"]


def test_get_delays_by_hour_returns_24_hour_buckets():
    rows = get_delays_by_hour(DB_PATH)

    hours = {row["hour"] for row in rows}
    assert min(hours) >= 0
    assert max(hours) <= 23
    assert {"hour", "event_count", "total_delay_minutes", "avg_delay_seconds"} <= rows[0].keys()


def test_get_worst_stops_returns_stop_delay_hotspots():
    rows = get_worst_stops(DB_PATH, limit=5)

    assert len(rows) == 5
    assert rows[0]["stop_name"]
    assert rows[0]["total_delay_minutes"] >= rows[1]["total_delay_minutes"]
    assert "delayed_3min_events" in rows[0]


def test_get_early_departures_returns_early_departure_hotspots():
    rows = get_early_departures(DB_PATH, limit=5)

    assert len(rows) == 5
    assert rows[0]["early_1min_events"] >= rows[1]["early_1min_events"]
    assert rows[0]["avg_early_seconds"] > 0


def test_get_bottleneck_stops_returns_delay_growth_hotspots():
    rows = get_bottleneck_stops(DB_PATH, limit=5)

    assert len(rows) == 5
    assert rows[0]["stop_name"]
    assert rows[0]["avg_delay_growth_seconds"] >= rows[1]["avg_delay_growth_seconds"]




def test_get_trip_delay_summary_returns_user_friendly_trip_metrics():
    summary = get_trip_delay_summary(DB_PATH, service_date="2024-12-12")

    assert summary["service_date"] == date(2024, 12, 12)
    assert summary["approx_trips"] == 190
    assert summary["total_trip_delay_minutes"] == 969.0
    assert summary["total_trip_delay_hours"] == 16.15
    assert summary["avg_max_delay_per_trip_minutes"] == 5.1
    assert summary["trips_delayed_3min"] == 106
    assert summary["trips_delayed_5min"] == 70
    assert summary["total_stop_delay_minutes"] > summary["total_trip_delay_minutes"]
    assert "plain_language_summary" in summary
    assert "16.15 hours" in summary["plain_language_summary"]
