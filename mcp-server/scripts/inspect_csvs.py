#!/usr/bin/env python3
"""Inspect CSV files before committing to a schema.

Usage:
    python scripts/inspect_csvs.py data/raw
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

import pandas as pd


CANDIDATE_DELIMITERS = [",", ";", "\t", "|"]
KEYWORD_GROUPS = {
    "date/time": ["date", "datum", "day", "tag", "time", "zeit", "uhr", "arrival", "departure", "ankunft", "abfahrt", "soll", "ist"],
    "line": ["line", "linie", "route", "fahrt", "trip", "kurs"],
    "stop": ["stop", "halt", "haltestelle", "station"],
    "delay": ["delay", "versp", "late", "early", "frueh", "früh", "diff", "abweich"],
    "geo": ["lat", "lon", "lng", "x", "y", "coord", "koordinate"],
}


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


def read_csv_sample(path: Path, delimiter: str, encoding: str, sample_rows: int) -> pd.DataFrame:
    try:
        return pd.read_csv(path, sep=delimiter, nrows=sample_rows, encoding=encoding)
    except UnicodeDecodeError:
        return pd.read_csv(path, sep=delimiter, nrows=sample_rows, encoding="latin1")


def matching_columns(columns: list[str], keywords: list[str]) -> list[str]:
    matches = []
    for column in columns:
        lowered = column.lower()
        if any(keyword in lowered for keyword in keywords):
            matches.append(column)
    return matches


def inspect_file(path: Path, sample_rows: int) -> None:
    encoding = detect_encoding(path)
    delimiter = detect_delimiter(path, encoding)
    print(f"\n## {path.name}")
    print(f"path: {path}")
    print(f"encoding: {encoding}")
    print(f"delimiter: {delimiter!r}")

    df = read_csv_sample(path, delimiter, encoding, sample_rows)

    columns = [str(column) for column in df.columns]
    print(f"columns ({len(columns)}):")
    for column in columns:
        print(f"  - {column}")

    for label, keywords in KEYWORD_GROUPS.items():
        matches = matching_columns(columns, keywords)
        if matches:
            print(f"possible {label} columns: {', '.join(matches)}")

    try:
        rows = 0
        for chunk in pd.read_csv(path, sep=delimiter, chunksize=100_000, encoding=encoding):
            rows += len(chunk)
        print(f"rows: {rows}")
    except Exception as exc:  # noqa: BLE001 - inspection should continue with useful output
        print(f"rows: unknown ({exc})")

    print("sample:")
    if df.empty:
        print("  <empty>")
    else:
        print(df.head(sample_rows).to_string(index=False))


def main() -> int:
    parser = argparse.ArgumentParser(description="Inspect CSV files and print likely transport columns.")
    parser.add_argument("raw_dir", nargs="?", default="data/raw", help="Directory containing CSV files")
    parser.add_argument("--sample-rows", type=int, default=5, help="Sample rows to print per CSV")
    args = parser.parse_args()

    raw_dir = Path(args.raw_dir).expanduser().resolve()
    csv_files = sorted(raw_dir.glob("*.csv"))
    if not csv_files:
        print(f"No CSV files found in {raw_dir}")
        print("Put files into data/raw and rerun this script.")
        return 1

    print(f"Found {len(csv_files)} CSV file(s) in {raw_dir}")
    for path in csv_files:
        inspect_file(path, args.sample_rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
