from __future__ import annotations

import os
from pathlib import Path

import duckdb


DEFAULT_DB_PATH = Path(__file__).resolve().parents[1] / "data" / "processed" / "transport.duckdb"


def resolve_db_path(db_path: str | os.PathLike[str] | None = None) -> Path:
    if db_path is not None:
        return Path(db_path).expanduser().resolve()
    env_path = os.environ.get("TRANSPORT_DB_PATH")
    if env_path:
        return Path(env_path).expanduser().resolve()
    return DEFAULT_DB_PATH


def connect(db_path: str | os.PathLike[str] | None = None, *, read_only: bool = True) -> duckdb.DuckDBPyConnection:
    path = resolve_db_path(db_path)
    return duckdb.connect(str(path), read_only=read_only)
