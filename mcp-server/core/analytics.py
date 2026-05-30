from __future__ import annotations

import re
from typing import Any

from .db import connect


_WRITE_SQL = re.compile(r"\b(attach|copy|create|delete|drop|insert|install|load|pragma|set|update|vacuum)\b", re.IGNORECASE)


def _rows_as_dicts(result: Any) -> list[dict[str, Any]]:
    columns = [description[0] for description in result.description]
    return [dict(zip(columns, row, strict=True)) for row in result.fetchall()]


def _query(db_path: str | None, sql: str, params: list[Any] | None = None) -> list[dict[str, Any]]:
    with connect(db_path) as con:
        result = con.execute(sql, params or [])
        return _rows_as_dicts(result)


def _limit(limit: int, maximum: int = 100) -> int:
    return max(1, min(int(limit), maximum))


def _validate_hour(hour: int | None, name: str) -> None:
    if hour is not None and not 0 <= int(hour) <= 23:
        raise ValueError(f"{name} must be between 0 and 23")


def _time_filter_clauses(
    hour_from: int | None = None,
    hour_to: int | None = None,
    weekday_only: bool | None = None,
    table_alias: str | None = None,
) -> tuple[list[str], list[Any]]:
    _validate_hour(hour_from, "hour_from")
    _validate_hour(hour_to, "hour_to")
    prefix = f"{table_alias}." if table_alias else ""
    hour_expr = f"TRY_CAST({prefix}planned_departure_hour AS INTEGER)"
    weekday_expr = f"TRY_CAST({prefix}weekday_number AS INTEGER)"
    clauses: list[str] = []
    params: list[Any] = []
    if hour_from is not None:
        clauses.append(f"{hour_expr} >= ?")
        params.append(int(hour_from))
    if hour_to is not None:
        clauses.append(f"{hour_expr} <= ?")
        params.append(int(hour_to))
    if weekday_only is True:
        clauses.append(f"{weekday_expr} BETWEEN 1 AND 5")
    return clauses, params


def _where_sql(clauses: list[str]) -> str:
    return " AND ".join(clauses) if clauses else "TRUE"


_CITY_CENTER_STOP_KEYWORDS = (
    "hauptbahnhof",
    "dachauplatz",
    "arnulfsplatz",
    "albertstraße",
    "albertstrasse",
)


def list_tables(db_path: str | None = None) -> list[str]:
    with connect(db_path) as con:
        rows = con.execute(
            """
            SELECT table_name
            FROM information_schema.tables
            WHERE table_schema = 'main'
            ORDER BY table_name
            """
        ).fetchall()
    return [row[0] for row in rows]


def describe_table(table_name: str, db_path: str | None = None) -> list[dict[str, Any]]:
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", table_name):
        raise ValueError("Invalid table name")
    with connect(db_path) as con:
        rows = con.execute(f"DESCRIBE {table_name}").fetchall()
    return [
        {
            "column_name": row[0],
            "column_type": row[1],
            "null": row[2],
            "key": row[3],
            "default": row[4],
            "extra": row[5],
        }
        for row in rows
    ]


def run_readonly_sql(sql: str, db_path: str | None = None, limit: int = 100) -> list[dict[str, Any]]:
    normalized = sql.strip().rstrip(";")
    if not normalized.lower().startswith("select"):
        raise ValueError("Only SELECT statements are allowed")
    if _WRITE_SQL.search(normalized):
        raise ValueError("SQL contains a blocked keyword")

    limit = _limit(limit, maximum=500)
    with connect(db_path) as con:
        try:
            statements = con.extract_statements(normalized)
        except Exception as exc:
            raise ValueError(f"Invalid SQL: {exc}") from exc
        if len(statements) != 1:
            raise ValueError("Only a single SQL statement is allowed")

        limited_sql = f"SELECT * FROM ({normalized}) AS readonly_query LIMIT ?"
        result = con.execute(limited_sql, [limit])
        return _rows_as_dicts(result)


def raw_table_overview(db_path: str | None = None) -> list[dict[str, Any]]:
    tables = list_tables(db_path)
    overview = []
    with connect(db_path) as con:
        for table in tables:
            if table == "ingest_files":
                continue
            row_count = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
            overview.append({"table_name": table, "row_count": int(row_count)})
    return overview


def get_days_with_most_delays(db_path: str | None = None, limit: int = 10) -> list[dict[str, Any]]:
    limit = _limit(limit)
    sql = """
        WITH trip_starts AS (
          SELECT
            service_date,
            weekday_name,
            line_id,
            direction_id,
            run_id,
            route_start,
            route_start_code,
            route_end,
            route_end_code,
            planned_departure AS trip_start_time,
            LEAD(planned_departure) OVER (
              PARTITION BY service_date, line_id, direction_id, run_id, route_start, route_end
              ORDER BY planned_departure
            ) AS next_trip_start_time
          FROM departure_delay_events
          WHERE stop_name = route_start OR stop_code = route_start_code
        ),
        trip_metrics AS (
          SELECT
            t.service_date,
            t.weekday_name,
            t.line_id,
            t.direction_id,
            t.run_id,
            t.route_start,
            t.route_end,
            t.trip_start_time,
            MAX(GREATEST(e.departure_delay_seconds, 0)) AS max_positive_delay_seconds,
            SUM(GREATEST(e.departure_delay_seconds, 0)) AS stop_delay_seconds
          FROM trip_starts t
          JOIN departure_delay_events e
            ON e.service_date = t.service_date
           AND e.line_id = t.line_id
           AND e.direction_id = t.direction_id
           AND e.run_id = t.run_id
           AND e.route_start = t.route_start
           AND e.route_end = t.route_end
           AND e.planned_departure >= t.trip_start_time
           AND (t.next_trip_start_time IS NULL OR e.planned_departure < t.next_trip_start_time)
          GROUP BY t.service_date, t.weekday_name, t.line_id, t.direction_id, t.run_id, t.route_start, t.route_end, t.trip_start_time
        )
        SELECT
          service_date,
          weekday_name,
          line_id,
          COUNT(*) AS approx_trips,
          ROUND(SUM(max_positive_delay_seconds) / 60.0, 1) AS total_trip_delay_minutes,
          ROUND(SUM(max_positive_delay_seconds) / 3600.0, 2) AS total_trip_delay_hours,
          ROUND(AVG(max_positive_delay_seconds) / 60.0, 1) AS avg_max_delay_per_trip_minutes,
          ROUND(MAX(max_positive_delay_seconds) / 60.0, 1) AS worst_trip_delay_minutes,
          SUM(CASE WHEN max_positive_delay_seconds >= 180 THEN 1 ELSE 0 END) AS trips_delayed_3min,
          ROUND(SUM(stop_delay_seconds) / 60.0, 1) AS total_stop_delay_minutes
        FROM trip_metrics
        GROUP BY service_date, weekday_name, line_id
        ORDER BY total_trip_delay_minutes DESC
        LIMIT ?
    """
    return _query(db_path, sql, [limit])


def get_delays_by_weekday(db_path: str | None = None, order: str = "highest") -> list[dict[str, Any]]:
    direction = "ASC" if order == "lowest" else "DESC"
    sql = f"""
        SELECT
          weekday_name,
          CAST(MIN(weekday_number) AS INTEGER) AS weekday_number,
          line_id,
          COUNT(DISTINCT service_date) AS service_days,
          SUM(event_count) AS event_count,
          ROUND(SUM(total_positive_delay_minutes), 1) AS total_stop_delay_minutes,
          ROUND(SUM(total_positive_delay_minutes) / COUNT(DISTINCT service_date), 1) AS avg_daily_stop_delay_minutes,
          ROUND(AVG(avg_positive_delay_seconds), 1) AS avg_positive_delay_seconds,
          SUM(delayed_3min_events) AS delayed_3min_events,
          SUM(early_1min_events) AS early_1min_events
        FROM daily_delay_metrics
        JOIN (
          SELECT DISTINCT service_date, weekday_number
          FROM departure_delay_events
        ) USING (service_date)
        GROUP BY weekday_name, line_id
        ORDER BY SUM(total_positive_delay_minutes) {direction}
    """
    return _query(db_path, sql)


def get_delays_by_hour(db_path: str | None = None) -> list[dict[str, Any]]:
    sql = """
        SELECT
          CAST(planned_departure_hour AS INTEGER) AS hour,
          line_id,
          COUNT(*) AS event_count,
          ROUND(SUM(GREATEST(departure_delay_seconds, 0)) / 60.0, 1) AS total_stop_delay_minutes,
          ROUND(AVG(departure_delay_seconds), 1) AS avg_delay_seconds,
          ROUND(MEDIAN(departure_delay_seconds), 1) AS median_delay_seconds,
          SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) AS delayed_3min_events,
          SUM(CASE WHEN departure_delay_seconds < -60 THEN 1 ELSE 0 END) AS early_1min_events
        FROM departure_delay_events
        WHERE planned_departure_hour IS NOT NULL
        GROUP BY planned_departure_hour, line_id
        ORDER BY hour
    """
    return _query(db_path, sql)


def get_worst_stops(db_path: str | None = None, limit: int = 10, service_date: str | None = None) -> list[dict[str, Any]]:
    limit = _limit(limit)
    date_filter = "AND service_date = ?" if service_date else ""
    params: list[Any] = [service_date] if service_date else []
    sql = f"""
        SELECT
          stop_name,
          stop_code,
          stop_point,
          line_id,
          COUNT(*) AS event_count,
          COUNT(DISTINCT service_date) AS service_days,
          ROUND(SUM(GREATEST(departure_delay_seconds, 0)) / 60.0, 1) AS total_stop_delay_minutes,
          ROUND(
            SUM(GREATEST(departure_delay_seconds, 0)) / 60.0 / COUNT(DISTINCT service_date),
            1
          ) AS avg_daily_stop_delay_minutes,
          ROUND(AVG(GREATEST(departure_delay_seconds, 0)), 1) AS avg_positive_delay_seconds,
          ROUND(MEDIAN(departure_delay_seconds), 1) AS median_delay_seconds,
          SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) AS delayed_3min_events,
          SUM(CASE WHEN departure_delay_seconds < -60 THEN 1 ELSE 0 END) AS early_1min_events
        FROM departure_delay_events
        WHERE stop_name IS NOT NULL
          {date_filter}
        GROUP BY stop_name, stop_code, stop_point, line_id
        ORDER BY total_stop_delay_minutes DESC
        LIMIT ?
    """
    return _query(db_path, sql, [*params, limit])


def get_stop_delay_extremes(
    db_path: str | None = None,
    limit: int = 10,
    order: str = "lowest",
    min_events: int = 1,
) -> list[dict[str, Any]]:
    """Rank stops by average positive delay, for lowest/highest overall delay questions."""
    limit = _limit(limit)
    normalized_order = order.strip().lower()
    if normalized_order not in {"lowest", "highest"}:
        raise ValueError("order must be 'lowest' or 'highest'")
    direction = "ASC" if normalized_order == "lowest" else "DESC"
    min_events = max(1, int(min_events))
    sql = f"""
        SELECT
          stop_name,
          stop_code,
          stop_point,
          line_id,
          COUNT(*) AS event_count,
          COUNT(DISTINCT service_date) AS service_days,
          ROUND(SUM(GREATEST(departure_delay_seconds, 0)) / 60.0, 1) AS total_stop_delay_minutes,
          ROUND(AVG(GREATEST(departure_delay_seconds, 0)), 1) AS avg_positive_delay_seconds,
          ROUND(MEDIAN(GREATEST(departure_delay_seconds, 0)), 1) AS median_positive_delay_seconds,
          SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) AS delayed_3min_events,
          ROUND(100.0 * SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_delayed_3min,
          'avg_positive_delay_seconds' AS ranking_metric
        FROM departure_delay_events
        WHERE stop_name IS NOT NULL
        GROUP BY stop_name, stop_code, stop_point, line_id
        HAVING COUNT(*) >= ?
        ORDER BY avg_positive_delay_seconds {direction}, pct_delayed_3min {direction}, total_stop_delay_minutes {direction}, event_count DESC
        LIMIT ?
    """
    return _query(db_path, sql, [min_events, limit])


