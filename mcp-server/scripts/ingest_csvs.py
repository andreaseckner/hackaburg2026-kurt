#!/usr/bin/env python3
"""Ingest raw CSV files into a DuckDB database.

This intentionally creates a raw layer first. We should inspect the real CSV
columns before forcing a normalized transport schema.

Usage:
    python scripts/ingest_csvs.py data/raw data/processed/transport.duckdb
"""

from __future__ import annotations

import argparse
import csv
import re
import tempfile
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

import duckdb


CANDIDATE_DELIMITERS = [",", ";", "\t", "|"]


def detect_encoding(path: Path) -> str:
    first_bytes = path.read_bytes()[:4]
    if first_bytes.startswith(b"\xff\xfe") or first_bytes.startswith(b"\xfe\xff"):
        return "utf-16"
    if first_bytes.startswith(b"\xef\xbb\xbf"):
        return "utf-8-sig"
    return "utf-8-sig"


def detect_delimiter(path: Path, encoding: str) -> str:
    sample = path.read_text(encoding=encoding, errors="replace")[:8192]
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters="".join(CANDIDATE_DELIMITERS))
        return dialect.delimiter
    except csv.Error:
        counts = {delimiter: sample.count(delimiter) for delimiter in CANDIDATE_DELIMITERS}
        return max(counts, key=counts.get)


def table_name_for(path: Path) -> str:
    stem = path.stem.lower()
    stem = re.sub(r"[^a-z0-9]+", "_", stem).strip("_")
    if not stem:
        stem = "csv"
    if stem[0].isdigit():
        stem = f"csv_{stem}"
    return f"raw_{stem}"


def quote_identifier(name: str) -> str:
    return '"' + name.replace('"', '""') + '"'


@contextmanager
def utf8_csv_path(path: Path, encoding: str) -> Iterator[Path]:
    """Yield a UTF-8 CSV path DuckDB can ingest reliably."""
    if encoding.lower().replace("_", "-") in {"utf-8", "utf-8-sig"}:
        yield path
        return

    with tempfile.NamedTemporaryFile("w", encoding="utf-8", newline="", suffix=".csv", delete=False) as tmp:
        tmp_path = Path(tmp.name)
        with path.open("r", encoding=encoding, errors="replace", newline="") as source:
            for line in source:
                tmp.write(line)
    try:
        yield tmp_path
    finally:
        tmp_path.unlink(missing_ok=True)


def ingest_csv(con: duckdb.DuckDBPyConnection, path: Path) -> tuple[str, int, str, str]:
    table_name = table_name_for(path)
    encoding = detect_encoding(path)
    delimiter = detect_delimiter(path, encoding)
    quoted_table = quote_identifier(table_name)
    delim_sql = delimiter.replace("'", "''")

    with utf8_csv_path(path, encoding) as readable_path:
        path_sql = str(readable_path).replace("'", "''")
        con.execute(f"DROP TABLE IF EXISTS {quoted_table}")
        con.execute(
            f"""
            CREATE TABLE {quoted_table} AS
            SELECT *
            FROM read_csv_auto(
                '{path_sql}',
                delim='{delim_sql}',
                header=true,
                sample_size=-1,
                ignore_errors=true,
                normalize_names=true
            )
            """
        )
    row_count = con.execute(f"SELECT COUNT(*) FROM {quoted_table}").fetchone()[0]
    return table_name, int(row_count), encoding, delimiter


def create_metadata_tables(con: duckdb.DuckDBPyConnection, ingested: list[tuple[str, str, int, str, str]]) -> None:
    con.execute("DROP TABLE IF EXISTS ingest_files")
    con.execute(
        """
        CREATE TABLE ingest_files (
            table_name VARCHAR,
            source_path VARCHAR,
            row_count BIGINT,
            encoding VARCHAR,
            delimiter VARCHAR,
            ingested_at TIMESTAMP DEFAULT now()
        )
        """
    )
    con.executemany(
        "INSERT INTO ingest_files(table_name, source_path, row_count, encoding, delimiter) VALUES (?, ?, ?, ?, ?)",
        ingested,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Ingest CSV files into raw DuckDB tables.")
    parser.add_argument("raw_dir", nargs="?", default="data/raw", help="Directory containing CSV files")
    parser.add_argument("db_path", nargs="?", default="data/processed/transport.duckdb", help="Output DuckDB path")
    args = parser.parse_args()

    raw_dir = Path(args.raw_dir).expanduser().resolve()
    db_path = Path(args.db_path).expanduser().resolve()
    db_path.parent.mkdir(parents=True, exist_ok=True)

    csv_files = sorted(raw_dir.glob("*.csv"))
    if not csv_files:
        print(f"No CSV files found in {raw_dir}")
        print("Put files into data/raw and rerun this script.")
        return 1

    con = duckdb.connect(str(db_path))
    try:
        ingested: list[tuple[str, str, int, str, str]] = []
        for path in csv_files:
            table_name, row_count, encoding, delimiter = ingest_csv(con, path)
            ingested.append((table_name, str(path), row_count, encoding, delimiter))
            print(f"ingested {path.name} -> {table_name} ({row_count} rows, {encoding}, delimiter={delimiter!r})")
        create_metadata_tables(con, ingested)
        print(f"database written: {db_path}")
        return 0
    finally:
        con.close()


if __name__ == "__main__":
    raise SystemExit(main())
