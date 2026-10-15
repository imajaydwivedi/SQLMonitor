# SQLMonitor Alert Engine

The Alert Engine is the alerting component of SQLMonitor. It evaluates health data collected from every SQL Server into the central `DBA` database, raises alerts, tracks their lifecycle in SQL tables, and notifies owning teams through Slack (with interactive buttons) or email. PagerDuty is planned but not implemented.

Source: `Alerting/` in the SQLMonitor repository.

---

## 1. Components

| Path | Role |
|---|---|
| `SQLMonitorAlertEngineApp.py` | Flask web server (Waitress) plus an APScheduler `BackgroundScheduler`. Receives Slack and Grafana actions and launches alert scripts on a schedule. |
| `SmaAlerts/Alert-*.py` | One script per alert (19 scripts). Each queries metrics, decides the alert action, and writes to and notifies from the database. |
| `SmaAlertPackage/AlertClasses/` | `SmaAlert` base class (mirrors `dbo.sma_alert`) and per-alert subclasses (for example `SmaCpuAlert`) that hold thresholds, severity rules, and message formats. |
| `SmaAlertPackage/CustomFunctions/` | One query function per alert (for example `get_cpu.py`). |
| `SmaAlertPackage/CommonFunctions/` | Shared helpers: DB connection, `sma_params` lookup, credential lookup, Slack and email senders, pretty-printing. |
| `Deployment-Instructions/SCH-*.sql` | Stored procedures for alert storage and retrieval. |
| `Dockerfile`, `alertengine-on-podman.sh` | Container packaging (Python 3.12-slim with MS ODBC Driver 18). |
| `requirements.txt` | Pinned Python dependencies. |

---

## 2. Runtime model

### 2.1 Scheduler tiers

`SQLMonitorAlertEngineApp.py` registers three interval jobs. Each job runs its scripts sequentially as separate `python` subprocesses, so a failure in one alert is logged and does not stop the others.

| Interval | Scripts |
|---|---|
| Every 1 min | `auto_resolve_cleared_alerts()` (in-process), `Alert-MemoryGrantsPending`, `Alert-OfflineAgent`, `Alert-OfflineServer`, `Alert-LogSpace`, `Alert-Tempdb` |
| Every 2 min | `Alert-Cpu`, `Alert-SqlBlocking`, `Alert-AvailableMemory`, `Alert-DiskLatency`, `Alert-AgLatency` |
| Every 5 min | `Alert-DiskSpace`, `Alert-SqlMonitorJobs`, `Alert-NonAgDbBackupIssue`, `Alert-AgDbBackupIssue` |

Five scripts are not referenced by the scheduler or by any wrapper in the repository: `Alert-SqlMemory`, `Alert-LoginExpiry`, `Alert-NonSupportedServer`, `Alert-WaitsPerCorePerMinute`, `Alert-SqlMonitorDataCollection`. They are either dormant or run manually. Confirm before relying on them.

### 2.2 Process boundaries

- Each alert script connects to the inventory server (`DBA` database) on its own and reads its arguments from the parent's `script_arguments` list.
- Each script writes its own log file under `Logs/`, named after its `alert_job_name`.
- The web server is one process running the scheduler in a background thread. The Dockerfile runs a single process. If the web server is run with multiple workers, each worker starts its own scheduler, which causes duplicate alerts (see §8).

### 2.3 Configuration

Every setting can come from a command-line argument or an environment variable of the same name. The environment variable wins. Key settings:

| Setting | Default | Meaning |
|---|---|---|
| `inventory_server` / `inventory_database` | `localhost` / `DBA` | Where alert state lives |
| `credential_manager_database` | `DBA` | Database holding `usp_get_credential` |
| `frequency_multiplier` | `4` | Auto-resolve threshold = multiplier × alert `frequency_minutes` |
| `run_scheduled_jobs` | `True` | Whether this process runs the scheduler |
| `use_waitress_server` | `True` | Waitress (production) vs. Flask dev server |
| `has_ssl_certificate` | `True` | Look for `Private/ssl_certificates/` (dev server only) |

