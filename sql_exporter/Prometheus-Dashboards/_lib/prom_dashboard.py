"""Helpers for generating Prometheus-backed Grafana dashboard JSON for
SQLMonitor. Every dashboard in this folder is produced from a small
Python spec by calling :func:`build_dashboard`.

The helpers aim for consistency with the existing sample dashboard
``sql_exporter/SQL-Exporter-Metrics-Dashboard-External.json`` so all
dashboards share the same datasource picker, schemaVersion, and
``${DS_PROMETHEUS}`` / ``$Server`` variables.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


PROM_DS = {"type": "prometheus", "uid": "${DS_PROMETHEUS}"}


def ds_var() -> dict[str, Any]:
    return {
        "name": "DS_PROMETHEUS",
        "type": "datasource",
        "label": "Data Source",
        "query": "prometheus",
        "current": {"text": "", "value": "${DS_PROMETHEUS}", "selected": True},
        "refresh": 1,
        "hide": 0,
        "regex": "",
        "skipUrlSync": False,
    }


def query_var(name: str, definition: str, *, label: str | None = None,
              multi: bool = False, include_all: bool = False,
              all_value: str = ".*", hide: int = 0,
              regex: str = "") -> dict[str, Any]:
    return {
        "name": name,
        "type": "query",
        "label": label or name,
        "datasource": PROM_DS,
        "definition": definition,
        "query": {"qryType": 1, "query": definition,
                   "refId": f"PrometheusVariableQueryEditor-{name}"},
        "refresh": 1,
        "sort": 1,
        "multi": multi,
        "includeAll": include_all,
        "allValue": all_value if include_all else None,
        "regex": regex,
        "current": {},
        "hide": hide,
        "skipUrlSync": False,
    }


def custom_var(name: str, options: list[str], *, default: str | None = None,
               label: str | None = None, hide: int = 0) -> dict[str, Any]:
    default = default or options[0]
    return {
        "name": name,
        "type": "custom",
        "label": label or name,
        "query": ",".join(options),
        "options": [
            {"text": o, "value": o, "selected": o == default} for o in options
        ],
        "current": {"text": default, "value": default, "selected": True},
        "hide": hide,
        "skipUrlSync": False,
    }


def constant_var(name: str, value: str, *, label: str | None = None,
                 hide: int = 2) -> dict[str, Any]:
    return {
        "name": name,
        "type": "constant",
        "label": label or name,
        "query": value,
        "current": {"text": value, "value": value, "selected": False},
        "hide": hide,
        "skipUrlSync": False,
    }


@dataclass
class Target:
    expr: str
    legend: str = "__auto"
    ref: str = "A"
    instant: bool = False
    format: str = "time_series"

    def to_json(self) -> dict[str, Any]:
        return {
            "datasource": PROM_DS,
            "editorMode": "code",
            "expr": self.expr,
            "legendFormat": self.legend,
            "range": not self.instant,
            "instant": self.instant,
            "format": self.format,
            "refId": self.ref,
        }


@dataclass
class Panel:
    title: str
    type: str = "timeseries"
    targets: list[Target] = field(default_factory=list)
    grid: tuple[int, int, int, int] = (0, 0, 12, 8)  # x, y, w, h
    unit: str = "short"
    description: str = ""
    decimals: int | None = None
    min_value: float | None = None
    max_value: float | None = None
    transformations: list[dict[str, Any]] = field(default_factory=list)
    field_overrides: list[dict[str, Any]] = field(default_factory=list)
    options_override: dict[str, Any] = field(default_factory=dict)
    thresholds_steps: list[dict[str, Any]] | None = None


ROW_TYPE = "row"


def row(title: str, y: int, *, collapsed: bool = False,
        panels: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    return {
        "type": ROW_TYPE,
        "title": title,
        "collapsed": collapsed,
        "gridPos": {"x": 0, "y": y, "w": 24, "h": 1},
        "panels": panels or [],
    }


def legacy_link_panel(title: str, grid: tuple[int, int, int, int],
                      sql_dashboard: str, note: str = "") -> Panel:
    """Text panel that deep-links to the original SQL-backed dashboard.
    Used wherever a source panel cannot be represented against
    Prometheus-only metrics without new collectors."""
    body = (
        f"**Legacy panel** — not yet ported to Prometheus.\n\n"
        f"[Open in SQL dashboard: *{sql_dashboard}*](/d/{sql_dashboard})"
    )
    if note:
        body += f"\n\n_Note:_ {note}"
    return Panel(
        title=title, type="text", grid=grid, description=body,
        options_override={"mode": "markdown", "content": body},
    )
