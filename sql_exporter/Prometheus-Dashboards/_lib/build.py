"""Dashboard builder: turns :class:`Panel` lists into a full Grafana
dashboard JSON document ready to be imported."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from prom_dashboard import PROM_DS, Panel, Target, ds_var, ROW_TYPE


_DEFAULT_THRESHOLDS = {
    "mode": "absolute",
    "steps": [
        {"color": "green", "value": None},
        {"color": "red", "value": 80},
    ],
}


def _panel_json(p: Panel, pid: int) -> dict[str, Any]:
    x, y, w, h = p.grid
    fc: dict[str, Any] = {
        "defaults": {
            "color": {"mode": "thresholds"},
            "mappings": [],
            "thresholds": {
                "mode": "absolute",
                "steps": p.thresholds_steps or [
                    {"color": "green", "value": None},
                ],
            },
            "unit": p.unit,
        },
        "overrides": p.field_overrides,
    }
    if p.decimals is not None:
        fc["defaults"]["decimals"] = p.decimals
    if p.min_value is not None:
        fc["defaults"]["min"] = p.min_value
    if p.max_value is not None:
        fc["defaults"]["max"] = p.max_value

    opts: dict[str, Any]
    if p.type == "timeseries":
        opts = {
            "legend": {"displayMode": "table", "placement": "bottom",
                        "showLegend": True, "calcs": ["lastNotNull", "mean", "max"]},
            "tooltip": {"mode": "multi", "sort": "desc"},
        }
        fc["defaults"]["custom"] = {
            "drawStyle": "line", "lineInterpolation": "linear",
            "lineWidth": 1, "fillOpacity": 10, "gradientMode": "none",
            "spanNulls": False, "showPoints": "never",
            "pointSize": 5, "stacking": {"mode": "none", "group": "A"},
            "axisPlacement": "auto", "axisLabel": "",
            "scaleDistribution": {"type": "linear"},
            "hideFrom": {"tooltip": False, "viz": False, "legend": False},
            "thresholdsStyle": {"mode": "off"},
        }
    elif p.type == "stat":
        opts = {
            "colorMode": "value", "graphMode": "area",
            "justifyMode": "auto", "orientation": "auto",
            "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
            "textMode": "auto", "wideLayout": True,
        }
    elif p.type == "table":
        opts = {"showHeader": True, "cellHeight": "sm",
                 "footer": {"countRows": False, "reducer": ["sum"], "show": False,
                             "fields": ""}}
        fc["defaults"]["custom"] = {
            "align": "auto", "cellOptions": {"type": "auto"},
            "inspect": False, "filterable": True,
        }
    elif p.type == "gauge":
        opts = {
            "orientation": "auto", "showThresholdLabels": False,
            "showThresholdMarkers": True,
            "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
        }
    elif p.type == "bargauge":
        opts = {
            "orientation": "horizontal", "displayMode": "gradient",
            "showUnfilled": True,
            "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
        }
    elif p.type == "text":
        opts = {"mode": "markdown", "content": p.description or p.title}
    else:
        opts = {}
    if p.options_override:
        opts.update(p.options_override)

    return {
        "id": pid,
        "type": p.type,
        "title": p.title,
        "description": p.description,
        "datasource": PROM_DS,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "fieldConfig": fc,
        "options": opts,
        "targets": [t.to_json() for t in p.targets],
        "transformations": p.transformations,
        "pluginVersion": "12.4.1",
    }


def build_dashboard(*, uid: str, title: str, tags: list[str],
                    variables: list[dict[str, Any]],
                    panels: list[Panel | dict[str, Any]],
                    description: str = "",
                    time_from: str = "now-3h", time_to: str = "now",
                    refresh: str = "30s") -> dict[str, Any]:
    pid = 100
    flat: list[dict[str, Any]] = []
    for p in panels:
        if isinstance(p, dict) and p.get("type") == ROW_TYPE:
            flat.append(p)
            continue
        pid += 1
        flat.append(_panel_json(p, pid))
    return {
        "__inputs": [{"name": "DS_PROMETHEUS", "label": "Prometheus",
                       "description": "", "type": "datasource",
                       "pluginId": "prometheus", "pluginName": "Prometheus"}],
        "__elements": {},
        "__requires": [
            {"type": "grafana", "id": "grafana", "name": "Grafana", "version": "12.0.0"},
            {"type": "datasource", "id": "prometheus", "name": "Prometheus", "version": "1.0.0"},
            {"type": "panel", "id": "timeseries", "name": "Time series", "version": ""},
            {"type": "panel", "id": "table", "name": "Table", "version": ""},
            {"type": "panel", "id": "stat", "name": "Stat", "version": ""},
        ],
        "annotations": {"list": []},
        "description": description,
        "editable": True,
        "fiscalYearStartMonth": 0,
        "graphTooltip": 1,
        "id": None,
        "links": [],
        "liveNow": False,
        "panels": flat,
        "refresh": refresh,
        "schemaVersion": 42,
        "tags": tags,
        "templating": {"list": [ds_var()] + variables},
        "time": {"from": time_from, "to": time_to},
        "timepicker": {},
        "timezone": "browser",
        "title": title,
        "uid": uid,
        "version": 1,
        "weekStart": "",
    }


def write_dashboard(out_dir: Path, filename: str, dashboard: dict[str, Any]) -> Path:
    path = out_dir / filename
    path.write_text(json.dumps(dashboard, indent=2) + "\n")
    return path
