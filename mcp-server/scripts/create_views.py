#!/usr/bin/env python3
"""Create first analytics views over imported raw monthly tables."""

from __future__ import annotations

import argparse
from pathlib import Path

import duckdb


def qident(name: str) -> str:
    return '"' + name.replace('"', '""') + '"'


def columns_for(con: duckdb.DuckDBPyConnection, table: str) -> set[str]:
    return {row[0] for row in con.execute(f"DESCRIBE {qident(table)}").fetchall()}


def value_expr(cols: set[str], name: str, default: str = "NULL") -> str:
    return qident(name) if name in cols else default


def select_for_table(con: duckdb.DuckDBPyConnection, table: str) -> str:
    cols = columns_for(con, table)

    if "departure_delay" in cols:
        # Newer raw exports already contain user-facing delay minutes where
        # positive means late. The analytics view stores the legacy schedule
        # deviation sign too, so convert minutes -> seconds and invert here.
        metric_name_expr = "'Fahrplan-Abw. Abfahrt derived'"
        metric_value_expr = "-TRY_CAST(departure_delay AS DOUBLE) * 60.0"
    elif "column22" in cols:
        metric_name_expr = qident("column21")
        metric_value_expr = f"TRY_CAST({qident('column22')} AS DOUBLE)"
    elif "column21" in cols:
        metric_name_expr = qident("column20")
        metric_value_expr = f"TRY_CAST({qident('column21')} AS DOUBLE)"
    elif "column20" in cols:
        metric_name_expr = qident("column19")
        metric_value_expr = f"TRY_CAST({qident('column20')} AS DOUBLE)"
    else:
        raise ValueError(f"Could not find departure delay columns for {table}")

    route_start_code = value_expr(cols, "column10", value_expr(cols, "street_names_start"))
    route_end_code = value_expr(cols, "column12", value_expr(cols, "street_names_end"))
    stop_code = value_expr(cols, "column14", value_expr(cols, "bus_stop_full"))

    return f"""
    SELECT
      '{table}' AS source_table,
      ankunft_haltestelle_tur,
      ankunft_haltestelle_halt,
      ankunft_plan_haltestelle,
      abfahrt_haltestelle_tur,
      abfahrt_haltestelle_halt,
      abfahrt_plan_haltestelle,
      ankunft_produktiv,
      abfahrt_produktiv,
      betriebstag AS service_date,
      fahrtbeginn_sollhaltestelle AS route_start,
      {route_start_code} AS route_start_code,
      fahrtende_sollhaltestelle AS route_end,
      {route_end_code} AS route_end_code,
      {value_expr(cols, 'haltestelle')} AS stop_name,
      {stop_code} AS stop_code,
      {value_expr(cols, 'haltepunkt')} AS stop_point,
      linie AS line_id,
      richtung AS direction_id,
      umlauf AS run_id,
      {metric_name_expr} AS metric_name,
      {metric_value_expr} AS metric_value
    FROM {qident(table)}
    """


def main() -> int:
    parser = argparse.ArgumentParser(description="Create analytics views in the DuckDB database.")
    parser.add_argument("db_path", nargs="?", default="data/processed/transport.duckdb")
    args = parser.parse_args()

    db_path = Path(args.db_path).expanduser().resolve()
    con = duckdb.connect(str(db_path))
    try:
        tables = [
            row[0]
            for row in con.execute(
                "SELECT table_name FROM ingest_files WHERE table_name LIKE 'raw_%' ORDER BY table_name"
            ).fetchall()
        ]
        if not tables:
            raise SystemExit("No raw tables found. Run scripts/ingest_csvs.py first.")

        union_sql = "\nUNION ALL\n".join(select_for_table(con, table) for table in tables)
        con.execute("DROP VIEW IF EXISTS raw_line1_metrics")
        con.execute(f"CREATE VIEW raw_line1_metrics AS {union_sql}")

        con.execute("DROP VIEW IF EXISTS departure_delay_events")
        con.execute(
            """
            CREATE VIEW departure_delay_events AS
            SELECT
              md5(CONCAT_WS('|',
                source_table,
                CAST(service_date AS VARCHAR),
                CAST(line_id AS VARCHAR),
                CAST(direction_id AS VARCHAR),
                CAST(run_id AS VARCHAR),
                COALESCE(route_start, ''),
                COALESCE(route_end, ''),
                COALESCE(stop_name, ''),
                COALESCE(stop_code, ''),
                COALESCE(stop_point, ''),
                CAST(abfahrt_plan_haltestelle AS VARCHAR),
                CAST(abfahrt_haltestelle_tur AS VARCHAR),
                CAST(metric_value AS VARCHAR)
              )) AS departure_event_id,
              source_table,
              service_date,
              strftime(service_date, '%w') AS weekday_number,
              strftime(service_date, '%A') AS weekday_name,
              EXTRACT(hour FROM abfahrt_plan_haltestelle) AS planned_departure_hour,
              route_start,
              route_start_code,
              route_end,
              route_end_code,
              COALESCE(stop_name, stop_point) AS stop_name,
              stop_code,
              stop_point,
              line_id,
              direction_id,
              run_id,
              abfahrt_plan_haltestelle AS planned_departure,
              abfahrt_haltestelle_tur AS actual_departure,
              -metric_value AS departure_delay_seconds,
              metric_value AS schedule_deviation_seconds
            FROM raw_line1_metrics
            WHERE metric_name LIKE 'Fahrplan-Abw. Abfahrt%'
              AND abfahrt_produktiv = 'Ja'
              AND metric_value IS NOT NULL
            """
        )

        con.execute("DROP VIEW IF EXISTS daily_delay_metrics")
        con.execute(
            """
            CREATE VIEW daily_delay_metrics AS
            SELECT
              service_date,
              weekday_name,
              line_id,
              COUNT(*) AS event_count,
              SUM(GREATEST(departure_delay_seconds, 0)) AS total_positive_delay_seconds,
              SUM(GREATEST(departure_delay_seconds, 0)) / 60.0 AS total_positive_delay_minutes,
              AVG(GREATEST(departure_delay_seconds, 0)) AS avg_positive_delay_seconds,
              MEDIAN(departure_delay_seconds) AS median_delay_seconds,
              SUM(CASE WHEN departure_delay_seconds >= 180 THEN 1 ELSE 0 END) AS delayed_3min_events,
              SUM(CASE WHEN departure_delay_seconds < -60 THEN 1 ELSE 0 END) AS early_1min_events
            FROM departure_delay_events
            GROUP BY service_date, weekday_name, line_id
            """
        )

        print(f"created views in {db_path}:")
        print("  raw_line1_metrics")
        print("  departure_delay_events")
        print("  daily_delay_metrics")
        return 0
    finally:
        con.close()


if __name__ == "__main__":
    raise SystemExit(main())
