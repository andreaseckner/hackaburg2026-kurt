from __future__ import annotations

import re
from typing import Any

from .analytics import (
    get_corridor_pain_points_filtered,
    get_segment_delay_growth_hotspots_filtered,
    get_stop_delay_exposure_filtered,
    get_stop_delay_extremes,
    get_trip_delay_summary,
)
from .chat_ui import fallback_ui, ranked_list_ui

SUGGESTED_QUESTIONS = [
    "Where should we intervene first on weekday mornings?",
    "Which segment creates the most delay toward the city center?",
    "Which stops expose passengers to the most delay after 16:00?",
]


def _normalize_question(question: str) -> str:
    return " ".join(question.lower().strip().split())


def _extract_service_date(question: str) -> str | None:
    match = re.search(r"\b(\d{1,2})[./-](\d{1,2})[./-](\d{4})\b", question)
    if match:
        day, month, year = (int(part) for part in match.groups())
        return f"{year:04d}-{month:02d}-{day:02d}"
    match = re.search(r"\b(\d{4})-(\d{1,2})-(\d{1,2})\b", question)
    if match:
        year, month, day = (int(part) for part in match.groups())
        return f"{year:04d}-{month:02d}-{day:02d}"
    return None


def _extract_after_hour(question: str) -> int | None:
    match = re.search(r"\bafter\s+(\d{1,2})(?::\d{2})?\b", question)
    if not match:
        return None
    hour = int(match.group(1))
    if 1 <= hour <= 7:
        hour += 12
    if 0 <= hour <= 23:
        return hour
    return None