Runtime thresholds and routing are stored in the database, not in code:

- `dbo.sma_params`: Slack bot name, channel ID, Grafana dashboard URLs, SMTP settings, and the Credential Manager database name.
- `dbo.sma_oncall_teams`: per-team alert method (`slack`, `email`, or `pagerduty`), email address, and Slack channel.
- `dbo.sma_servers`: which servers are onboarded and not decommissioned. Alert queries filter on this table.

---

## 3. Alert lifecycle

### 3.1 States

`Active` → `Acknowledged` / `Suppressed` / `Cleared` → `Resolved`

- **Active:** the condition is true and the alert is open.
- **Acknowledged:** a person has taken ownership. Notifications continue.
- **Suppressed:** notifications are muted for a window (`suppress_start_date_utc` to `suppress_end_date_utc`, default one hour).
- **Cleared:** the condition is no longer true. Auto-resolve moves the alert to `Resolved` after the grace period.
- **Resolved:** terminal. A new condition creates a new alert.

### 3.2 Actions

Each alert run computes one action from two flags: whether the alert already exists (`exists`) and whether the condition is currently true (`generate_alert`).

| `exists` | `generate_alert` | Action |
|---|---|---|
| False | False | No Action |
| False | True | **Create**: insert a row, post the message |
| True | False | **Clear**: mark Cleared and notify (skipped if already Cleared) |
| True | True | **Update**: post an update |
| True | True, severity increased | **Upgrade**: raise severity and re-notify |
| True | True, inside suppress window | **SkipNotification** |
| Cleared | True | **UnClear**: back to Active |

### 3.3 Deduplication

`dbo.usp_insert_sma_alert` checks for an existing row with the same `alert_key` in an open state (`Active`, `Acknowledged`, `Suppressed`, `Cleared`). If one exists, it reuses it and sets `@is_pre_existing_OUTPUT = 1`. A repeated detection therefore never creates a second row.

### 3.4 Auto-resolve

`auto_resolve_cleared_alerts()` runs every minute. It calls `usp_get_active_alert_by_state_severity` for alerts in `Cleared` state and resolves an alert only when:

```
minutes_since_last_log >= frequency_minutes × frequency_multiplier
```

The grace period prevents flapping when a metric oscillates around its threshold.

---

## 4. Data flow for a single alert (CPU)

1. `Alert-Cpu.py` loads thresholds from `SmaCpuAlert` defaults (warning 45%, critical 70%, 5-minute average).
2. `get_cpu()` queries `dbo.all_server_volatile_info_history` for servers that are onboarded and not decommissioned, averages `os_cpu` and `sql_cpu` over the window, and returns servers at or above the warning threshold.
3. `SmaCpuAlert.initialize_derived_attributes()` computes severity (Critical if any server is critical, otherwise High for warnings), the Slack header, the description table, and the Grafana link.
4. `SmaAlert.take_required_action()` calls `usp_insert_sma_alert`. For a `Create`, it then posts the Slack message and writes the returned Slack timestamp back with `usp_update_alert_slack_ts_value`.

---

## 5. Slack integration

- **First message:** a one-line summary with two buttons, **Acknowledge** and **Clear**. Each button's `action_id` is `<Action>-<alert_id>`, so the handler can recover the ID.
- **Threading:** the Slack message timestamp (`slack_ts_value`) is stored. Later updates post into the same thread.
- **Callback endpoint:** `POST /slack/interactive-endpoint` parses the payload, loads the alert, and calls `take_required_action()`.
- **Slash command:** `/alerts` acknowledges the command in the channel. It does not return data yet.
- **Events:** the `app_mention` handler replies to greetings.

---

## 6. HTTP endpoints