def get_stop_delays_for_line(
    db_path: str | None = None,
    line_id: str = "",
    limit: int = 10,
    min_events: int = 1,
) -> list[dict[str, Any]]:
    """Rank stops by average positive delay for a specific line."""
    limit = _limit(limit)
    min_events = max(1, int(min_events))
    sql = """
        SELECT
          stop_name,
          stop_code,
          stop_point,
          line_id,
          COUNT(*) AS event_count,
          COUNT(DISTINCT service_date) AS service_days,
          ROUND(SUM(GREATEST(departure_delay_seconds, 0)) / 60.0, 1) AS total_stop_delay_minutes,
          ROUND(AVG(GREATEST(departure_delay_seconds, 0)), 1) AS avg_positive_delay_seconds,
          SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) AS delayed_3min_events,
          ROUND(100.0 * SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_delayed_3min
        FROM departure_delay_events
        WHERE stop_name IS NOT NULL AND line_id = ?
        GROUP BY stop_name, stop_code, stop_point, line_id
        HAVING COUNT(*) >= ?
        ORDER BY avg_positive_delay_seconds DESC, total_stop_delay_minutes DESC
        LIMIT ?
    """
    return _query(db_path, sql, [line_id, min_events, limit])


def get_early_departures(db_path: str | None = None, limit: int = 10) -> list[dict[str, Any]]:
    limit = _limit(limit)
    sql = """
        SELECT
          stop_name,
          stop_code,
          stop_point,
          line_id,
          COUNT(*) AS event_count,
          SUM(CASE WHEN departure_delay_seconds < -60 THEN 1 ELSE 0 END) AS early_1min_events,
          ROUND(AVG(CASE WHEN departure_delay_seconds < 0 THEN -departure_delay_seconds END), 1) AS avg_early_seconds,
          ROUND(MAX(CASE WHEN departure_delay_seconds < 0 THEN -departure_delay_seconds END), 1) AS max_early_seconds
        FROM departure_delay_events
        WHERE stop_name IS NOT NULL
        GROUP BY stop_name, stop_code, stop_point, line_id
        HAVING early_1min_events > 0
        ORDER BY early_1min_events DESC, avg_early_seconds DESC
        LIMIT ?
    """
    return _query(db_path, sql, [limit])


def get_bottleneck_stops(db_path: str | None = None, limit: int = 10) -> list[dict[str, Any]]:
    limit = _limit(limit)
    sql = """
        WITH sequenced AS (
          SELECT
            service_date,
            line_id,
            direction_id,
            run_id,
            stop_name,
            stop_code,
            stop_point,
            planned_departure,
            departure_delay_seconds,
            departure_delay_seconds - LAG(departure_delay_seconds) OVER (
              PARTITION BY service_date, line_id, direction_id, run_id
              ORDER BY planned_departure
            ) AS delay_growth_seconds
          FROM departure_delay_events
          WHERE stop_name IS NOT NULL
        )
        SELECT
          stop_name,
          stop_code,
          stop_point,
          line_id,
          COUNT(*) AS event_count,
          ROUND(AVG(delay_growth_seconds), 1) AS avg_delay_growth_seconds,
          ROUND(SUM(GREATEST(delay_growth_seconds, 0)) / 60.0, 1) AS total_positive_delay_growth_minutes,
          SUM(CASE WHEN delay_growth_seconds >= 60 THEN 1 ELSE 0 END) AS growth_1min_events
        FROM sequenced
        WHERE delay_growth_seconds IS NOT NULL
        GROUP BY stop_name, stop_code, stop_point, line_id
        HAVING growth_1min_events > 0
        ORDER BY avg_delay_growth_seconds DESC, total_positive_delay_growth_minutes DESC
        LIMIT ?
    """
    return _query(db_path, sql, [limit])




def compare_directions(db_path: str | None = None) -> list[dict[str, Any]]:
    sql = """
        SELECT
          line_id,
          direction_id,
          route_start,
          route_start_code,
          route_end,
          route_end_code,
          COUNT(*) AS event_count,
          ROUND(SUM(GREATEST(departure_delay_seconds, 0)) / 60.0, 1) AS total_stop_delay_minutes,
          ROUND(AVG(GREATEST(departure_delay_seconds, 0)), 1) AS avg_positive_delay_seconds,
          ROUND(MEDIAN(departure_delay_seconds), 1) AS median_delay_seconds,
          SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) AS delayed_3min_events,
          SUM(CASE WHEN departure_delay_seconds < -60 THEN 1 ELSE 0 END) AS early_1min_events
        FROM departure_delay_events
        GROUP BY line_id, direction_id, route_start, route_start_code, route_end, route_end_code
        ORDER BY total_stop_delay_minutes DESC
    """
    return _query(db_path, sql)


