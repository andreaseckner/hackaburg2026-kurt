from __future__ import annotations

import json
import logging
import os
import re
import urllib.error
import urllib.request
from collections.abc import Callable
from pathlib import Path
from typing import Any

try:
    from dotenv import load_dotenv
except ImportError:  # pragma: no cover - optional dependency during partial installs
    load_dotenv = None

if load_dotenv is not None:
    load_dotenv(Path(__file__).resolve().parents[1] / ".env")

from .analytics import (
    get_corridor_pain_points_filtered,
    get_segment_delay_growth_hotspots_filtered,
    get_stop_delay_exposure_filtered,
)
from .chat import SUGGESTED_QUESTIONS, answer_transport_question
from .chat_ui import fallback_ui, ranked_list_ui
from .mcp_tool_client import call_local_mcp_tool

logger = logging.getLogger("uvicorn.error")

ToolClassifier = Callable[[str], dict[str, Any]]
McpToolCaller = Callable[[str, dict[str, Any]], str]
AnswerSynthesizer = Callable[[str, str, dict[str, Any], list[dict[str, Any]]], dict[str, Any] | None]

_ALLOWED_MCP_TOOLS = {
    "get_delay_by_weekday",
    "get_delay_by_hour",
    "get_delay_hotspot_stops",
    "get_stop_delay_extremes",
    "get_early_departure_hotspots",
    "get_bottleneck_stop_hotspots",
    "compare_route_directions",
    "explain_trip_delay_for_day",
    "get_corridor_reliability_pain_points",
    "get_delay_growth_segments",
    "explain_reliability_pain_points_for_day",
    "delay_ranking",
    "get_delay_event_attributes",
    "get_delay_attribute_values",
    "get_delay_event_records",
}

_ALLOWED_TOOLS = {
    "corridor_pain_points",
    "segment_delay_growth",
    "stop_delay_exposure",
    "unsupported",
    *{f"mcp.{tool}" for tool in _ALLOWED_MCP_TOOLS},
}


def _classifier_prompt(question: str) -> str:
    return f"""
Classify this transport reliability question into exactly one JSON tool call.
Return exactly this JSON shape and nothing else:
{{"tool":"mcp.get_delay_hotspot_stops","parameters":{{"limit":5}}}}
Do not return code, markdown, tool_code, print(...), or function-call syntax.
Allowed tools:
- corridor_pain_points parameters: weekday_only bool|null, hour_from int|null, hour_to int|null, limit int
- segment_delay_growth parameters: toward_city_center bool, hour_from int|null, hour_to int|null, limit int
- stop_delay_exposure parameters: weekday_only bool|null, hour_from int|null, hour_to int|null, limit int
- mcp.get_delay_by_weekday parameters: order "lowest"|"highest"
- mcp.get_delay_by_hour parameters: {{}}
- mcp.get_delay_hotspot_stops parameters: limit int, service_date YYYY-MM-DD|null
- mcp.get_stop_delay_extremes parameters: order "lowest"|"highest", limit int
- mcp.get_early_departure_hotspots parameters: limit int
- mcp.get_bottleneck_stop_hotspots parameters: limit int
- mcp.compare_route_directions parameters: {{}}
- mcp.explain_trip_delay_for_day parameters: service_date YYYY-MM-DD
- mcp.get_corridor_reliability_pain_points parameters: limit int
- mcp.get_delay_growth_segments parameters: limit int, min_growth_1min_events int
- mcp.explain_reliability_pain_points_for_day parameters: service_date YYYY-MM-DD
- mcp.delay_ranking parameters: group_by "overall"|"stop"|"weekday"|"hour"|"date"|"corridor"|"direction", line_id string|null, date_from YYYY-MM-DD|null, date_to YYYY-MM-DD|null, weekday_only bool, hour_from int|null, hour_to int|null, stop_name string|null, direction string|null, order "highest"|"lowest", limit int
- mcp.get_delay_event_attributes parameters: {{}}
- mcp.get_delay_attribute_values parameters: attribute string, line_id string|null, stop_name string|null, weekday_name string|null, hour_from int|null, hour_to int|null, limit int
- mcp.get_delay_event_records parameters: attributes list[string]|null, filters object|null, hour_from int|null, hour_to int|null, order_by string, order "highest"|"lowest", limit int
- unsupported parameters: reason string
Never choose mcp.query_readonly_sql.
Never choose mcp.answer_reliability_question; use a specific analytics tool instead.
For questions asking "all delays from bus line N" or "delays from line N", choose mcp.delay_ranking with group_by="date", line_id="N", order="highest".
For questions asking "overall" delay for bus line N, choose mcp.delay_ranking with group_by="overall", line_id="N".
For questions asking "rush hour" or "rushhour", include hour_from=7 and hour_to=18.
For questions asking "between 4pm and 6pm" or similar, convert to 24-hour inclusive hour_from/hour_to, e.g. hour_from=16 and hour_to=18.
For questions asking "how many delays" or "delays on" one day, choose mcp.delay_ranking with group_by="date", date_from=date_to=that day, order="highest".
For generic exploratory questions where you need raw context rows rather than an aggregate, choose mcp.get_delay_event_records with only the attributes and filters needed.
For questions asking what lines/stops/dates/hours exist, choose mcp.get_delay_attribute_values for that attribute.

Question: {question}
""".strip()


def _unsupported_response(reason: str) -> dict[str, Any]:
    return {
        "mode": "llm_tool_router",
        "intent": "unsupported",
        "confidence": 0.0,
        "title": "Question not supported yet",
        "answer": "I can only answer verified historical reliability questions for the current dataset. Try one of the suggested questions below.",
        "bullets": [],
        "metric_source": "none",
        "data": [],
        "map_state": None,
        "ui": fallback_ui("Question not supported yet", SUGGESTED_QUESTIONS),
        "suggested_questions": SUGGESTED_QUESTIONS,
        "unsupported_reason": reason,
    }


def _as_bool(value: Any, default: bool | None = None) -> bool | None:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in {"true", "1", "yes"}:
            return True
        if lowered in {"false", "0", "no"}:
            return False
    return default


def _as_hour(value: Any) -> int | None:
    if value is None or value == "":
        return None
    hour = int(value)
    if not 0 <= hour <= 23:
        raise ValueError("hour must be between 0 and 23")
    return hour


def _as_limit(value: Any, default: int = 5) -> int:
    if value is None or value == "":
        return default
    return max(1, min(int(value), 10))


def _normalize_tool_name(raw_tool: Any) -> str:
    tool = str(raw_tool or "unsupported").strip()
    if tool in _ALLOWED_TOOLS:
        return tool
    match = re.search(r"\bmcp\.([a-zA-Z_][a-zA-Z0-9_]*)\b", tool)
    if match:
        return f"mcp.{match.group(1)}"
    return tool


def _sanitize_choice(choice: dict[str, Any]) -> tuple[str, dict[str, Any]]:
    tool = _normalize_tool_name(choice.get("tool") or choice.get("tool_code") or choice.get("tool_name"))
    if tool not in _ALLOWED_TOOLS:
        raise ValueError(f"Unsupported tool: {tool}")
    raw_params = choice.get("parameters") or {}
    if not isinstance(raw_params, dict):
        raise ValueError("parameters must be an object")
    params: dict[str, Any] = {}
    if tool == "corridor_pain_points":
        params = {
            "weekday_only": _as_bool(raw_params.get("weekday_only")),
            "hour_from": _as_hour(raw_params.get("hour_from")),
            "hour_to": _as_hour(raw_params.get("hour_to")),
            "limit": _as_limit(raw_params.get("limit"), 3),
        }
    elif tool == "segment_delay_growth":
        params = {
            "toward_city_center": _as_bool(raw_params.get("toward_city_center"), False),
            "hour_from": _as_hour(raw_params.get("hour_from")),
            "hour_to": _as_hour(raw_params.get("hour_to")),
            "limit": _as_limit(raw_params.get("limit"), 3),
        }
    elif tool == "stop_delay_exposure":
        params = {
            "weekday_only": _as_bool(raw_params.get("weekday_only")),
            "hour_from": _as_hour(raw_params.get("hour_from")),
            "hour_to": _as_hour(raw_params.get("hour_to")),
            "limit": _as_limit(raw_params.get("limit"), 5),
        }
    elif tool.startswith("mcp."):
        mcp_tool = tool.removeprefix("mcp.")
        params = _sanitize_mcp_params(mcp_tool, raw_params)
    return tool, params


def _sanitize_mcp_params(tool: str, raw_params: dict[str, Any]) -> dict[str, Any]:
    if tool not in _ALLOWED_MCP_TOOLS:
        raise ValueError(f"Unsupported MCP tool: {tool}")
    if tool in {"get_delay_by_hour", "compare_route_directions", "get_delay_event_attributes"}:
        return {}
    if tool == "get_delay_by_weekday":
        order = str(raw_params.get("order") or "highest").strip().lower()
        if order not in {"lowest", "highest"}:
            order = "highest"
        return {"order": order}
    if tool == "get_stop_delay_extremes":
        order = str(raw_params.get("order") or "lowest").strip().lower()
        if order not in {"lowest", "highest"}:
            raise ValueError("order must be lowest or highest")
        return {"order": order, "limit": _as_limit(raw_params.get("limit"), 10)}
    if tool in {
        "get_delay_hotspot_stops",
        "get_early_departure_hotspots",
        "get_bottleneck_stop_hotspots",
        "get_corridor_reliability_pain_points",
    }:
        return {"limit": _as_limit(raw_params.get("limit"), 10)}
    if tool == "get_delay_growth_segments":
        return {
            "limit": _as_limit(raw_params.get("limit"), 10),
            "min_growth_1min_events": max(1, min(int(raw_params.get("min_growth_1min_events") or 100), 10000)),
        }
    if tool in {"explain_trip_delay_for_day", "explain_reliability_pain_points_for_day"}:
        service_date = str(raw_params.get("service_date") or "2024-12-12")
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", service_date):
            raise ValueError("service_date must be YYYY-MM-DD")
        return {"service_date": service_date}
    if tool == "delay_ranking":
        valid_group_by = {"overall", "stop", "weekday", "hour", "date", "corridor", "direction"}
        gb = str(raw_params.get("group_by") or "stop").strip().lower()
        if gb not in valid_group_by:
            gb = "stop"
        order = str(raw_params.get("order") or "highest").strip().lower()
        if order not in {"lowest", "highest"}:
            order = "highest"
        params: dict[str, Any] = {"group_by": gb, "order": order, "limit": _as_limit(raw_params.get("limit"), 10)}
        line_id = raw_params.get("line_id")
        if line_id is not None and str(line_id).strip():
            params["line_id"] = str(line_id).strip()[:20]
        for date_key in ("date_from", "date_to"):
            val = raw_params.get(date_key)
            if val and re.fullmatch(r"\d{4}-\d{2}-\d{2}", str(val)):
                params[date_key] = str(val)
        if _as_bool(raw_params.get("weekday_only")) is True:
            params["weekday_only"] = True
        for hour_key in ("hour_from", "hour_to"):
            h = _as_hour(raw_params.get(hour_key))
            if h is not None:
                params[hour_key] = h
        for str_key in ("stop_name", "direction"):
            val = raw_params.get(str_key)
            if val and isinstance(val, str) and val.strip():
                params[str_key] = val.strip()[:100]
        return params
    if tool == "get_delay_attribute_values":
        valid_attributes = {
            "service_date",
            "weekday_name",
            "weekday_number",
            "hour",
            "planned_departure_hour",
            "line_id",
            "stop_name",
            "stop_code",
            "stop_point",
            "departure_delay_seconds",
            "departure_delay_minutes",
            "positive_delay_minutes",
            "direction_id",
            "run_id",
            "planned_departure",
            "route_start",
            "route_start_code",
            "route_end",
            "route_end_code",
        }
        attribute = str(raw_params.get("attribute") or "line_id").strip()
        if attribute not in valid_attributes:
            raise ValueError("Unsupported delay attribute")
        params = {"attribute": attribute, "limit": _as_limit(raw_params.get("limit"), 50)}
        for str_key in ("line_id", "stop_name", "weekday_name"):
            val = raw_params.get(str_key)
            if val is not None and str(val).strip():
                params[str_key] = str(val).strip()[:100]
        for hour_key in ("hour_from", "hour_to"):
            h = _as_hour(raw_params.get(hour_key))
            if h is not None:
                params[hour_key] = h
        return params
    if tool == "get_delay_event_records":
        valid_attributes = {
            "service_date",
            "weekday_name",
            "weekday_number",
            "hour",
            "planned_departure_hour",
            "line_id",
            "stop_name",
            "stop_code",
            "stop_point",
            "departure_delay_seconds",
            "departure_delay_minutes",
            "positive_delay_minutes",
            "direction_id",
            "run_id",
            "planned_departure",
            "route_start",
            "route_start_code",
            "route_end",
            "route_end_code",
        }
        raw_attributes = raw_params.get("attributes")
        attributes = [str(item).strip() for item in raw_attributes if str(item).strip()] if isinstance(raw_attributes, list) else []
        invalid = [attribute for attribute in attributes if attribute not in valid_attributes]
        if invalid:
            raise ValueError(f"Unsupported delay attributes: {invalid}")
        raw_filters = raw_params.get("filters") or {}
        if not isinstance(raw_filters, dict):
            raise ValueError("filters must be an object")
        valid_filters = {"service_date", "weekday_name", "line_id", "stop_name", "route_start", "route_end", "direction_id"}
        filters = {str(key): value for key, value in raw_filters.items() if key in valid_filters and value not in (None, "")}
        order_by = str(raw_params.get("order_by") or "positive_delay_minutes").strip()
        if order_by not in valid_attributes:
            order_by = "positive_delay_minutes"
        order = str(raw_params.get("order") or "highest").strip().lower()
        if order not in {"lowest", "highest"}:
            order = "highest"
        params = {
            "attributes": attributes or None,
            "filters": filters or None,
            "order_by": order_by,
            "order": order,
            "limit": _as_limit(raw_params.get("limit"), 25),
        }
        for hour_key in ("hour_from", "hour_to"):
            h = _as_hour(raw_params.get(hour_key))
            if h is not None:
                params[hour_key] = h
        return params
    return {}


def _metric_filter_source(tool: str, params: dict[str, Any]) -> str:
    pieces = []
    for key in ("weekday_only", "toward_city_center", "hour_from", "hour_to"):
        if key in params and params[key] is not None:
            pieces.append(f"{key}={str(params[key]).lower()}")
    suffix = " " + " ".join(pieces) if pieces else ""
    if tool == "corridor_pain_points":
        return f"corridor_pain_points_filtered{suffix}"
    if tool == "segment_delay_growth":
        return f"segment_delay_growth_filtered{suffix}"
    if tool == "stop_delay_exposure":
        return f"stop_delay_exposure_filtered{suffix}"
    return "none"


def _corridor_answer(db_path: str | None, params: dict[str, Any]) -> dict[str, Any]:
    rows = get_corridor_pain_points_filtered(db_path=db_path, **params)
    if not rows:
        return _unsupported_response("No corridor data matched the selected filters.")
    top = rows[0]
    corridor_rows = [{**row, "corridor": f"{row['route_start']} → {row['route_end']}"} for row in rows]
    return {
        "mode": "llm_tool_router",
        "intent": "corridor_pain_points",
        "confidence": 1.0,
        "title": "Corridor reliability pain points",
        "answer": f"The strongest corridor pain point is {top['route_start']} → {top['route_end']} with {top['total_stop_delay_minutes']} stop-delay minutes.",
        "bullets": [
            f"{row['corridor']}: {row['total_stop_delay_minutes']} stop-delay minutes, {row['pct_delayed_3min']}% events delayed 3+ min"
            for row in corridor_rows
        ],
        "metric_source": _metric_filter_source("corridor_pain_points", params),
        "data": rows,
        "map_state": {
            "layer_type": "corridor",
            "stops": [],
            "segments": [],
            "route_start": top["route_start"],
            "route_end": top["route_end"],
            "hour_from": params.get("hour_from"),
            "hour_to": params.get("hour_to"),
            "severity_metric": "total_stop_delay_minutes",
        },
        "ui": ranked_list_ui(
            title="Corridor reliability pain points",
            rows=corridor_rows,
            label_key="corridor",
            metric_key="total_stop_delay_minutes",
            metric_label="Stop-delay minutes",
            metric_unit="min",
        ),
        "suggested_questions": SUGGESTED_QUESTIONS,
        "unsupported_reason": None,
    }


def _segment_answer(db_path: str | None, params: dict[str, Any]) -> dict[str, Any]:
    rows = get_segment_delay_growth_hotspots_filtered(db_path=db_path, min_growth_1min_events=1, **params)
    if not rows:
        return _unsupported_response("No delay-growth segment data matched the selected filters.")
    top = rows[0]
    segment_rows = [{**row, "segment": f"{row['previous_stop']} → {row['current_stop']}"} for row in rows]
    return {
        "mode": "llm_tool_router",
        "intent": "segment_delay_growth",
        "confidence": 1.0,
        "title": "Delay-growth segments",
        "answer": f"The strongest delay-growth segment is {top['previous_stop']} → {top['current_stop']} with {top['total_positive_growth_minutes']} positive delay-growth minutes.",
        "bullets": [
            f"{row['segment']}: {row['avg_growth_seconds']} sec avg growth, {row['growth_1min_events']} events grew 1+ min"
            for row in segment_rows
        ],
        "metric_source": _metric_filter_source("segment_delay_growth", params),
        "data": rows,
        "map_state": {
            "layer_type": "segment",
            "stops": [top["previous_stop"], top["current_stop"]],
            "segments": [{"previous_stop": top["previous_stop"], "current_stop": top["current_stop"], "severity": top["total_positive_growth_minutes"]}],
            "route_start": top["route_start"],
            "route_end": top["route_end"],
            "hour_from": params.get("hour_from"),
            "hour_to": params.get("hour_to"),
            "severity_metric": "total_positive_growth_minutes",
        },
        "ui": ranked_list_ui(
            title="Delay-growth segments",
            rows=segment_rows,
            label_key="segment",
            metric_key="total_positive_growth_minutes",
            metric_label="Positive delay growth",
            metric_unit="min",
        ),
        "suggested_questions": SUGGESTED_QUESTIONS,
        "unsupported_reason": None,
    }


def _stop_answer(db_path: str | None, params: dict[str, Any]) -> dict[str, Any]:
    rows = get_stop_delay_exposure_filtered(db_path=db_path, **params)
    if not rows:
        return _unsupported_response("No stop delay exposure data matched the selected filters.")
    top = rows[0]
    return {
        "mode": "llm_tool_router",
        "intent": "stop_delay_exposure",
        "confidence": 1.0,
        "title": "Passenger delay exposure by stop",
        "answer": f"The highest passenger delay exposure is at {top['stop_name']} with {top['total_stop_delay_minutes']} stop-delay minutes.",
        "bullets": [
            f"{row['stop_name']}: {row['total_stop_delay_minutes']} stop-delay minutes, {row['delayed_3min_events']} events delayed 3+ min"
            for row in rows
        ],
        "metric_source": _metric_filter_source("stop_delay_exposure", params),
        "data": rows,
        "map_state": {
            "layer_type": "stops",
            "stops": [row["stop_name"] for row in rows],
            "segments": [],
            "route_start": None,
            "route_end": None,
            "hour_from": params.get("hour_from"),
            "hour_to": params.get("hour_to"),
            "severity_metric": "total_stop_delay_minutes",
        },
        "ui": ranked_list_ui(
            title="Passenger delay exposure by stop",
            rows=rows,
            label_key="stop_name",
            metric_key="total_stop_delay_minutes",
            metric_label="Stop-delay minutes",
            metric_unit="min",
        ),
        "suggested_questions": SUGGESTED_QUESTIONS,
        "unsupported_reason": None,
    }


def _mcp_label_key(rows: list[dict[str, Any]]) -> str:
    if not rows:
        return "label"
    first = rows[0]
    for key in ("stop_name", "weekday_name", "planned_departure_hour", "service_date", "route_end", "route_start", "current_stop"):
        if key in first:
            return key
    return next(iter(first.keys()))


def _mcp_metric_key(rows: list[dict[str, Any]]) -> str:
    if not rows:
        return "value"
    first = rows[0]
    for key in (
        "total_trip_delay_minutes",
        "total_stop_delay_minutes",
        "avg_daily_stop_delay_minutes",
        "total_positive_growth_minutes",
        "delayed_3min_events",
        "event_count",
        "trip_count",
    ):
        if key in first:
            return key
    for key, value in first.items():
        if isinstance(value, int | float):
            return key
    return next(iter(first.keys()))


