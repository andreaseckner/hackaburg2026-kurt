from __future__ import annotations

import os
import time
import uuid
from typing import Any
import logging

from fastapi import FastAPI
from pydantic import BaseModel, Field

from core.chat import answer_transport_question
from core.db import resolve_db_path
from core.llm_chat import answer_transport_question_with_llm

logger = logging.getLogger("uvicorn.error")

app = FastAPI(title="Hackaburg Transport Reliability API")


class ChatQueryRequest(BaseModel):
    question: str = Field(..., min_length=1, max_length=500)
    use_llm: bool = True


@app.get("/health")
def health() -> dict[str, Any]:
    db_path = resolve_db_path()
    return {
        "status": "ok",
        "database_path": str(db_path),
        "database_exists": db_path.exists(),
        "llm_provider": os.environ.get("LLM_PROVIDER", "auto"),
        "llm_available": bool(os.environ.get("GEMINI_API_KEY")),
        "llm_model": os.environ.get("GEMINI_MODEL", "gemini-2.5-flash"),
        "ollama_base_url": os.environ.get("OLLAMA_BASE_URL") or os.environ.get("LOCAL_LLM_BASE_URL") or "http://127.0.0.1:11434",
        "ollama_model": os.environ.get("OLLAMA_MODEL") or os.environ.get("LOCAL_LLM_MODEL"),
    }


@app.post("/chat/query")
def chat_query(request: ChatQueryRequest) -> dict[str, Any]:
    request_id = uuid.uuid4().hex[:8]
    started_at = time.perf_counter()
    db_path = resolve_db_path()

    logger.info(
        "chat/query start request_id=%s use_llm=%s question_len=%s db_path=%s db_exists=%s llm_provider=%s gemini_available=%s gemini_model=%s ollama_model=%s",
        request_id,
        request.use_llm,
        len(request.question),
        db_path,
        db_path.exists(),
        os.environ.get("LLM_PROVIDER", "auto"),
        bool(os.environ.get("GEMINI_API_KEY")),
        os.environ.get("GEMINI_MODEL", "gemini-2.5-flash"),
        os.environ.get("OLLAMA_MODEL") or os.environ.get("LOCAL_LLM_MODEL"),
    )

    try:
        if request.use_llm:
            response = answer_transport_question_with_llm(request.question, db_path=str(db_path))
        else:
            response = answer_transport_question(request.question, db_path=str(db_path))
            response["mode"] = "deterministic"
    except Exception:
        elapsed_ms = int((time.perf_counter() - started_at) * 1000)
        logger.exception("chat/query failed request_id=%s elapsed_ms=%s", request_id, elapsed_ms)
        raise

    elapsed_ms = int((time.perf_counter() - started_at) * 1000)
    logger.info(
        "chat/query complete request_id=%s elapsed_ms=%s mode=%s intent=%s metric_source=%s rows=%s unsupported_reason=%s",
        request_id,
        elapsed_ms,
        response.get("mode"),
        response.get("intent"),
        response.get("metric_source"),
        len(response.get("data") or []),
        response.get("unsupported_reason"),
    )
    return response
