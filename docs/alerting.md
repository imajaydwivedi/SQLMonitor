# Alerting

SQLMonitor ships with a standalone **Alert Engine** written in Python (Flask + APScheduler + Slack SDK + Waitress) that reads the inventory `DBA` database and fires alerts to Slack (primary), PagerDuty and email. It is completely independent of SQL Server's built-in Database Mail / `sp_send_dbmail` path &mdash; though you can still use those alongside if you wish.

## What the engine does

| | |
|---|---|
| **Source of truth** | The `Alerting/` folder in the repo &mdash; specifically `SQLMonitorAlertEngineApp.py` (the server) and `SmaAlerts/Alert-*.py` (one file per alert). |
| **Scheduler** | [APScheduler](https://apscheduler.readthedocs.io/) `BackgroundScheduler` &mdash; every alert runs on its own `frequency_minutes` cadence. |
| **Web surface** | Flask app on port **5000** (served by Waitress in production) &mdash; handles Slack interactivity (acknowledge / snooze buttons), health checks and manual triggers. |
| **State** | Active alerts, history and de-duplication keys live in `DBA.dbo.sma_alerts` on the inventory server (schema created by `Alerting/Deployment-Instructions/SCH-Create-Alert-Objects.sql`). |

## Built-in alerts

Each file in `Alerting/SmaAlerts/` is a self-contained alert that can be executed standalone or registered with the scheduler. There are 18 shipped alerts:

| Alert | Source | Fires when |
|---|---|---|
| `Alert-Cpu` | `all_server_volatile_info` | Host CPU % crosses configured warn/crit thresholds |
| `Alert-AvailableMemory` | `all_server_volatile_info` | Node available memory falls under threshold |
| `Alert-SqlMemory` | `all_server_volatile_info` | SQL Server target-vs-total memory discrepancy |
| `Alert-MemoryGrantsPending` | `all_server_volatile_info` | Pending memory grants > 0 for N minutes |
| `Alert-DiskSpace` | `disk_space_all_servers` | Free % or free GB below per-drive threshold |
| `Alert-DiskLatency` | perfmon | Avg Disk sec/Read or Write above threshold |
| `Alert-LogSpace` | `log_space_consumers_all_servers` | DB t-log % used > threshold |
| `Alert-Tempdb` | `tempdb_space_usage_all_servers` | Tempdb usage / version-store growth |
| `Alert-SqlBlocking` | `WhoIsActive` | Blocking chain persists > N seconds |
| `Alert-WaitsPerCorePerMinute` | `wait_stats` | Fleet-wide wait pressure |
| `Alert-AgLatency` | AG DMVs | Availability-Group redo/log-send lag |
| `Alert-AgDbBackupIssue` | `backups_all_servers` | AG database without a recent backup |
| `Alert-NonAgDbBackupIssue` | `backups_all_servers` | Standalone database without a recent backup |
| `Alert-OfflineServer` | `all_server_volatile_info` | Host has not reported in N minutes |
| `Alert-OfflineAgent` | `sql_agent_jobs_all_servers` | SQL Agent process down |
| `Alert-SqlMonitorJobs` | `sql_agent_jobs_all_servers` | A `(dba) *` job is failing repeatedly |
| `Alert-SqlMonitorDataCollection` | `all_server_collection_latency_info` | A collection is stale &mdash; dashboards will go red |
| `Alert-LoginExpiry` | `all_server_logins` | SQL Login password expiring soon |
| `Alert-NonSupportedServer` | `sma_sql_instance` | An instance below min supported SQL version joined inventory |

Each alert is independently tunable. Parameters live in `DBA.dbo.sma_parameters` (keyed by alert name) so you never edit Python to change a threshold.

## Deploying the Alert Engine

### Option 1 &mdash; Podman / Docker container (recommended)

The repo ships a `Dockerfile` that installs ODBC Driver 18, the Python dependencies from `requirements.txt`, and exposes port 5000.

```bash
cd ~/GitHub/SQLMonitor/Alerting

# Put the inventory SQL password in an env var (don't bake it into the image)
export MSSQLPASSWORD='<password for login on inventory SQL instance>'

podman build -t sqlmonitor-alert-engine .

podman run --replace -d --name sqlmonitor-alert-engine -p 5000:5000 \
  -e inventory_server='sqlmonitor' \
  -e login_password="$MSSQLPASSWORD" \
  sqlmonitor-alert-engine

curl http://localhost:5000/          # should return the health page
podman logs -f sqlmonitor-alert-engine
```

To autostart on boot (Podman on a systemd host):

```bash
podman generate systemd --name sqlmonitor-alert-engine --files --new
sudo mv container-sqlmonitor-alert-engine.service /etc/systemd/system/
sudo systemctl enable --now container-sqlmonitor-alert-engine
```

Full annotated flow is in [`Alerting/Deployment-Instructions/alertengine-on-podman.sh`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/Alerting/Deployment-Instructions/alertengine-on-podman.sh).

### Option 2 &mdash; Python venv on Windows/Linux

```powershell
cd E:\GitHub\SQLMonitor\Alerting
python -m venv AlertEngineVenv
AlertEngineVenv\Scripts\activate.bat
pip install -r requirements.txt
python SQLMonitorAlertEngineApp.py --inventory_server sqlmonitor --login_password '<pwd>'
```

On Linux install the ODBC driver first:

```bash
bash Alerting/Deployment-Instructions/install-ms-odbc-drivers-18-sqlserver.sh
pip install -r Alerting/requirements.txt
```

## Inventory-side objects

Run `Alerting/Deployment-Instructions/SCH-Create-Alert-Objects.sql` on the inventory server once. It creates:

- `dbo.sma_alerts` &mdash; the flat table of every alert instance (open & resolved)
- `dbo.sma_parameters` &mdash; per-alert thresholds, cadences, severity, owner team
- `dbo.usp_insert_sma_alert`, `usp_get_active_alert_by_key`, `usp_get_active_alert_by_state`, `usp_get_alert_by_id`, `usp_update_alert_slack_ts_value` &mdash; the CRUD surface the engine uses.

`DML-Populate-Inventory-Tables.sql` seeds the owner-team / on-call routing table.

## Slack & PagerDuty integration

The engine expects a Slack bot token in the **Credential Manager** (`DBA.dbo.sma_credential`):

| Credential name | Used for |
|---|---|
| `slack_bot_token` | `xoxb-*` token &mdash; posts messages, updates them on resolve, handles button clicks |
| `slack_signing_secret` | Verifies the incoming Slack event payloads |
| `pagerduty_integration_key` | Events API v2 key per service |
| `smtp_host`, `smtp_port`, `smtp_user`, `smtp_password` | Fallback e-mail |

Add credentials via the helper proc:

```sql
EXEC DBA.dbo.usp_set_sm_credential
    @credential_name = N'slack_bot_token',
    @credential_value = N'xoxb-...';
```

The engine reads them at startup through `SmaAlertPackage/CommonFunctions/get_sm_credential.py`.

## Operating the engine

| Endpoint | Purpose |
|---|---|
| `GET /` | Health page listing scheduled alerts and their next run |
| `POST /slack/events` | Receives Slack events (ack / snooze / resolve clicks) |
| `POST /slack/commands` | Slash-command entrypoint |
| `GET /run-alert?name=<AlertName>` | Manually trigger a single alert (useful for smoke tests) |

Logs go to `Alerting/Logs/(dba) SQLMonitorAlertEngineApp.log` by default; redirect to your log shipper if desired.

## Extending &mdash; writing your own alert

1. Copy any file in `Alerting/SmaAlerts/` (e.g. `Alert-Cpu.py`) and rename it `Alert-MyThing.py`.
2. Keep the same arg-parser skeleton &mdash; the engine passes all of these from config.
3. Replace the SQL query / threshold logic. Use the `SmaAlert` / `SmaCpuAlert` base classes in `SmaAlertPackage/AlertClasses/` for consistent formatting.
4. Add a row in `dbo.sma_parameters` with your alert name, cadence and thresholds.
5. Restart the engine &mdash; APScheduler will pick up the new alert on the next boot.

See [Alert-Cpu.py](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/Alerting/SmaAlerts/Alert-Cpu.py) as the canonical pattern.
