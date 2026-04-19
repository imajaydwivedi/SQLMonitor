#!/usr/bin/env python3
"""
pastetheplan-proxy.py  –  Grafana → PasteThePlan local bridge (Python stdlib only)

Usage
-----
    cd sql_exporter
    python3 pastetheplan-proxy.py                          # port 8080, Prometheus on 9090
    python3 pastetheplan-proxy.py 8080 http://prom:9090   # custom port / Prometheus URL

Grafana data link (set on the query_plan column override in both table panels):
    http://localhost:8080/pastetheplan-bridge.html?key=${__data.fields.unique_key}&server=${Server}

How it works
------------
1. Grafana opens the URL above in a new browser tab.
   Only the tiny unique_key value is passed — no large/newline-containing XML in the URL.
2. THIS server queries the Prometheus instant-query API server-side:
       mssql_whoisactive__start_time{unique_key="<key>", instance="<server>"}
3. It reads the "query_plan" label from the returned metric.
4. It POSTs {"queryplan_xml": "<xml>"} to the PasteThePlan AWS Lambda API (no CORS).
5. It 302-redirects the browser to https://www.brentozar.com/pastetheplan/?id=<id>
"""

import html as _html_escape
import http.server
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

PORT        = int(sys.argv[1])  if len(sys.argv) > 1 else 8080
PROM_URL    = sys.argv[2].rstrip("/") if len(sys.argv) > 2 else "http://localhost:9090"

# Current PasteThePlan API endpoint (updated 2026-04; old jeczi7iqj8 endpoint is dead)
PTP_API    = "https://i7is2wx2pd.execute-api.us-west-2.amazonaws.com/id"
PTP_VIEWER = "https://www.brentozar.com/pastetheplan/?id="

HANDLED_PATHS = {"/pastetheplan-bridge.html", "/pastetheplan-bridge", "/"}


class PTPHandler(http.server.BaseHTTPRequestHandler):

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)

        if parsed.path not in HANDLED_PATHS:
            self._html(404, "<h2>404 – Not Found</h2>"
                       "<p>Use <code>/pastetheplan-bridge.html"
                       "?key=&lt;unique_key&gt;&amp;server=&lt;instance&gt;</code></p>")
            return

        params = urllib.parse.parse_qs(parsed.query, keep_blank_values=True)
        key    = (params.get("key")    or [""])[0].strip()
        server = (params.get("server") or [""])[0].strip()

        if not key:
            self._html(400, "<h2>Missing parameter</h2>"
                       "<p><code>key</code> (unique_key) is required.</p>")
            return

        # ------------------------------------------------------------------
        # 1. Fetch query_plan XML from Prometheus (server-side, no CORS,
        #    no URL-size / newline-in-URL problems).
        # ------------------------------------------------------------------
        # Use last_over_time([24h]) so the query succeeds even after a session
        # ends and its time series becomes stale (Prometheus default staleness
        # window is only 5 minutes for instant queries).
        selector = f'mssql_whoisactive__start_time{{unique_key="{key}"'
        if server:
            selector += f',instance="{server}"'
        selector += "}"
        promql       = f"last_over_time({selector}[24h])"
        prom_req_url = (PROM_URL + "/api/v1/query?query="
                        + urllib.parse.quote(promql, safe=""))
        print(f"[PTP proxy] Querying Prometheus: {prom_req_url}")

        try:
            with urllib.request.urlopen(prom_req_url, timeout=10) as r:
                prom_data = json.loads(r.read().decode("utf-8"))
        except Exception as exc:
            self._html(502, "<h2>Could not reach Prometheus</h2>"
                       "<p>" + str(exc) + "</p>"
                       "<p>Is Prometheus running at <code>" + PROM_URL + "</code>?</p>")
            return

        results = prom_data.get("data", {}).get("result", [])
        if not results:
            self._html(404, "<h2>No data found in Prometheus</h2>"
                       "<p>No metric for <code>unique_key=" + _html_escape.escape(key)
                       + "</code> within the last 24 hours.</p>"
                       "<p>PromQL used: <code>" + _html_escape.escape(promql) + "</code></p>"
                       "<p>Is the proxy pointing at the right Prometheus? "
                       "Current: <code>" + PROM_URL + "</code><br>"
                       "Override: <code>python3 pastetheplan-proxy.py 8080 http://&lt;prom-host&gt;:&lt;port&gt;</code></p>")
            return

        xml = results[0].get("metric", {}).get("query_plan", "").strip()
        if not xml:
            self._html(400, "<h2>No query plan for this session</h2>"
                       "<p>The <code>query_plan</code> label is empty — "
                       "this session had no execution plan at collection time.</p>")
            return

        print(f"[PTP proxy] Got query_plan: {len(xml):,} chars")

        # ------------------------------------------------------------------
        # 2. POST the XML to PasteThePlan (server-side, no CORS).
        # ------------------------------------------------------------------
        try:
            body = json.dumps({"queryplan_xml": xml}).encode("utf-8")
            req  = urllib.request.Request(PTP_API, data=body,
                                          headers={"Content-Type": "application/json"},
                                          method="POST")
            with urllib.request.urlopen(req, timeout=20) as resp:
                result = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            err_body = ""
            try:
                err_body = exc.read().decode("utf-8", errors="replace")
            except Exception:
                pass
            self._html(502, "<h2>PasteThePlan API error (HTTP " + str(exc.code) + ")</h2>"
                       "<p>" + str(exc.reason) + "</p><pre>" + err_body + "</pre>")
            return
        except urllib.error.URLError as exc:
            self._html(502, "<h2>Could not reach PasteThePlan API</h2>"
                       "<p>" + str(exc.reason) + "</p>")
            return
        except Exception as exc:
            self._html(500, "<h2>Unexpected error</h2><p>" + str(exc) + "</p>")
            return

        if result.get("error"):
            preview = _html_escape.escape((xml[:600] + " …") if len(xml) > 600 else xml)
            self._html(400, "<h2>PasteThePlan rejected the plan</h2>"
                       "<p>" + str(result.get("message", "")) + "</p>"
                       "<pre style='background:#f5f5f5;padding:1rem;overflow:auto'>"
                       + preview + "</pre>")
            return

        plan_id = result.get("id")
        if not plan_id:
            self._html(502, "<h2>Unexpected API response (no id)</h2>"
                       "<pre>" + json.dumps(result, indent=2) + "</pre>")
            return

        location = PTP_VIEWER + urllib.parse.quote(str(plan_id), safe="")
        print(f"[PTP proxy] Redirecting → {location}")
        self.send_response(302)
        self.send_header("Location", location)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _html(self, code, body_html):
        page = (
            "<!DOCTYPE html><html><head><meta charset='utf-8'>"
            "<title>PasteThePlan Proxy</title>"
            "<style>body{font-family:sans-serif;margin:2rem;color:#333}"
            "h2{color:#c00}</style></head>"
            "<body>" + body_html + "</body></html>"
        )
        enc = page.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(enc)))
        self.end_headers()
        self.wfile.write(enc)

    def log_message(self, fmt, *args):   # suppress default stderr noise
        print(f"[PTP proxy] {self.address_string()} – {fmt % args}")


if __name__ == "__main__":
    server = http.server.HTTPServer(("localhost", PORT), PTPHandler)
    print(f"PasteThePlan proxy  →  http://localhost:{PORT}/pastetheplan-bridge.html")
    print("Press Ctrl+C to stop.\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")