def _unsupported_response(reason: str = "No supported intent matched the question.") -> dict[str, Any]:
    return {
        "mode": "deterministic",
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


def _base_response(intent: str, title: str, answer: str, metric_source: str, data: list[dict[str, Any]], map_state: dict[str, Any]) -> dict[str, Any]:
    return {
        "mode": "deterministic",
        "intent": intent,
        "confidence": 1.0,
        "title": title,
        "answer": answer,
        "bullets": [],
        "metric_source": metric_source,
        "data": data,
        "map_state": map_state,
        "ui": {},
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
    response["ui"] = ranked_list_ui(
        title="Weekday morning corridors",
        rows=[{**row, "corridor": f"{row['route_start']} → {row['route_end']}"} for row in rows],
        label_key="corridor",
        metric_key="total_stop_delay_minutes",
        metric_label="Stop-delay minutes",
        metric_unit="min",
    )
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
    response["ui"] = ranked_list_ui(
        title="Delay-growth segments",
        rows=[{**row, "segment": f"{row['previous_stop']} → {row['current_stop']}"} for row in rows],
        label_key="segment",
        metric_key="total_positive_growth_minutes",
        metric_label="Positive delay growth",
        metric_unit="min",
    )
    return response


def _answer_stop_delay_extremes(db_path: str | None, order: str = "lowest") -> dict[str, Any]:
    rows = get_stop_delay_extremes(db_path=db_path, order=order, limit=5)
    if not rows:
        return _unsupported_response(f"No stop delay extremes matched order={order}.")

    top = rows[0]
    direction_label = "lowest" if order == "lowest" else "highest"
    response = _base_response(
        intent="stop_delay_extremes",
        title=f"Stops with the {direction_label} overall delay",
        answer=(
            f"Overall, {top['stop_name']} has the {direction_label} average positive delay: "
            f"{top['avg_positive_delay_seconds']} seconds per stop event."
        ),
        metric_source=f"stop_delay_extremes order={order}",
        data=rows,
        map_state={
            "layer_type": "stops",
            "stops": [row["stop_name"] for row in rows],
            "segments": [],
            "route_start": None,
            "route_end": None,
            "hour_from": None,
            "hour_to": None,
            "severity_metric": "avg_positive_delay_seconds",
        },
    )
    response["bullets"] = [
        f"{row['stop_name']}: {row['avg_positive_delay_seconds']} sec average positive delay, {row['total_stop_delay_minutes']} total stop-delay minutes"
        for row in rows
    ]
    response["ui"] = ranked_list_ui(
        title=f"Stops with the {direction_label} overall delay",
        rows=rows,
        label_key="stop_name",
        metric_key="avg_positive_delay_seconds",
        metric_label="Avg positive delay",
        metric_unit="sec",
    )
    return response


def _answer_passenger_delay_exposure(db_path: str | None, hour_from: int = 16, hour_to: int = 23) -> dict[str, Any]:
    rows = get_stop_delay_exposure_filtered(db_path=db_path, hour_from=hour_from, hour_to=hour_to, limit=5)
    if not rows:
        return _unsupported_response(f"No stop delay exposure data matched hour_from={hour_from} hour_to={hour_to}.")

    top = rows[0]
    response = _base_response(
        intent="passenger_delay_exposure",
        title=f"Passenger delay exposure after {hour_from:02d}:00",
        answer=(
            f"After {hour_from:02d}:00, passengers see the most accumulated stop-level delay at {top['stop_name']}. "
            f"That stop has {top['total_stop_delay_minutes']} stop-delay minutes in the filtered data."
        ),
        metric_source=f"stop_delay_exposure_filtered hour_from={hour_from} hour_to={hour_to}",
        data=rows,
        map_state={
            "layer_type": "stops",
            "stops": [row["stop_name"] for row in rows],
            "segments": [],
            "route_start": None,
            "route_end": None,
            "hour_from": hour_from,
            "hour_to": hour_to,
            "severity_metric": "total_stop_delay_minutes",
        },
    )
    response["bullets"] = [
        f"{row['stop_name']}: {row['total_stop_delay_minutes']} stop-delay minutes, {row['delayed_3min_events']} events delayed 3+ min"
        for row in rows
    ]
    response["ui"] = ranked_list_ui(
        title="Stops with passenger delay exposure",
        rows=rows,
        label_key="stop_name",
        metric_key="total_stop_delay_minutes",
        metric_label="Stop-delay minutes",
        metric_unit="min",
    )
    return response


def _answer_trip_delay_for_date(db_path: str | None, service_date: str) -> dict[str, Any]:
    summary = get_trip_delay_summary(db_path=db_path, service_date=service_date)
    if summary.get("approx_trips", 0) == 0:
        return _unsupported_response(f"No trips found for {service_date}.")
    response = _base_response(
        intent="trip_delay_for_date",
        title=f"End-to-end trip delay on {service_date}",
        answer=(
            f"On {summary['service_date']}, Line 1 had about {summary['approx_trips']} end-to-end trips. "
            f"Counting each trip once, they accumulated {summary['total_trip_delay_minutes']} minutes "
            f"({summary['total_trip_delay_hours']} hours) of trip-level delay. "
            f"The worst single trip reached {summary['worst_trip_delay_minutes']} minutes late."
        ),
        metric_source="trip_delay_summary max positive delay per end-to-end trip",
        data=[summary],
        map_state={
            "layer_type": "route",
            "stops": [],
            "segments": [],
            "route_start": None,
            "route_end": None,
            "hour_from": None,
            "hour_to": None,
            "severity_metric": "total_trip_delay_minutes",
        },
    )
    response["bullets"] = [
        f"End-to-end trips: {summary['approx_trips']}",
        f"Total trip-level delay: {summary['total_trip_delay_minutes']} minutes ({summary['total_trip_delay_hours']} hours)",
        f"Worst single trip: {summary['worst_trip_delay_minutes']} minutes late",
        f"Trips delayed 3+ minutes: {summary['trips_delayed_3min']}",
        f"Stop-level burden, for context only: {summary['total_stop_delay_minutes']} minutes",
    ]
    response["ui"] = ranked_list_ui(
        title=f"End-to-end trip delay on {service_date}",
        rows=[summary],
        label_key="service_date",
        metric_key="total_trip_delay_minutes",
        metric_label="Trip-level delay",
        metric_unit="min",
    )
    return response


def answer_transport_question(question: str, db_path: str | None = None) -> dict[str, Any]:
    q = _normalize_question(question)
    if not q:
        return _unsupported_response("Question is empty.")
    if "select " in q or ";" in q:
        return _unsupported_response("SQL input is not supported in the chat router.")
    service_date = _extract_service_date(q)
    if service_date and "delay" in q:
        return _answer_trip_delay_for_date(db_path, service_date)
    if "intervene" in q and "weekday" in q and "morning" in q:
        return _answer_weekday_morning_intervention(db_path)
    if "segment" in q and ("city center" in q or "city centre" in q):
        return _answer_city_center_delay_growth_segment(db_path)
    after_hour = _extract_after_hour(q)
    if "stops" in q and "passengers" in q and after_hour is not None:
        return _answer_passenger_delay_exposure(db_path, hour_from=after_hour)
    if ("station" in q or "stop" in q) and "delay" in q and "overall" in q and ("lowest" in q or "least" in q or "best" in q):
        return _answer_stop_delay_extremes(db_path, order="lowest")
    if ("station" in q or "stop" in q) and "delay" in q and "overall" in q and ("highest" in q or "most" in q or "worst" in q):
        return _answer_stop_delay_extremes(db_path, order="highest")
    return _unsupported_response()
