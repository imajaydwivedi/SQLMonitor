#!/usr/bin/env python3
"""Validate every generated Prometheus dashboard JSON in this folder.

Checks:
  - parses as JSON
  - schemaVersion >= 41
  - contains a DS_PROMETHEUS datasource input
  - every non-row/non-text panel has >= 1 target with a non-empty expr
  - prints (uid, #panels total, #data panels, #rows, #text panels, #vars)
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def walk(panels):
    for p in panels:
        yield p
        if p.get("panels"):
            yield from walk(p["panels"])


def validate(path: str) -> bool:
    d = json.load(open(path))
    assert d.get("schemaVersion", 0) >= 41, f"{path}: schemaVersion too old"
    assert any(i["name"] == "DS_PROMETHEUS" for i in d.get("__inputs", [])), \
        f"{path}: missing DS_PROMETHEUS input"
    all_p = list(walk(d.get("panels", [])))
    rows = sum(1 for p in all_p if p.get("type") == "row")
    text = sum(1 for p in all_p if p.get("type") == "text")
    data = [p for p in all_p
            if p.get("type") not in ("row", "text", "dashlist")]
    for p in data:
        tgts = p.get("targets", [])
        if not tgts:
            print(f"  WARN {path}: panel '{p.get('title')}' has 0 targets")
            continue
        for t in tgts:
            if not t.get("expr", "").strip():
                print(f"  WARN {path}: panel '{p.get('title')}' "
                      f"target {t.get('refId')} has empty expr")
    vars_ = len(d.get("templating", {}).get("list", []))
    print(f"{os.path.basename(path):60s}  uid={d['uid']:40s}  "
          f"panels={len(all_p):3d}  data={len(data):3d}  rows={rows:2d}  "
          f"text={text:2d}  vars={vars_:2d}")
    return True


if __name__ == "__main__":
    files = sorted(f for f in os.listdir(ROOT) if f.endswith(".json"))
    ok = True
    for f in files:
        try:
            validate(os.path.join(ROOT, f))
        except Exception as e:
            print(f"FAIL {f}: {e}")
            ok = False
    sys.exit(0 if ok else 1)