| Method | Path | Purpose |
|---|---|---|
| GET/POST | `/` | Redirects to the Grafana alerts dashboard |
| GET/POST | `/verify` | Health check (`{"health": "server is up and running"}`) |
| GET/POST | `/slack/events` | Slack Events API (via `slackeventsapi`) |
| GET/POST | `/alerts` | Slack slash command |
| POST | `/slack/interactive-endpoint` | Slack button callbacks |
| GET | `/alert/take_action` | Action from Grafana links. Query parameters: `app_name`, `user_name`, `alert_id`, `alert_key`, `action_to_take` (plus `remarks` for `Update`) |

**Security note:** `/alert/take_action` does not verify the caller. `user_name` is taken from the query string, and the only check is that it is not `guest`. Anyone who can reach the port can change alert state under any name. See §8.

---

## 7. Deployment

### Container (Podman or Docker)

```bash
# Image built from Alerting/Dockerfile
# Runs: python SQLMonitorAlertEngineApp.py  (port 5000)
```

The image installs `unixodbc`, `msodbcsql18`, and the Python requirements. Settings are passed as environment variables; see `Deployment-Instructions/alertengine-on-podman.sh`.

### Windows

- `Deployment-Instructions/requirements_windows.txt` for dependencies.
- `Wrapper-Samples/Wrapper-SQLMonitorAlertEngineApp.ps1` (in the repository root) for launching the engine.
- Running from PowerShell logs to the console. A service or other parent process logs to `Logs/<alert_job_name>.log`.

### Database

Run the scripts in `Deployment-Instructions/` in the `DBA` database. `SCH-Create-Alert-Objects.sql` is the main one. Each procedure file contains a `stub` version that is replaced on execution, so the scripts are safe to re-run.

---

## 8. Known issues

Ordered by risk.

1. **Unauthenticated action endpoint.** `/alert/take_action` trusts the `user_name` query parameter. Fix: require a signed token, or use the Slack request-signature check that the code already imports.
2. **Password exposure.** `--login_password` is passed as a `subprocess` argument, so it appears in process listings. Verbose mode also prints `login_password`. Fix: pass secrets through environment variables or stdin, and never print them.
3. **Boolean command-line flags are broken.** `type=bool` in argparse means `--has_ssl_certificate False` evaluates to `True`, because `bool("False")` is truthy. This affects 8 flags. Fix: `action="store_true"` or an explicit string-to-bool parser.
4. **PagerDuty key is set from the wrong field.** `SmaAlert.py` line 175 assigns `team_slack_channel` to the PagerDuty service key. PagerDuty sending is also an empty stub.
5. **Duplicate schedulers under multiple workers.** Running more than one Waitress worker starts more than one scheduler and sends duplicate alerts. Fix: move scheduling to a separate process, or add a distributed lock.
6. **Repeated code.** The scheduler functions repeat the same try/subprocess/except block for every script. A loop over script names would remove most of it.
7. **Unscheduled scripts.** Five alert scripts (see §2.1) have no caller. Either schedule them, or delete them to avoid confusion.
8. **No test suite.** `test_flask_app.py` is a small mock server, not a test suite. The alert logic has no automated tests.
9. **Dated dependencies.** `requests==2.25.1` is old and has known CVEs. Upgrade it.

---

## 9. Changelog highlights

From the Alerting git history (`git log -- Alerting`, 59 commits, 2024-11-12 to 2025-11-16):

- **2024-11-12 to 2024-11-25** — Initial commit, then the Flask web server: Waitress, logging, scheduler, Slack challenge handling, the `/alert/take_action` endpoint for Grafana, and a first attempt at a Windows service.
- **2024-12-02 to 2024-12-31** — Encrypted connections, Ubuntu requirements, Podman deployment, and the reorganization into `SmaAlertPackage` (`AlertClasses`, `CustomFunctions`, `CommonFunctions`).
- **2025-01-20 to 2025-03-22** — Podman command helpers, then connection pooling.
- **2025-10-29 to 2025-10-30** — AG failover functionality.
- **2025-11-16** — Solution file added (latest commit).