def _synthesis_prompt(question: str, tool_name: str, params: dict[str, Any], rows: list[dict[str, Any]]) -> str:
    context_json = json.dumps(rows[:10], ensure_ascii=False, indent=2)
    params_json = json.dumps(params, ensure_ascii=False, sort_keys=True)
    return f"""
You are Kurt, a transport reliability assistant.
Use ONLY the MCP tool result below as factual context. Do not invent dates, lines, stops, counts, or delays.
Return exactly one JSON object and nothing else with this shape:
{{"title":"short title","answer":"one concise paragraph grounded in the rows","bullets":["top fact 1","top fact 2"]}}

User question: {question}
MCP tool: {tool_name}
MCP parameters: {params_json}
MCP result rows:
{context_json}
""".strip()


def _sanitize_synthesized_answer(raw: dict[str, Any], fallback_title: str, fallback_answer: str, fallback_bullets: list[str]) -> dict[str, Any]:
    title = str(raw.get("title") or fallback_title).strip()[:120]
    answer = str(raw.get("answer") or fallback_answer).strip()
    raw_bullets = raw.get("bullets")
    bullets = [str(item).strip() for item in raw_bullets if str(item).strip()] if isinstance(raw_bullets, list) else []
    return {
        "title": title or fallback_title,
        "answer": answer or fallback_answer,
        "bullets": bullets[:10] or fallback_bullets,
    }


def gemini_answer_synthesizer(question: str, tool_name: str, params: dict[str, Any], rows: list[dict[str, Any]]) -> dict[str, Any] | None:
    if not os.environ.get("GEMINI_API_KEY"):
        logger.info("chat/llm synthesizer skipped reason=missing_gemini_api_key")
        return None
    try:
        from google import genai  # type: ignore
    except ImportError:
        logger.info("chat/llm synthesizer skipped reason=google_genai_not_installed")
        return None

    model = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash")
    client = genai.Client()
    prompt = _synthesis_prompt(question, tool_name, params, rows)
    try:
        response = client.models.generate_content(model=model, contents=prompt)
    except Exception:
        logger.exception("chat/llm synthesizer failed model=%s", model)
        return None
    logger.info("chat/llm synthesizer response model=%s text_len=%s", model, len(response.text or ""))
    return _extract_json(response.text or "{}")


