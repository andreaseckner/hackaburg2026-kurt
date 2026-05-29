from __future__ import annotations

from typing import Any

from .analytics import (
    get_corridor_pain_points_filtered,
    get_segment_delay_growth_hotspots_filtered,
    get_stop_delay_exposure_filtered,
)

SUGGESTED_QUESTIONS = [
    "Where should we intervene first on weekday mornings?",
    "Which segment creates the most delay toward the city center?",
    "Which stops expose passengers to the most delay after 16:00?",
]


def _normalize_question(question: str) -> str:
    return " ".join(question.lower().strip().split())


def _unsupported_response(reason: str = "No supported intent matched the question.") -> dict[str, Any]:
    return {
        "intent": "unsupported",
        "confidence": 0.0,
        "title": "Question not supported yet",
        "answer": "I can only answer verified historical reliability questions for the current dataset. Try one of the suggested questions below.",
        "bullets": [],
        "metric_source": "none",
        "data": [],
        "map_state": None,
        "suggested_questions": SUGGESTED_QUESTIONS,
        "unsupported_reason": reason,
    }


def _base_response(intent: str, title: str, answer: str, metric_source: str, data: list[dict[str, Any]], map_state: dict[str, Any]) -> dict[str, Any]:
    return {
        "intent": intent,
        "confidence": 1.0,
        "title": title,
        "answer": answer,
        "bullets": [],
        "metric_source": metric_source,
        "data": data,
        "map_state": map_state,
        "suggested_questions": SUGGESTED_QUESTIONS,
        "unsupported_reason": None,
    }


def _answer_weekday_morning_intervention(db_path: str | None) -> dict[str, Any]:
    rows = get_corridor_pain_points_filtered(
        db_path=db_path,
        weekday_only=True,
        hour_from=6,
        hour_to=10,
        limit=3,
    )
    if not rows:
        return _unsupported_response("No corridor data matched weekday morning filters.")

    top = rows[0]
    response = _base_response(
        intent="weekday_morning_intervention",
        title="Weekday morning intervention priority",
        answer=(
            f"Prioritize {top['route_start']} → {top['route_end']} for weekday mornings. "
            f"It has {top['total_stop_delay_minutes']} stop-delay minutes in the filtered data."
        ),
        metric_source="corridor_pain_points_filtered weekday_only=true hour_from=6 hour_to=10",
        data=rows,
        map_state={
            "layer_type": "corridor",
            "stops": [],
            "segments": [],
            "route_start": top["route_start"],
            "route_end": top["route_end"],
            "hour_from": 6,
            "hour_to": 10,
            "severity_metric": "total_stop_delay_minutes",
        },
    )
    response["bullets"] = [
        f"{row['route_start']} → {row['route_end']}: {row['total_stop_delay_minutes']} stop-delay minutes, {row['pct_delayed_3min']}% events delayed 3+ min"
        for row in rows
    ]
    return response


def _answer_city_center_delay_growth_segment(db_path: str | None) -> dict[str, Any]:
    rows = get_segment_delay_growth_hotspots_filtered(
        db_path=db_path,
        limit=3,
        min_growth_1min_events=1,
        toward_city_center=True,
    )
    if not rows:
        return _unsupported_response("No city-center delay-growth segment matched the dataset.")

    top = rows[0]
    segment = {"previous_stop": top["previous_stop"], "current_stop": top["current_stop"], "severity": top["total_positive_growth_minutes"]}
    response = _base_response(
        intent="city_center_delay_growth_segment",
        title="City-center delay creation segment",
        answer=(
            f"The strongest city-center delay-growth segment is {top['previous_stop']} → {top['current_stop']}. "
            f"Average delay growth is {top['avg_growth_seconds']} seconds."
        ),
        metric_source="segment_delay_growth_filtered toward_city_center=true",
        data=rows,
        map_state={
            "layer_type": "segment",
            "stops": [top["previous_stop"], top["current_stop"]],
            "segments": [segment],
            "route_start": top["route_start"],
            "route_end": top["route_end"],
            "hour_from": None,
            "hour_to": None,
            "severity_metric": "total_positive_growth_minutes",
        },
    )
    response["bullets"] = [
        f"{row['previous_stop']} → {row['current_stop']}: {row['avg_growth_seconds']} sec avg growth, {row['growth_1min_events']} events grew 1+ min"
        for row in rows
    ]
    return response


def _answer_passenger_delay_exposure_after_16(db_path: str | None) -> dict[str, Any]:
    rows = get_stop_delay_exposure_filtered(db_path=db_path, hour_from=16, hour_to=23, limit=5)
    if not rows:
        return _unsupported_response("No stop delay exposure data matched hour_from=16 hour_to=23.")

    top = rows[0]
    response = _base_response(
        intent="passenger_delay_exposure_after_16",
        title="Passenger delay exposure after 16:00",
        answer=(
            f"After 16:00, passengers see the most accumulated stop-level delay at {top['stop_name']}. "
            f"That stop has {top['total_stop_delay_minutes']} stop-delay minutes in the filtered data."
        ),
        metric_source="stop_delay_exposure_filtered hour_from=16 hour_to=23",
        data=rows,
        map_state={
            "layer_type": "stops",
            "stops": [row["stop_name"] for row in rows],
            "segments": [],
            "route_start": None,
            "route_end": None,
            "hour_from": 16,
            "hour_to": 23,
            "severity_metric": "total_stop_delay_minutes",
        },
    )
    response["bullets"] = [
        f"{row['stop_name']}: {row['total_stop_delay_minutes']} stop-delay minutes, {row['delayed_3min_events']} events delayed 3+ min"
        for row in rows
    ]
    return response


def answer_transport_question(question: str, db_path: str | None = None) -> dict[str, Any]:
    q = _normalize_question(question)
    if not q:
        return _unsupported_response("Question is empty.")
    if "select " in q or ";" in q:
        return _unsupported_response("SQL input is not supported in the chat router.")
    if "intervene" in q and "weekday" in q and "morning" in q:
        return _answer_weekday_morning_intervention(db_path)
    if "segment" in q and ("city center" in q or "city centre" in q):
        return _answer_city_center_delay_growth_segment(db_path)
    if "stops" in q and "passengers" in q and ("after 16" in q or "after 4" in q):
        return _answer_passenger_delay_exposure_after_16(db_path)
    return _unsupported_response()