def get_trip_delay_summary(db_path: str | None = None, service_date: str = "2024-12-12") -> dict[str, Any]:
    """Return user-facing trip-level delay metrics for one service day.

    Stop-level delay minutes count every delayed stop. Trip-level delay minutes
    count each route departure once, using the largest delay that trip reached.
    """
    sql = """
        WITH trip_starts AS (
          SELECT
            service_date,
            line_id,
            direction_id,
            run_id,
            route_start,
            route_start_code,
            route_end,
            route_end_code,
            planned_departure AS trip_start_time,
            LEAD(planned_departure) OVER (
              PARTITION BY service_date, line_id, direction_id, run_id, route_start, route_end
              ORDER BY planned_departure
            ) AS next_trip_start_time
          FROM departure_delay_events
          WHERE service_date = ?
            AND (stop_name = route_start OR stop_code = route_start_code)
        ),
        trip_events AS (
          SELECT
            t.*,
            e.planned_departure,
            e.departure_delay_seconds
          FROM trip_starts t
          JOIN departure_delay_events e
            ON e.service_date = t.service_date
           AND e.line_id = t.line_id
           AND e.direction_id = t.direction_id
           AND e.run_id = t.run_id
           AND e.route_start = t.route_start
           AND e.route_end = t.route_end
           AND e.planned_departure >= t.trip_start_time
           AND (t.next_trip_start_time IS NULL OR e.planned_departure < t.next_trip_start_time)
        ),
        trip_metrics AS (
          SELECT
            service_date,
            line_id,
            direction_id,
            run_id,
            route_start,
            route_end,
            trip_start_time,
            COUNT(*) AS stop_events,
            MAX(GREATEST(departure_delay_seconds, 0)) AS max_positive_delay_seconds,
            SUM(GREATEST(departure_delay_seconds, 0)) AS stop_delay_seconds
          FROM trip_events
          GROUP BY service_date, line_id, direction_id, run_id, route_start, route_end, trip_start_time
        )
        SELECT
          service_date,
          COUNT(*) AS approx_trips,
          ROUND(SUM(max_positive_delay_seconds) / 60.0, 1) AS total_trip_delay_minutes,
          ROUND(SUM(max_positive_delay_seconds) / 3600.0, 2) AS total_trip_delay_hours,
          ROUND(AVG(max_positive_delay_seconds) / 60.0, 1) AS avg_max_delay_per_trip_minutes,
          ROUND(MEDIAN(max_positive_delay_seconds) / 60.0, 1) AS median_max_delay_per_trip_minutes,
          ROUND(MAX(max_positive_delay_seconds) / 60.0, 1) AS worst_trip_delay_minutes,
          SUM(CASE WHEN max_positive_delay_seconds >= 180 THEN 1 ELSE 0 END) AS trips_delayed_3min,
          SUM(CASE WHEN max_positive_delay_seconds >= 300 THEN 1 ELSE 0 END) AS trips_delayed_5min,
          ROUND(SUM(stop_delay_seconds) / 60.0, 1) AS total_stop_delay_minutes,
          ROUND(SUM(stop_delay_seconds) / 3600.0, 2) AS total_stop_delay_hours
        FROM trip_metrics
        GROUP BY service_date
    """
    rows = _query(db_path, sql, [service_date])
    if not rows:
        return {"service_date": service_date, "approx_trips": 0, "plain_language_summary": "No trips found for this date."}

    summary = rows[0]
    summary["plain_language_summary"] = (
        f"On {summary['service_date']}, Line 1 had about {summary['approx_trips']} trips. "
        f"Those trips accumulated about {summary['total_trip_delay_minutes']} minutes "
        f"({summary['total_trip_delay_hours']} hours) of trip-level delay. "
        f"A typical trip reached about {summary['avg_max_delay_per_trip_minutes']} minutes of maximum delay, "
        f"and {summary['trips_delayed_3min']} trips were delayed by at least 3 minutes somewhere on the route."
    )
    summary["metric_explanation"] = (
        "Trip-level delay counts each route departure once, using the largest positive delay it reached. "
        "Stop-level delay counts delay at every stop and is useful for system burden, but is harder for people to interpret."
    )
    return summary


def get_corridor_pain_points(db_path: str | None = None, limit: int = 10) -> list[dict[str, Any]]:
    """Rank directional route corridors by recurring delay pain."""
    limit = _limit(limit)
    sql = """
        SELECT
          direction_id,
          route_start,
          route_end,
          COUNT(*) AS event_count,
          COUNT(DISTINCT service_date) AS service_days,
          ROUND(SUM(GREATEST(departure_delay_seconds, 0)) / 60.0, 1) AS total_stop_delay_minutes,
          ROUND(AVG(GREATEST(departure_delay_seconds, 0)), 1) AS avg_positive_delay_seconds,
          SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) AS delayed_3min_events,
          ROUND(100.0 * SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_delayed_3min
        FROM departure_delay_events
        WHERE route_start IS NOT NULL AND route_end IS NOT NULL
        GROUP BY direction_id, route_start, route_end
        ORDER BY total_stop_delay_minutes DESC
        LIMIT ?
    """
    rows = _query(db_path, sql, [limit])
    for row in rows:
        params = [row["direction_id"], row["route_start"], row["route_end"]]
        worst_hour = _query(
            db_path,
            """
            SELECT
              CAST(planned_departure_hour AS INTEGER) AS hour,
              ROUND(SUM(GREATEST(departure_delay_seconds, 0)) / 60.0, 1) AS total_stop_delay_minutes,
              SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) AS delayed_3min_events
            FROM departure_delay_events
            WHERE direction_id = ? AND route_start = ? AND route_end = ?
              AND planned_departure_hour IS NOT NULL
            GROUP BY planned_departure_hour
            ORDER BY total_stop_delay_minutes DESC
            LIMIT 1
            """,
            params,
        )
        worst_day = _query(
            db_path,
            """
            SELECT
              service_date,
              weekday_name,
              ROUND(SUM(GREATEST(departure_delay_seconds, 0)) / 60.0, 1) AS total_stop_delay_minutes,
              SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) AS delayed_3min_events
            FROM departure_delay_events
            WHERE direction_id = ? AND route_start = ? AND route_end = ?
            GROUP BY service_date, weekday_name
            ORDER BY total_stop_delay_minutes DESC
            LIMIT 1
            """,
            params,
        )
        row["worst_hour"] = worst_hour[0] if worst_hour else None
        row["worst_day"] = worst_day[0] if worst_day else None
    return rows