def ollama_answer_synthesizer(question: str, tool_name: str, params: dict[str, Any], rows: list[dict[str, Any]]) -> dict[str, Any] | None:
    model = os.environ.get("OLLAMA_MODEL") or os.environ.get("LOCAL_LLM_MODEL")
    if not model:
        logger.info("chat/ollama synthesizer skipped reason=missing_ollama_model")
        return None

    base_url = (os.environ.get("OLLAMA_BASE_URL") or os.environ.get("LOCAL_LLM_BASE_URL") or "http://127.0.0.1:11434").rstrip("/")
    timeout_seconds = float(os.environ.get("OLLAMA_TIMEOUT_SECONDS", "120"))
    payload = json.dumps(
        {
            "model": model,
            "prompt": _synthesis_prompt(question, tool_name, params, rows),
            "stream": False,
            "format": "json",
            "options": {"temperature": 0.0, "num_predict": 2048},
        }
    ).encode()
    request = urllib.request.Request(
        f"{base_url}/api/generate",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
            response_json = json.loads(response.read().decode())
    except (OSError, urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        logger.exception("chat/ollama synthesizer failed base_url=%s model=%s", base_url, model)
        return None

    text = str(response_json.get("response") or "")
    if not text.strip():
        logger.warning("chat/ollama synthesizer empty_response base_url=%s model=%s", base_url, model)
        return None
    logger.info("chat/ollama synthesizer response base_url=%s model=%s text_len=%s", base_url, model, len(text))
    return _extract_json(text or "{}")


def default_answer_synthesizer(question: str, tool_name: str, params: dict[str, Any], rows: list[dict[str, Any]]) -> dict[str, Any] | None:
    provider = os.environ.get("LLM_PROVIDER", "auto").strip().lower()
    if provider == "gemini":
        return gemini_answer_synthesizer(question, tool_name, params, rows)
    if provider in {"ollama", "local", "local_llm"}:
        return ollama_answer_synthesizer(question, tool_name, params, rows)
    if provider not in {"", "auto"}:
        logger.info("chat/synthesizer unknown_llm_provider=%s using=auto", provider)

    synthesized = gemini_answer_synthesizer(question, tool_name, params, rows)
    if synthesized is not None:
        return synthesized
    return ollama_answer_synthesizer(question, tool_name, params, rows)

def _mcp_tool_answer(
    question: str,
    tool_name: str,
    params: dict[str, Any],
    caller: McpToolCaller,
    synthesize_answer: AnswerSynthesizer | None = None,
) -> dict[str, Any]:
    result_text = caller(tool_name, params)
    parsed = json.loads(result_text) if result_text.strip() else []
    rows = parsed if isinstance(parsed, list) else [parsed]
    rows = [row for row in rows if isinstance(row, dict)]
    if not rows:
        return _unsupported_response(f"MCP tool {tool_name} returned no displayable rows.")
    label_key = _mcp_label_key(rows)
    metric_key = _mcp_metric_key(rows)
    top = rows[0]
    title = tool_name.replace("_", " ").title()
    answer = f"MCP tool {tool_name} returned {len(rows)} result(s). Top result: {top.get(label_key)}."
    bullets = [f"{row.get(label_key)}: {row.get(metric_key)}" for row in rows[:5]]
    if synthesize_answer is not None:
        try:
            synthesized = synthesize_answer(question, tool_name, params, rows)
        except Exception:
            logger.exception("chat/router answer_synthesis_failed tool=%s params=%s", tool_name, params)
            synthesized = None
        if synthesized is not None:
            payload = _sanitize_synthesized_answer(synthesized, title, answer, bullets)
            title = payload["title"]
            answer = payload["answer"]
            bullets = payload["bullets"]
    return {
        "mode": "llm_mcp_tool_router",
        "intent": tool_name,
        "tool_name": tool_name,
        "confidence": 1.0,
        "title": title,
        "answer": answer,
        "bullets": bullets,
        "metric_source": f"mcp:{tool_name}",
        "data": rows,
        "map_state": {
            "layer_type": "stops" if "stop_name" in top else "table",
            "stops": [str(row["stop_name"]) for row in rows if "stop_name" in row],
            "segments": [],
            "route_start": None,
            "route_end": None,
            "hour_from": None,
            "hour_to": None,
            "severity_metric": metric_key,
        },
        "ui": ranked_list_ui(
            title=title,
            rows=rows,
            label_key=label_key,
            metric_key=metric_key,
            metric_label=metric_key.replace("_", " ").title(),
            metric_unit="min" if "minutes" in metric_key else "",
        ),
        "suggested_questions": SUGGESTED_QUESTIONS,
        "unsupported_reason": None,
    }


def _extract_json(text: str) -> dict[str, Any]:
    stripped = text.strip()
    if stripped.startswith("```"):
        stripped = re.sub(r"^```(?:json)?\s*", "", stripped)
        stripped = re.sub(r"\s*```$", "", stripped)
    return json.loads(stripped)


def gemini_tool_classifier(question: str) -> dict[str, Any] | None:
    if not os.environ.get("GEMINI_API_KEY"):
        logger.info("chat/llm classifier skipped reason=missing_gemini_api_key")
        return None
    try:
        from google import genai  # type: ignore
    except ImportError:
        logger.info("chat/llm classifier skipped reason=google_genai_not_installed")
        return None

    model = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash")
    client = genai.Client()
    prompt = _classifier_prompt(question)
    try:
        response = client.models.generate_content(model=model, contents=prompt)
    except Exception:
        logger.exception("chat/llm classifier failed model=%s", model)
        return None
    logger.info("chat/llm classifier response model=%s text_len=%s", model, len(response.text or ""))
    return _extract_json(response.text or "{}")


def ollama_tool_classifier(question: str) -> dict[str, Any] | None:
    model = os.environ.get("OLLAMA_MODEL") or os.environ.get("LOCAL_LLM_MODEL")
    if not model:
        logger.info("chat/ollama classifier skipped reason=missing_ollama_model")
        return None

    base_url = (os.environ.get("OLLAMA_BASE_URL") or os.environ.get("LOCAL_LLM_BASE_URL") or "http://127.0.0.1:11434").rstrip("/")
    timeout_seconds = float(os.environ.get("OLLAMA_TIMEOUT_SECONDS", "120"))
    payload = json.dumps(
        {
            "model": model,
            "prompt": _classifier_prompt(question),
            "stream": False,
            "format": "json",
            "options": {"temperature": 0.0, "num_predict": 2048},
        }
    ).encode()
    request = urllib.request.Request(
        f"{base_url}/api/generate",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
            response_json = json.loads(response.read().decode())
    except (OSError, urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        logger.exception("chat/ollama classifier failed base_url=%s model=%s", base_url, model)
        return None

    text = str(response_json.get("response") or "")
    if not text.strip():
        logger.warning(
            "chat/ollama classifier empty_response base_url=%s model=%s done_reason=%s eval_count=%s (try increasing num_predict)",
            base_url, model, response_json.get("done_reason"), response_json.get("eval_count"),
        )
        return None
    logger.info("chat/ollama classifier response base_url=%s model=%s text_len=%s", base_url, model, len(text))
    return _extract_json(text or "{}")


def default_tool_classifier(question: str) -> dict[str, Any] | None:
    provider = os.environ.get("LLM_PROVIDER", "auto").strip().lower()
    if provider == "gemini":
        return gemini_tool_classifier(question)
    if provider in {"ollama", "local", "local_llm"}:
        return ollama_tool_classifier(question)
    if provider not in {"", "auto"}:
        logger.info("chat/router unknown_llm_provider=%s using=auto", provider)

    choice = gemini_tool_classifier(question)
    if choice is not None:
        return choice
    return ollama_tool_classifier(question)


def answer_transport_question_with_llm(
    question: str,
    db_path: str | None = None,
    classify_tool: ToolClassifier | None = None,
    call_mcp_tool: McpToolCaller | None = None,
    synthesize_answer: AnswerSynthesizer | None = None,
) -> dict[str, Any]:
    deterministic = answer_transport_question(question, db_path)
    if deterministic["intent"] != "unsupported":
        deterministic["mode"] = "deterministic_fallback"
        logger.info(
            "chat/router deterministic_match intent=%s metric_source=%s rows=%s",
            deterministic.get("intent"),
            deterministic.get("metric_source"),
            len(deterministic.get("data") or []),
        )
        return deterministic

    classifier = classify_tool or default_tool_classifier
    choice = classifier(question) if classifier else None
    if choice is None:
        deterministic["mode"] = "deterministic_fallback"
        logger.info("chat/router classifier_unavailable using=deterministic_fallback")
        return deterministic
    logger.info("chat/router classifier_choice=%s", choice)
    try:
        tool, params = _sanitize_choice(choice)
    except (TypeError, ValueError):
        logger.exception("chat/router invalid_classifier_choice=%s", choice)
        return _unsupported_response("The LLM selected an unsupported or invalid tool.")

    if tool == "unsupported":
        logger.info("chat/router unsupported_by_classifier reason=%s", (choice.get("parameters") or {}).get("reason"))
        return _unsupported_response(str((choice.get("parameters") or {}).get("reason", "No supported analytics tool matched.")))
    if tool.startswith("mcp."):
        mcp_tool = tool.removeprefix("mcp.")
        logger.info("chat/router call_mcp_tool tool=%s params=%s", mcp_tool, params)
        try:
            caller = call_mcp_tool or call_local_mcp_tool
            synthesizer = synthesize_answer if synthesize_answer is not None else (default_answer_synthesizer if call_mcp_tool is None else None)
            return _mcp_tool_answer(question, mcp_tool, params, caller, synthesizer)
        except (RuntimeError, json.JSONDecodeError, TypeError, ValueError) as exc:
            logger.exception("chat/router mcp_tool_failed tool=%s params=%s", mcp_tool, params)
            return _unsupported_response(f"MCP tool call failed: {exc}")
    if tool == "corridor_pain_points":
        logger.info("chat/router call_local_tool tool=%s params=%s", tool, params)
        return _corridor_answer(db_path, params)
    if tool == "segment_delay_growth":
        logger.info("chat/router call_local_tool tool=%s params=%s", tool, params)
        return _segment_answer(db_path, params)
    if tool == "stop_delay_exposure":
        logger.info("chat/router call_local_tool tool=%s params=%s", tool, params)
        return _stop_answer(db_path, params)
    logger.info("chat/router no_supported_tool tool=%s params=%s", tool, params)
    return _unsupported_response("No supported analytics tool matched.")
