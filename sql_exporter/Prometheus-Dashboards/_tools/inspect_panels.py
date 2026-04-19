#!/usr/bin/env python3
"""Helper: list panels (title+type+grid) for a source dashboard JSON.
Usage: python3 inspect_panels.py <file.json>
"""
import json
import sys

def walk(panels, prefix=""):
    for p in panels:
        t = p.get("type", "?")
        title = p.get("title", "")
        g = p.get("gridPos", {})
        coord = f"({g.get('x',0)},{g.get('y',0)},{g.get('w',0)},{g.get('h',0)})"
        print(f"{prefix}[{t:10}] {coord:18} {title}")
        if p.get("panels"):
            walk(p["panels"], prefix + "  ")

d = json.load(open(sys.argv[1]))
walk(d.get("panels", []))