def get_segment_delay_growth_hotspots(
    db_path: str | None = None,
    limit: int = 10,
    min_growth_1min_events: int = 100,
) -> list[dict[str, Any]]:
    """Find route segments where buses repeatedly gain delay inside a trip."""
    limit = _limit(limit)
    min_growth_1min_events = max(1, int(min_growth_1min_events))
    sql = """
        WITH trip_starts AS (
          SELECT
            service_date,
            line_id,
            direction_id,
            run_id,
            route_start,
            route_start_code,
            route_end,
            route_end_code,
            planned_departure AS trip_start_time,
            LEAD(planned_departure) OVER (
              PARTITION BY service_date, line_id, direction_id, run_id, route_start, route_end
              ORDER BY planned_departure
            ) AS next_trip_start_time
          FROM departure_delay_events
          WHERE stop_name = route_start OR stop_code = route_start_code
        ),
        trip_events AS (
          SELECT
            t.service_date,
            t.line_id,
            t.direction_id,
            t.run_id,
            t.route_start,
            t.route_end,
            t.trip_start_time,
            e.stop_name,
            e.stop_code,
            e.planned_departure,
            e.departure_delay_seconds
          FROM trip_starts t
          JOIN departure_delay_events e
            ON e.service_date = t.service_date
           AND e.line_id = t.line_id
           AND e.direction_id = t.direction_id
           AND e.run_id = t.run_id
           AND e.route_start = t.route_start
           AND e.route_end = t.route_end
           AND e.planned_departure >= t.trip_start_time
           AND (t.next_trip_start_time IS NULL OR e.planned_departure < t.next_trip_start_time)
        ),
        sequenced AS (
          SELECT
            *,
            LAG(stop_name) OVER trip_window AS previous_stop,
            LAG(stop_code) OVER trip_window AS previous_stop_code,
            departure_delay_seconds - LAG(departure_delay_seconds) OVER trip_window AS delay_growth_seconds
          FROM trip_events
          WINDOW trip_window AS (
            PARTITION BY service_date, line_id, direction_id, run_id, route_start, route_end, trip_start_time
            ORDER BY planned_departure
          )
        )
        SELECT
          route_start,
          route_end,
          COALESCE(previous_stop_code, previous_stop) AS previous_stop,
          previous_stop AS previous_stop_abbrev,
          COALESCE(stop_code, stop_name) AS current_stop,
          stop_name AS current_stop_abbrev,
          COUNT(*) AS segment_events,
          ROUND(AVG(delay_growth_seconds), 1) AS avg_growth_seconds,
          ROUND(SUM(GREATEST(delay_growth_seconds, 0)) / 60.0, 1) AS total_positive_growth_minutes,
          SUM(CASE WHEN delay_growth_seconds >= 60 THEN 1 ELSE 0 END) AS growth_1min_events
        FROM sequenced
        WHERE delay_growth_seconds IS NOT NULL
          AND previous_stop IS NOT NULL
          AND stop_name IS NOT NULL
        GROUP BY route_start, route_end, previous_stop, previous_stop_code, stop_name, stop_code
        HAVING growth_1min_events >= ?
        ORDER BY total_positive_growth_minutes DESC, avg_growth_seconds DESC
        LIMIT ?
    """
    return _query(db_path, sql, [min_growth_1min_events, limit])


def get_stop_delay_exposure_filtered(
    db_path: str | None = None,
    limit: int = 10,
    hour_from: int | None = None,
    hour_to: int | None = None,
    weekday_only: bool | None = None,
) -> list[dict[str, Any]]:
    """Rank stop-level passenger delay exposure with explicit time filters."""
    limit = _limit(limit)
    clauses, params = _time_filter_clauses(hour_from, hour_to, weekday_only)
    clauses.append("stop_name IS NOT NULL")
    sql = f"""
        SELECT
          stop_name,
          stop_code,
          stop_point,
          COUNT(*) AS event_count,
          ROUND(SUM(GREATEST(departure_delay_seconds, 0)) / 60.0, 1) AS total_stop_delay_minutes,
          ROUND(AVG(GREATEST(departure_delay_seconds, 0)), 1) AS avg_positive_delay_seconds,
          SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) AS delayed_3min_events,
          ROUND(100.0 * SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_delayed_3min
        FROM departure_delay_events
        WHERE {_where_sql(clauses)}
        GROUP BY stop_name, stop_code, stop_point
        ORDER BY total_stop_delay_minutes DESC, pct_delayed_3min DESC
        LIMIT ?
    """
    return _query(db_path, sql, [*params, limit])


def get_corridor_pain_points_filtered(
    db_path: str | None = None,
    limit: int = 10,
    weekday_only: bool | None = None,
    hour_from: int | None = None,
    hour_to: int | None = None,
    min_service_days: int = 1,
) -> list[dict[str, Any]]:
    """Rank corridor pain points with explicit time filters."""
    limit = _limit(limit)
    min_service_days = max(1, int(min_service_days))
    clauses, params = _time_filter_clauses(hour_from, hour_to, weekday_only)
    clauses.extend(["route_start IS NOT NULL", "route_end IS NOT NULL"])
    where_sql = _where_sql(clauses)
    sql = f"""
        SELECT
          direction_id,
          route_start,
          route_end,
          COUNT(*) AS event_count,
          COUNT(DISTINCT service_date) AS service_days,
          ROUND(SUM(GREATEST(departure_delay_seconds, 0)) / 60.0, 1) AS total_stop_delay_minutes,
          ROUND(SUM(GREATEST(departure_delay_seconds, 0)) / 60.0 / COUNT(DISTINCT service_date), 1) AS avg_daily_stop_delay_minutes,
          ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT service_date), 1) AS avg_daily_stop_events,
          ROUND(AVG(GREATEST(departure_delay_seconds, 0)), 1) AS avg_positive_delay_seconds,
          SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) AS delayed_3min_events,
          ROUND(100.0 * SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_delayed_3min
        FROM departure_delay_events
        WHERE {where_sql}
        GROUP BY direction_id, route_start, route_end
        HAVING COUNT(DISTINCT service_date) >= ?
        ORDER BY avg_daily_stop_delay_minutes DESC, pct_delayed_3min DESC
        LIMIT ?
    """
    rows = _query(db_path, sql, [*params, min_service_days, limit])
    for row in rows:
        row_params = [*params, row["direction_id"], row["route_start"], row["route_end"]]
        row_clauses = [*clauses, "direction_id = ?", "route_start = ?", "route_end = ?"]
        row_where_sql = _where_sql(row_clauses)
        worst_hour = _query(
            db_path,
            f"""
            SELECT
              CAST(planned_departure_hour AS INTEGER) AS hour,
              ROUND(SUM(GREATEST(departure_delay_seconds, 0)) / 60.0, 1) AS total_stop_delay_minutes,
              SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) AS delayed_3min_events
            FROM departure_delay_events
            WHERE {row_where_sql}
              AND planned_departure_hour IS NOT NULL
            GROUP BY planned_departure_hour
            ORDER BY total_stop_delay_minutes DESC
            LIMIT 1
            """,
            row_params,
        )
        worst_day = _query(
            db_path,
            f"""
            SELECT
              service_date,
              weekday_name,
              ROUND(SUM(GREATEST(departure_delay_seconds, 0)) / 60.0, 1) AS total_stop_delay_minutes,
              SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) AS delayed_3min_events
            FROM departure_delay_events
            WHERE {row_where_sql}
            GROUP BY service_date, weekday_name
            ORDER BY total_stop_delay_minutes DESC
            LIMIT 1
            """,
            row_params,
        )
        row["worst_hour"] = worst_hour[0] if worst_hour else None
        row["worst_day"] = worst_day[0] if worst_day else None
    return rows


