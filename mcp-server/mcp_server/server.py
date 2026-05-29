from __future__ import annotations

import json
from typing import Any

from mcp.server.fastmcp import FastMCP

from core.analytics import (
    compare_directions,
    describe_table,
    explain_pain_points_for_day,
    get_bottleneck_stops,
    get_corridor_pain_points,
    get_days_with_most_delays,
    get_delay_ranking,
    get_delays_by_hour,
    get_delays_by_weekday,
    get_early_departures,
    get_segment_delay_growth_hotspots,
    get_stop_delay_extremes as get_stop_delay_extremes_rows,
    get_trip_delay_summary,
    get_worst_stops,
    list_tables,
    raw_table_overview,
    run_readonly_sql,
)
from core.chat import answer_transport_question
from core.db import resolve_db_path


mcp = FastMCP("hackathon-2026-transport")


@mcp.tool()
def health_check() -> dict[str, Any]:
    """Return basic MCP/database health information."""
    db_path = resolve_db_path()
    return {
        "status": "ok",
        "database_path": str(db_path),
        "database_exists": db_path.exists(),
    }


@mcp.tool()
def get_tables() -> list[str]:
    """List tables available in the DuckDB database."""
    return list_tables()


@mcp.tool()
def get_table_schema(table_name: str) -> list[dict[str, Any]]:
    """Describe a DuckDB table schema."""
    return describe_table(table_name)


@mcp.tool()
def get_raw_table_overview() -> list[dict[str, Any]]:
    """Return row counts for raw imported tables."""
    return raw_table_overview()


@mcp.tool()
def get_top_delay_days(limit: int = 10) -> str:
    """Return the days on Line 1 with the highest trip-level delay; stop-level burden is included separately."""
    rows = get_days_with_most_delays(limit=limit)
    return json.dumps(rows, default=str, ensure_ascii=False, indent=2)


@mcp.tool()
def get_delay_by_weekday(order: str = "highest") -> str:
    """Return stop-level delay burden grouped by weekday. order='lowest' for least delayed days first, 'highest' (default) for most delayed."""
    rows = get_delays_by_weekday(order=order)
    return json.dumps(rows, default=str, ensure_ascii=False, indent=2)


@mcp.tool()
def get_delay_by_hour() -> str:
    """Return stop-level delay burden grouped by planned departure hour across the dataset."""
    rows = get_delays_by_hour()
    return json.dumps(rows, default=str, ensure_ascii=False, indent=2)


@mcp.tool()
def get_delay_hotspot_stops(limit: int = 10, service_date: str | None = None) -> str:
    """Return stop-level delay hot spots. Pass service_date='YYYY-MM-DD' for day-specific answers."""
    rows = get_worst_stops(limit=limit, service_date=service_date)
    return json.dumps(rows, default=str, ensure_ascii=False, indent=2)


@mcp.tool()
def get_stop_delay_extremes(order: str = "lowest", limit: int = 10, min_events: int = 1) -> str:
    """Return stops with the lowest or highest average positive delay overall."""
    rows = get_stop_delay_extremes_rows(order=order, limit=limit, min_events=min_events)
    return json.dumps(rows, default=str, ensure_ascii=False, indent=2)


@mcp.tool()
def get_early_departure_hotspots(limit: int = 10) -> str:
    """Return stops where buses leave early most often."""
    rows = get_early_departures(limit=limit)
    return json.dumps(rows, default=str, ensure_ascii=False, indent=2)


@mcp.tool()
def get_bottleneck_stop_hotspots(limit: int = 10) -> str:
    """Return stops where delay tends to grow compared with the previous stop in the same run."""
    rows = get_bottleneck_stops(limit=limit)
    return json.dumps(rows, default=str, ensure_ascii=False, indent=2)


@mcp.tool()
def compare_route_directions() -> str:
    """Compare reliability metrics between route directions."""
    rows = compare_directions()
    return json.dumps(rows, default=str, ensure_ascii=False, indent=2)


@mcp.tool()
def explain_trip_delay_for_day(service_date: str = "2024-12-12") -> str:
    """Return easy-to-understand trip-level delay minutes/hours for one day."""
    summary = get_trip_delay_summary(service_date=service_date)
    return json.dumps(summary, default=str, ensure_ascii=False, indent=2)


@mcp.tool()
def get_corridor_reliability_pain_points(limit: int = 10) -> str:
    """Rank from-to route corridors by recurring delay burden and delayed-event rate."""
    rows = get_corridor_pain_points(limit=limit)
    return json.dumps(rows, default=str, ensure_ascii=False, indent=2)


@mcp.tool()
def get_delay_growth_segments(limit: int = 10, min_growth_1min_events: int = 100) -> str:
    """Return stop-to-stop segments where buses repeatedly gain delay inside trips."""
    rows = get_segment_delay_growth_hotspots(
        limit=limit,
        min_growth_1min_events=min_growth_1min_events,
    )
    return json.dumps(rows, default=str, ensure_ascii=False, indent=2)


@mcp.tool()
def explain_reliability_pain_points_for_day(service_date: str = "2024-12-12") -> str:
    """Return a demo-ready day story: worst corridor, hour, stops, and trip-level delay."""
    story = explain_pain_points_for_day(service_date=service_date)
    return json.dumps(story, default=str, ensure_ascii=False, indent=2)


@mcp.tool()
def answer_reliability_question(question: str) -> str:
    """Answer a supported natural-language reliability question using deterministic analytics only."""
    response = answer_transport_question(question)
    return json.dumps(response, default=str, ensure_ascii=False, indent=2)


@mcp.tool()
def delay_ranking(
    group_by: str = "stop",
    date_from: str | None = None,
    date_to: str | None = None,
    weekday_only: bool = False,
    hour_from: int | None = None,
    hour_to: int | None = None,
    stop_name: str | None = None,
    direction: str | None = None,
    order: str = "highest",
    limit: int = 10,
) -> str:
    """Flexible delay ranking with filters.

    group_by: what to rank. One of: stop, weekday, hour, date, corridor, direction.
    date_from/date_to: restrict to a date range (YYYY-MM-DD).
    weekday_only: true to exclude Saturday/Sunday.
    hour_from/hour_to: restrict to planned departure hours (0-23).
    stop_name: filter to a specific stop.
    direction: filter to corridors involving this stop name.
    order: 'highest' (most delay first) or 'lowest' (least delay first).
    limit: max results (1-50).
    """
    rows = get_delay_ranking(
        group_by=group_by,
        date_from=date_from,
        date_to=date_to,
        weekday_only=weekday_only or None,
        hour_from=hour_from,
        hour_to=hour_to,
        stop_name=stop_name,
        direction=direction,
        order=order,
        limit=limit,
    )
    return json.dumps(rows, default=str, ensure_ascii=False, indent=2)


@mcp.tool()
def query_readonly_sql(sql: str, limit: int = 100) -> str:
    """Run a safe read-only SELECT query against the transport DuckDB database."""
    rows = run_readonly_sql(sql, limit=max(1, min(limit, 500)))
    return json.dumps(rows, default=str, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    mcp.run()
