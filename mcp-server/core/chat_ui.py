from __future__ import annotations

from typing import Any


def build_ui_payload(
    *,
    response_type: str,
    title: str,
    primary_metric: dict[str, Any] | None = None,
    sections: list[dict[str, Any]] | None = None,
    actions: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    return {
        "response_type": response_type,
        "title": title,
        "primary_metric": primary_metric,
        "sections": sections or [],
        "actions": actions or [],
    }


def ranked_list_ui(
    *,
    title: str,
    rows: list[dict[str, Any]],
    label_key: str,
    metric_key: str,
    metric_label: str,
    metric_unit: str,
) -> dict[str, Any]:
    items = []
    for row in rows:
        items.append(
            {
                "label": str(row.get(label_key, "")),
                "value": row.get(metric_key),
                "unit": metric_unit,
                "details": row,
            }
        )
    primary_metric = None
    if rows:
        primary_metric = {
            "label": metric_label,
            "value": rows[0].get(metric_key),
            "unit": metric_unit,
        }
    return build_ui_payload(
        response_type="ranked_list",
        title=title,
        primary_metric=primary_metric,
        sections=[{"title": "Top results", "items": items}],
    )


def fallback_ui(title: str, suggestions: list[str]) -> dict[str, Any]:
    return build_ui_payload(
        response_type="fallback",
        title=title,
        sections=[
            {
                "title": "Try one of these questions",
                "items": [{"label": question, "value": question, "unit": None, "details": {}} for question in suggestions],
            }
        ],
    )