def get_segment_delay_growth_hotspots_filtered(
    db_path: str | None = None,
    limit: int = 10,
    min_growth_1min_events: int = 10,
    hour_from: int | None = None,
    hour_to: int | None = None,
    toward_city_center: bool = False,
) -> list[dict[str, Any]]:
    """Find trip-safe delay-growth segments with explicit demo filters."""
    limit = _limit(limit)
    min_growth_1min_events = max(1, int(min_growth_1min_events))
    clauses, params = _time_filter_clauses(hour_from, hour_to, table_alias="e")
    event_filter = _where_sql(clauses)
    city_filter = ""
    if toward_city_center:
        city_filter = (
            "AND REGEXP_MATCHES("
            "LOWER(CONCAT_WS(' ', route_end, previous_stop, stop_name, previous_stop_code, stop_code)), ?"
            ")"
        )
    sql = f"""
        WITH trip_starts AS (
          SELECT
            service_date,
            line_id,
            direction_id,
            run_id,
            route_start,
            route_start_code,
            route_end,
            route_end_code,
            planned_departure AS trip_start_time,
            LEAD(planned_departure) OVER (
              PARTITION BY service_date, line_id, direction_id, run_id, route_start, route_end
              ORDER BY planned_departure
            ) AS next_trip_start_time
          FROM departure_delay_events
          WHERE stop_name = route_start OR stop_code = route_start_code
        ),
        trip_events AS (
          SELECT
            t.service_date,
            t.line_id,
            t.direction_id,
            t.run_id,
            t.route_start,
            t.route_end,
            t.trip_start_time,
            e.stop_name,
            e.stop_code,
            e.planned_departure,
            e.departure_delay_seconds
          FROM trip_starts t
          JOIN departure_delay_events e
            ON e.service_date = t.service_date
           AND e.line_id = t.line_id
           AND e.direction_id = t.direction_id
           AND e.run_id = t.run_id
           AND e.route_start = t.route_start
           AND e.route_end = t.route_end
           AND e.planned_departure >= t.trip_start_time
           AND (t.next_trip_start_time IS NULL OR e.planned_departure < t.next_trip_start_time)
          WHERE {event_filter}
        ),
        sequenced AS (
          SELECT
            *,
            LAG(stop_name) OVER trip_window AS previous_stop,
            LAG(stop_code) OVER trip_window AS previous_stop_code,
            departure_delay_seconds - LAG(departure_delay_seconds) OVER trip_window AS delay_growth_seconds
          FROM trip_events
          WINDOW trip_window AS (
            PARTITION BY service_date, line_id, direction_id, run_id, route_start, route_end, trip_start_time
            ORDER BY planned_departure
          )
        )
        SELECT
          route_start,
          route_end,
          COALESCE(previous_stop_code, previous_stop) AS previous_stop,
          previous_stop AS previous_stop_abbrev,
          COALESCE(stop_code, stop_name) AS current_stop,
          stop_name AS current_stop_abbrev,
          COUNT(*) AS segment_events,
          ROUND(AVG(delay_growth_seconds), 1) AS avg_growth_seconds,
          ROUND(SUM(GREATEST(delay_growth_seconds, 0)) / 60.0, 1) AS total_positive_growth_minutes,
          SUM(CASE WHEN delay_growth_seconds >= 60 THEN 1 ELSE 0 END) AS growth_1min_events
        FROM sequenced
        WHERE delay_growth_seconds IS NOT NULL
          AND previous_stop IS NOT NULL
          AND stop_name IS NOT NULL
          {city_filter}
        GROUP BY route_start, route_end, previous_stop, previous_stop_code, stop_name, stop_code
        HAVING growth_1min_events >= ?
        ORDER BY total_positive_growth_minutes DESC, avg_growth_seconds DESC
        LIMIT ?
    """
    query_params = [*params]
    if toward_city_center:
        query_params.append("|".join(_CITY_CENTER_STOP_KEYWORDS))
    query_params.extend([min_growth_1min_events, limit])
    return _query(db_path, sql, query_params)


