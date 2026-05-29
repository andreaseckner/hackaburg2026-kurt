# MCP Server

Local stdio MCP server entrypoint:

```bash
cd mcp-server
source .venv/bin/activate
python mcp_server/server.py
```

Hermes config example:

```yaml
mcp_servers:
  hackathon_2026_transport:
    command: "/path/to/repo/mcp-server/.venv/bin/python"
    args: ["/path/to/repo/mcp-server/mcp_server/server.py"]
    env:
      TRANSPORT_DB_PATH: "/path/to/repo/mcp-server/data/processed/transport.duckdb"
    timeout: 120
    connect_timeout: 30
```

Available analytics tools:

- `health_check`
- `get_tables`
- `get_table_schema`
- `get_raw_table_overview`
- `get_top_delay_days`
- `get_delay_by_weekday`
- `get_delay_by_hour`
- `get_delay_hotspot_stops`
- `get_early_departure_hotspots`
- `get_bottleneck_stop_hotspots`
- `compare_route_directions`
- `explain_trip_delay_for_day`
- `query_readonly_sql`

The first proper analytics are based on normalized departure delay semantics:

```text
departure_delay_seconds = -schedule_deviation_seconds
```

So positive delay means late, negative delay means early.

For human-facing answers, prefer trip-level delay metrics from `explain_trip_delay_for_day`:

- `total_trip_delay_minutes` / `total_trip_delay_hours`: each trip counted once, using its maximum delay.
- `avg_max_delay_per_trip_minutes`: typical worst delay reached by a trip.
- `trips_delayed_3min` and `trips_delayed_5min`: easy reliability counts.
- `total_stop_delay_minutes`: every delayed stop counted separately; useful as system burden, but not intuitive for users.

Security note: read-only DuckDB connections disable external access, and the ad-hoc SQL tool accepts only a single SELECT statement with blocked write/DDL keywords.
