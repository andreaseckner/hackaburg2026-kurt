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

    limited_sql = f"SELECT * FROM ({normalized}) AS readonly_query LIMIT ?"
    return _query(db_path, limited_sql, [limit])


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
        SELECT
          service_date,
          weekday_name,
          line_id,
          event_count,
          ROUND(total_positive_delay_minutes, 1) AS total_delay_minutes,
          ROUND(avg_positive_delay_seconds, 1) AS avg_positive_delay_seconds,
          delayed_3min_events,
          early_1min_events
        FROM daily_delay_metrics
        ORDER BY total_positive_delay_minutes DESC
        LIMIT ?
    """
    return _query(db_path, sql, [limit])


def get_delays_by_weekday(db_path: str | None = None) -> list[dict[str, Any]]:
    sql = """
        SELECT
          weekday_name,
          CAST(MIN(weekday_number) AS INTEGER) AS weekday_number,
          line_id,
          COUNT(DISTINCT service_date) AS service_days,
          SUM(event_count) AS event_count,
          ROUND(SUM(total_positive_delay_minutes), 1) AS total_delay_minutes,
          ROUND(AVG(avg_positive_delay_seconds), 1) AS avg_positive_delay_seconds,
          SUM(delayed_3min_events) AS delayed_3min_events,
          SUM(early_1min_events) AS early_1min_events
        FROM daily_delay_metrics
        JOIN (
          SELECT DISTINCT service_date, weekday_number
          FROM departure_delay_events
        ) USING (service_date)
        GROUP BY weekday_name, line_id
        ORDER BY SUM(total_positive_delay_minutes) DESC
    """
    return _query(db_path, sql)


def get_delays_by_hour(db_path: str | None = None) -> list[dict[str, Any]]:
    sql = """
        SELECT
          CAST(planned_departure_hour AS INTEGER) AS hour,
          line_id,
          COUNT(*) AS event_count,
          ROUND(SUM(GREATEST(departure_delay_seconds, 0)) / 60.0, 1) AS total_delay_minutes,
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


def get_worst_stops(db_path: str | None = None, limit: int = 10) -> list[dict[str, Any]]:
    limit = _limit(limit)
    sql = """
        SELECT
          stop_name,
          stop_code,
          stop_point,
          line_id,
          COUNT(*) AS event_count,
          ROUND(SUM(GREATEST(departure_delay_seconds, 0)) / 60.0, 1) AS total_delay_minutes,
          ROUND(AVG(GREATEST(departure_delay_seconds, 0)), 1) AS avg_positive_delay_seconds,
          ROUND(MEDIAN(departure_delay_seconds), 1) AS median_delay_seconds,
          SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) AS delayed_3min_events,
          SUM(CASE WHEN departure_delay_seconds < -60 THEN 1 ELSE 0 END) AS early_1min_events
        FROM departure_delay_events
        WHERE stop_name IS NOT NULL
        GROUP BY stop_name, stop_code, stop_point, line_id
        ORDER BY total_delay_minutes DESC
        LIMIT ?
    """
    return _query(db_path, sql, [limit])


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
          ROUND(SUM(GREATEST(departure_delay_seconds, 0)) / 60.0, 1) AS total_delay_minutes,
          ROUND(AVG(GREATEST(departure_delay_seconds, 0)), 1) AS avg_positive_delay_seconds,
          ROUND(MEDIAN(departure_delay_seconds), 1) AS median_delay_seconds,
          SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) AS delayed_3min_events,
          SUM(CASE WHEN departure_delay_seconds < -60 THEN 1 ELSE 0 END) AS early_1min_events
        FROM departure_delay_events
        GROUP BY line_id, direction_id, route_start, route_start_code, route_end, route_end_code
        ORDER BY total_delay_minutes DESC
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