def explain_pain_points_for_day(db_path: str | None = None, service_date: str = "2024-12-12") -> dict[str, Any]:
    """Return a compact, demo-ready explanation of one day's main reliability pain points."""
    trip_summary = get_trip_delay_summary(db_path, service_date=service_date)
    corridors = _query(
        db_path,
        """
        SELECT
          service_date,
          weekday_name,
          direction_id,
          route_start,
          route_end,
          COUNT(*) AS event_count,
          ROUND(SUM(GREATEST(departure_delay_seconds, 0)) / 60.0, 1) AS total_stop_delay_minutes,
          SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) AS delayed_3min_events,
          ROUND(AVG(GREATEST(departure_delay_seconds, 0)), 1) AS avg_positive_delay_seconds
        FROM departure_delay_events
        WHERE service_date = ?
        GROUP BY service_date, weekday_name, direction_id, route_start, route_end
        ORDER BY total_stop_delay_minutes DESC
        LIMIT 1
        """,
        [service_date],
    )
    hours = _query(
        db_path,
        """
        SELECT
          CAST(planned_departure_hour AS INTEGER) AS hour,
          COUNT(*) AS event_count,
          ROUND(SUM(GREATEST(departure_delay_seconds, 0)) / 60.0, 1) AS total_stop_delay_minutes,
          SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) AS delayed_3min_events,
          ROUND(AVG(GREATEST(departure_delay_seconds, 0)), 1) AS avg_positive_delay_seconds
        FROM departure_delay_events
        WHERE service_date = ? AND planned_departure_hour IS NOT NULL
        GROUP BY planned_departure_hour
        ORDER BY total_stop_delay_minutes DESC
        LIMIT 1
        """,
        [service_date],
    )
    stops = _query(
        db_path,
        """
        SELECT
          COALESCE(stop_code, stop_name) AS stop_name,
          stop_name AS stop_abbrev,
          stop_point,
          direction_id,
          route_start,
          route_end,
          COUNT(*) AS event_count,
          ROUND(SUM(GREATEST(departure_delay_seconds, 0)) / 60.0, 1) AS total_stop_delay_minutes,
          SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) AS delayed_3min_events,
          ROUND(AVG(GREATEST(departure_delay_seconds, 0)), 1) AS avg_positive_delay_seconds
        FROM departure_delay_events
        WHERE service_date = ? AND stop_name IS NOT NULL
        GROUP BY stop_name, stop_code, stop_point, direction_id, route_start, route_end
        ORDER BY total_stop_delay_minutes DESC
        LIMIT 5
        """,
        [service_date],
    )

    worst_corridor = corridors[0] if corridors else None
    worst_hour = hours[0] if hours else None
    if not worst_corridor:
        return {
            "service_date": service_date,
            "trip_summary": trip_summary,
            "plain_language_summary": "No pain points found for this date.",
        }

    stop_names = ", ".join(stop["stop_name"] for stop in stops[:3])
    summary = (
        f"On {worst_corridor['service_date']}, the biggest reliability pain was "
        f"{worst_corridor['route_start']} → {worst_corridor['route_end']}"
    )
    if worst_hour:
        summary += f" around {worst_hour['hour']}:00"
    if stop_names:
        summary += f", especially near {stop_names}"
    summary += "."

    return {
        "service_date": worst_corridor["service_date"],
        "trip_summary": trip_summary,
        "worst_corridor": worst_corridor,
        "worst_hour": worst_hour,
        "worst_stops": stops,
        "plain_language_summary": summary,
        "metric_explanation": (
            "This combines trip-level delay for human scale with stop, corridor, and hour rollups "
            "to locate where the reliability problem concentrates. It identifies where/when, not the external cause."
        ),
    }


# ---------------------------------------------------------------------------
# Flexible delay ranking
# ---------------------------------------------------------------------------

_VALID_GROUP_BY = {"overall", "stop", "weekday", "hour", "date", "corridor", "direction"}

_DELAY_EVENT_ATTRIBUTES: dict[str, str] = {
    "service_date": "CAST(service_date AS VARCHAR)",
    "weekday_name": "weekday_name",
    "weekday_number": "CAST(weekday_number AS INTEGER)",
    "hour": "CAST(planned_departure_hour AS INTEGER)",
    "planned_departure_hour": "CAST(planned_departure_hour AS INTEGER)",
    "line_id": "CAST(line_id AS VARCHAR)",
    "stop_name": "stop_name",
    "stop_code": "stop_code",
    "stop_point": "stop_point",
    "departure_delay_seconds": "departure_delay_seconds",
    "departure_delay_minutes": "ROUND(departure_delay_seconds / 60.0, 1)",
    "positive_delay_minutes": "ROUND(GREATEST(departure_delay_seconds, 0) / 60.0, 1)",
    "direction_id": "direction_id",
    "run_id": "run_id",
    "planned_departure": "CAST(planned_departure AS VARCHAR)",
    "route_start": "route_start",
    "route_start_code": "route_start_code",
    "route_end": "route_end",
    "route_end_code": "route_end_code",
}

_DELAY_EVENT_FILTERS = {
    "service_date",
    "weekday_name",
    "line_id",
    "stop_name",
    "route_start",
    "route_end",
    "direction_id",
}


def list_delay_event_attributes() -> list[dict[str, Any]]:
    """Return safe attributes the LLM can request from departure_delay_events."""
    descriptions = {
        "service_date": "Operating date of the event.",
        "weekday_name": "Weekday label.",
        "hour": "Planned departure hour, 0-23.",
        "line_id": "Bus line identifier.",
        "stop_name": "Stop where the departure event was observed.",
        "departure_delay_seconds": "Signed delay; positive means late, negative means early.",
        "departure_delay_minutes": "Signed delay in minutes; positive means late, negative means early.",
        "positive_delay_minutes": "Delay burden in minutes; early/on-time events count as 0.",
        "direction_id": "Route direction identifier.",
        "run_id": "Vehicle/trip run identifier inside a service day.",
        "planned_departure": "Planned departure timestamp.",
        "route_start": "Trip/corridor start stop.",
        "route_end": "Trip/corridor end stop.",
    }
    return [
        {"attribute": name, "description": descriptions.get(name, "Raw event attribute.")}
        for name in _DELAY_EVENT_ATTRIBUTES
    ]


def get_delay_attribute_values(
    attribute: str,
    *,
    line_id: str | int | None = None,
    stop_name: str | None = None,
    weekday_name: str | None = None,
    hour_from: int | None = None,
    hour_to: int | None = None,
    limit: int = 50,
    db_path: str | None = None,
) -> list[dict[str, Any]]:
    """Return distinct values for one safe delay-event attribute with optional filters."""
    if attribute not in _DELAY_EVENT_ATTRIBUTES:
        raise ValueError(f"attribute must be one of {sorted(_DELAY_EVENT_ATTRIBUTES)}")
    _validate_hour(hour_from, "hour_from")
    _validate_hour(hour_to, "hour_to")
    conditions: list[str] = []
    params: list[Any] = []
    if line_id is not None:
        conditions.append("CAST(line_id AS VARCHAR) = ?")
        params.append(str(line_id))
    if stop_name:
        conditions.append("stop_name = ?")
        params.append(stop_name)
    if weekday_name:
        conditions.append("weekday_name = ?")
        params.append(weekday_name)
    if hour_from is not None:
        conditions.append("planned_departure_hour >= ?")
        params.append(int(hour_from))
    if hour_to is not None:
        conditions.append("planned_departure_hour <= ?")
        params.append(int(hour_to))
    where = "WHERE " + " AND ".join(conditions) if conditions else ""
    expr = _DELAY_EVENT_ATTRIBUTES[attribute]
    sql = f"""
        SELECT {expr} AS value, COUNT(*) AS event_count
        FROM departure_delay_events
        {where}
        GROUP BY value
        ORDER BY event_count DESC, value
        LIMIT ?
    """
    params.append(_limit(limit, maximum=100))
    return _query(db_path, sql, params)


