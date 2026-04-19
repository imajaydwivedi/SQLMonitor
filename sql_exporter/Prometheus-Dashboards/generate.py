#!/usr/bin/env python3
"""Generate all Prometheus-backed SQLMonitor Grafana dashboards.

Run from this folder:

    python3 generate.py            # regenerate every dashboard
    python3 generate.py core       # regenerate only the Core Metrics - Trend port

Each ``*.json`` written here is importable directly into Grafana via the
standard "New -> Import" dialog; Grafana will prompt you for the
Prometheus datasource to bind to the ``${DS_PROMETHEUS}`` placeholder.
"""
from __future__ import annotations

import importlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "_lib"))
sys.path.insert(0, str(ROOT / "_specs"))

from build import build_dashboard, write_dashboard  # noqa: E402


SPECS = [
    # (spec_module, output_filename)
    ("core_metrics_trend", "Core Metrics - Trend.json"),
    ("wait_stats", "Wait Stats.json"),
    ("disk_space", "Disk Space.json"),
    ("ag_health_state", "Ag Health State.json"),
    ("sql_agent_jobs", "SQL Agent Jobs.json"),
    ("backup_history", "Backup History.json"),
    ("xevent_trend", "XEvent - Trend.json"),
    ("database_file_io_stats", "Database File IO Stats.json"),
    ("dba_inventory", "DBA Inventory.json"),
    ("monitoring_live_all_servers",
     "Monitoring - Live - All Servers.json"),
    ("monitoring_live_distributed",
     "Monitoring - Live - Distributed.json"),
    ("monitoring_perfmon_quest",
     "Monitoring - Perfmon Counters - Quest Softwares - Distributed.json"),
]


def regenerate(filter_: str | None = None) -> list[Path]:
    out: list[Path] = []
    for mod_name, filename in SPECS:
        if filter_ and filter_ not in mod_name:
            continue
        spec = importlib.import_module(mod_name)
        dashboard = build_dashboard(
            uid=spec.UID,
            title=spec.TITLE,
            tags=spec.TAGS,
            variables=spec.variables(),
            panels=spec.panels(),
            description=getattr(spec, "DESCRIPTION", ""),
        )
        out.append(write_dashboard(ROOT, filename, dashboard))
    return out


if __name__ == "__main__":
    flt = sys.argv[1] if len(sys.argv) > 1 else None
    for p in regenerate(flt):
        print(f"wrote {p.relative_to(ROOT)}")
