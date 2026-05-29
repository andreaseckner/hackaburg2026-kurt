from __future__ import annotations

from typing import Any

from fastapi import FastAPI
from pydantic import BaseModel, Field

from core.chat import answer_transport_question
from core.db import resolve_db_path

app = FastAPI(title="Hackaburg Transport Reliability API")


class ChatQueryRequest(BaseModel):
    question: str = Field(..., min_length=1, max_length=500)


@app.get("/health")
def health() -> dict[str, Any]:
    db_path = resolve_db_path()
    return {
        "status": "ok",
        "database_path": str(db_path),
        "database_exists": db_path.exists(),
    }


@app.post("/chat/query")
def chat_query(request: ChatQueryRequest) -> dict[str, Any]:
    return answer_transport_question(request.question)