def get_delay_event_records(
    attributes: list[str] | None = None,
    *,
    filters: dict[str, Any] | None = None,
    hour_from: int | None = None,
    hour_to: int | None = None,
    order_by: str = "positive_delay_minutes",
    order: str = "highest",
    limit: int = 25,
    db_path: str | None = None,
) -> list[dict[str, Any]]:
    """Return raw-ish delay events for selected safe attributes and filters."""
    requested = attributes or [
        "service_date",
        "line_id",
        "stop_name",
        "hour",
        "departure_delay_minutes",
        "route_start",
        "route_end",
    ]
    invalid = [attribute for attribute in requested if attribute not in _DELAY_EVENT_ATTRIBUTES]
    if invalid:
        raise ValueError(f"Unsupported attributes: {invalid}")
    if order_by not in _DELAY_EVENT_ATTRIBUTES:
        raise ValueError(f"order_by must be one of {sorted(_DELAY_EVENT_ATTRIBUTES)}")
    if order not in {"highest", "lowest"}:
        raise ValueError("order must be highest or lowest")
    _validate_hour(hour_from, "hour_from")
    _validate_hour(hour_to, "hour_to")

    conditions: list[str] = []
    params: list[Any] = []
    for key, value in (filters or {}).items():
        if value is None or value == "":
            continue
        if key not in _DELAY_EVENT_FILTERS:
            raise ValueError(f"Unsupported filter: {key}")
        if key == "line_id":
            conditions.append("CAST(line_id AS VARCHAR) = ?")
            params.append(str(value))
        else:
            conditions.append(f"{key} = ?")
            params.append(value)
    if hour_from is not None:
        conditions.append("planned_departure_hour >= ?")
        params.append(int(hour_from))
    if hour_to is not None:
        conditions.append("planned_departure_hour <= ?")
        params.append(int(hour_to))

    where = "WHERE " + " AND ".join(conditions) if conditions else ""
    select = ", ".join(f"{_DELAY_EVENT_ATTRIBUTES[attribute]} AS {attribute}" for attribute in requested)
    order_sql = "DESC" if order == "highest" else "ASC"
    sql = f"""
        SELECT {select}
        FROM departure_delay_events
        {where}
        ORDER BY {_DELAY_EVENT_ATTRIBUTES[order_by]} {order_sql}
        LIMIT ?
    """
    params.append(_limit(limit, maximum=100))
    return _query(db_path, sql, params)


def get_delay_ranking(
    *,
    group_by: str = "stop",
    line_id: str | int | None = None,
    date_from: str | None = None,
    date_to: str | None = None,
    weekday_only: bool | None = None,
    hour_from: int | None = None,
    hour_to: int | None = None,
    stop_name: str | None = None,
    direction: str | None = None,
    order: str = "highest",
    limit: int = 10,
    db_path: str | None = None,
) -> list[dict[str, Any]]:
    """Flexible delay ranking with filters.

    group_by: what to rank — overall | stop | weekday | hour | date | corridor | direction
    Filters narrow the dataset before aggregation.
    """
    if group_by not in _VALID_GROUP_BY:
        raise ValueError(f"group_by must be one of {_VALID_GROUP_BY}")

    # -- SELECT / GROUP BY clause per group_by --------------------------------
    if group_by == "overall":
        select = "'overall' AS scope"
        group = "scope"
    elif group_by == "stop":
        select = "stop_name"
        group = "stop_name"
    elif group_by == "weekday":
        select = "weekday_name, CAST(MIN(weekday_number) AS INTEGER) AS weekday_number"
        group = "weekday_name"
    elif group_by == "hour":
        select = "CAST(planned_departure_hour AS INTEGER) AS hour"
        group = "planned_departure_hour"
    elif group_by == "date":
        select = "CAST(service_date AS VARCHAR) AS service_date, MIN(weekday_name) AS weekday_name"
        group = "service_date"
    elif group_by == "corridor":
        select = "route_start, route_end, direction_id"
        group = "route_start, route_end, direction_id"
    elif group_by == "direction":
        select = "direction_id, MIN(route_start) AS route_start, MIN(route_end) AS route_end"
        group = "direction_id"

    direction_sql = "ASC" if order == "lowest" else "DESC"

    # -- WHERE filters --------------------------------------------------------
    conditions: list[str] = []
    params: list[Any] = []

    if line_id is not None:
        conditions.append("CAST(line_id AS VARCHAR) = ?")
        params.append(str(line_id))
    if date_from is not None:
        conditions.append("service_date >= CAST(? AS DATE)")
        params.append(date_from)
    if date_to is not None:
        conditions.append("service_date <= CAST(? AS DATE)")
        params.append(date_to)
    if weekday_only is True:
        conditions.append("CAST(weekday_number AS INTEGER) BETWEEN 0 AND 4")
    if hour_from is not None:
        conditions.append("planned_departure_hour >= ?")
        params.append(hour_from)
    if hour_to is not None:
        conditions.append("planned_departure_hour <= ?")
        params.append(hour_to)
    if stop_name is not None:
        conditions.append("stop_name = ?")
        params.append(stop_name)
    if direction is not None:
        conditions.append("(route_start = ? OR route_end = ?)")
        params.append(direction)
        params.append(direction)

    where = ("WHERE " + " AND ".join(conditions)) if conditions else ""
    params.append(max(1, min(limit, 50)))

    sql = f"""
        SELECT
          {select},
          COUNT(*) AS event_count,
          COUNT(DISTINCT service_date) AS service_days,
          ROUND(SUM(GREATEST(departure_delay_seconds, 0)) / 60.0, 1) AS total_stop_delay_minutes,
          ROUND(AVG(CASE WHEN departure_delay_seconds > 0 THEN departure_delay_seconds END), 1) AS avg_positive_delay_seconds,
          SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) AS delayed_3min_events,
          ROUND(100.0 * SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 1) AS pct_delayed_3min,
          SUM(CASE WHEN departure_delay_seconds < -60 THEN 1 ELSE 0 END) AS early_1min_events
        FROM departure_delay_events
        {where}
        GROUP BY {group}
        ORDER BY total_stop_delay_minutes {direction_sql}
        LIMIT ?
    """
    return _query(db_path, sql, params)
