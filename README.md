# SQLMonitor

**Open-source SQL Server monitoring & alerting &mdash; built on SQL Agent jobs, Grafana, Prometheus and Python.**

[![Live Demo](https://img.shields.io/badge/live%20demo-sqlmonitor.ajaydwivedi.com-brightgreen)](https://sqlmonitor.ajaydwivedi.com)
[![Docs](https://img.shields.io/badge/docs-GitHub%20Pages-blue)](https://imajaydwivedi.github.io/SQLMonitor/)
[![YouTube](https://img.shields.io/badge/YouTube-tutorials-red)](https://ajaydwivedi.com/youtube/sqlmonitor)
[![Slack](https://img.shields.io/badge/Slack-%23sqlmonitor-purple)](https://ajaydwivedi.com/sqlmonitor/slack)

> Replace expensive enterprise monitoring with something you can install on a single inventory server, point at the rest of your fleet, and open in Grafana ten minutes later &mdash; from DEV all the way through PROD.

📖 **Full documentation:** <https://imajaydwivedi.github.io/SQLMonitor/>

---

## Live Demo

| | |
|---|---|
| 🔗 Grafana | <https://sqlmonitor.ajaydwivedi.com> |
| 👤 Login | `guest` / `ajaydwivedi-guest` |
| 💾 SQL | `sqlmonitor.ajaydwivedi.com:1433`  &mdash; user `grafana` / `grafana` (read-only on `DBA`) |

[![YouTube Tutorial](https://github.com/imajaydwivedi/Images/blob/master/SQLMonitor/YouTube-Thumbnail-Live-All-Servers.png)](https://ajaydwivedi.com/youtube/sqlmonitor)

![Live Dashboards](https://github.com/imajaydwivedi/Images/blob/master/SQLMonitor/Live-Dashboards-All.gif)

---

## What you get

- **17 Grafana dashboards** &mdash; distributed live, per-instance deep-dive, Blitz-family diagnostics, AG health, backups, disk, wait stats, workload.
- **46 SQL Agent jobs** in one `(dba) SQLMonitor` category &mdash; polling DMVs, OS, WMI, XEvents, Perfmon on every instance.
- **One central `DBA` database** on an inventory server aggregates the fleet via linked servers and fans it out to Grafana.
- **Python alert engine** with Slack, PagerDuty and email routing &mdash; 18 built-in alerts, all threshold-tunable without touching code.
- **Prometheus path** via [`sql_exporter`](https://github.com/burningalchemist/sql_exporter) + `windows_exporter` for shops that prefer pull-based metrics.
- **AI Agent** (Streamlit + LangChain + Ollama) that answers natural-language questions against the inventory.
- **First-Responder-Kit, Darling-Data, Ola-Hallengren, sp_WhoIsActive** installed and scheduled by default &mdash; so the diagnostic tooling is already there when you need it.

![Alert Engine](https://github.com/imajaydwivedi/Images/blob/master/SQLMonitor-AlertEngine/Sma-Slack-3-Images-Gif.gif)

---

## Quick install

Minimal happy-path (see the [full deployment guide](https://imajaydwivedi.github.io/SQLMonitor/deployment/) for prerequisites, parameters and troubleshooting).

### 1. Inventory server &mdash; SQL Server on Linux

The inventory server runs on Linux, where SQL Agent has no `CmdExec` or
`PowerShell` subsystem. Its jobs are either `TSQL` Agent jobs or systemd timers,
and it is installed with bash, not PowerShell
([full guide](https://imajaydwivedi.github.io/SQLMonitor/deployment/linux-inventory/)):

```bash
git clone https://github.com/imajaydwivedi/SQLMonitor.git /usr/local/src/SQLMonitor
cd /usr/local/src/SQLMonitor/SQLMonitor/linux

sudo install -d -m 0750 /etc/sqlmonitor
sudo cp sqlmonitor-inventory.conf.sample /etc/sqlmonitor/inventory.conf
sudo vi /etc/sqlmonitor/inventory.conf

sudo ./install-inventory.sh --dry-run --verbose   # look first
sudo ./install-inventory.sh
```

### 2. Monitored instances &mdash; Windows

```powershell
# 1. Clone onto the deployer box
git clone https://github.com/imajaydwivedi/SQLMonitor.git C:\SQLMonitor
cd C:\SQLMonitor\SQLMonitor

# 2. Copy the wrapper template and edit it (credentials, instance name, host)
Copy-Item .\Wrapper-Samples\Wrapper-InstallSQLMonitor.ps1 .\Private\Wrapper-InstallSQLMonitor.ps1
notepad .\Private\Wrapper-InstallSQLMonitor.ps1

# 3. Run it
.\Private\Wrapper-InstallSQLMonitor.ps1 -Verbose
```

Install Grafana, import the JSON dashboards from `Grafana-Dashboards/`, point them at the inventory SQL datasource &mdash; done.

Removing an instance is the exact inverse:

```powershell
Copy-Item .\Wrapper-Samples\Wrapper-RemoveSQLMonitor.ps1 .\Private\Wrapper-RemoveSQLMonitor.ps1
.\Private\Wrapper-RemoveSQLMonitor.ps1 -Verbose
```

---

## Documentation

Everything lives on the docs site &mdash; <https://imajaydwivedi.github.io/SQLMonitor/>. Quick index:

| Section | What you'll find |
|---|---|
| [Architecture](https://imajaydwivedi.github.io/SQLMonitor/architecture/) | Topology, data flow, components, data model |
| [Deployment](https://imajaydwivedi.github.io/SQLMonitor/deployment/) | Prerequisites, installer walkthrough, parameter reference, 59 install steps, upgrade, removal, troubleshooting |
| [Dashboards](https://imajaydwivedi.github.io/SQLMonitor/dashboards/) | Catalog of all 17 Grafana dashboards, live-demo links, Grafana variable conventions |
| [Jobs & Collectors](https://imajaydwivedi.github.io/SQLMonitor/jobs/) | Authoritative list of all 46 SQL Agent jobs with schedules and source links |
| [Alerting](https://imajaydwivedi.github.io/SQLMonitor/alerting/) | The Python Alert Engine, 18 built-in alerts, Slack/PagerDuty wiring |
| [Prometheus path](https://imajaydwivedi.github.io/SQLMonitor/prometheus/) | `sql_exporter` setup, collector files, migration from Perfmon |
| [AI Agent](https://imajaydwivedi.github.io/SQLMonitor/ai-agent/) | Streamlit + LangChain + Ollama agent over the inventory |
| [Support & FAQ](https://imajaydwivedi.github.io/SQLMonitor/support/) | Getting help, filing bugs, common questions |

---

## Support

- **Community:** [`#sqlmonitor`](https://ajaydwivedi.com/sqlmonitor/slack) on [sqlcommunity.slack.com](https://ajaydwivedi.com/join/slack)
- **Bugs:** [GitHub Issues](https://github.com/imajaydwivedi/SQLMonitor/issues)
- **Paid / private:** DM on Slack, or via <https://ajaydwivedi.com/contact>

## Related links

- GitHub: <https://github.com/imajaydwivedi/SQLMonitor>
- Live demo: <https://sqlmonitor.ajaydwivedi.com>
- YouTube playlist: <https://ajaydwivedi.com/youtube/sqlmonitor>
- Blog posts: <https://ajaydwivedi.com/category/sqlmonitor>

---

Thanks :smiley:. Subscribe for updates :thumbsup:
