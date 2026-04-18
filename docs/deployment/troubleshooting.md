# Troubleshooting

Common errors during install, collection, or dashboarding &mdash; and what to do about them.

## Install-time

### `The term 'Invoke-DbaQuery' is not recognized`

The `dbatools` module wasn't importable in the runspace. Check `DbaToolsFolderPath` points at a folder whose layout is:

```text
DbaToolsFolderPath\
    <version>\
        dbatools.psd1
        dbatools.psm1
        ...
```

Try:

```powershell
Save-Module dbatools -Path 'D:\Downloads\dbatools' -Repository PSGallery
```

then pass `-DbaToolsFolderPath 'D:\Downloads\dbatools'`.

### `Access is denied` from PSRemoting

The wrapper can't reach the monitored host as `WindowsCredential`. Check, on the **host**:

```powershell
Enable-PSRemoting -Force -SkipNetworkProfileCheck
Set-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System `
    -Name LocalAccountTokenFilterPolicy -Value 1
```

…and on the **deployer**:

```powershell
Set-Item WSMAN:\Localhost\Client\TrustedHosts -Value 'MyHost.lab.com' -Concatenate -Force
```

If the host is cross-domain, pass a domain-qualified credential (`DOMAIN\svc_sqlmonitor`) or use CredSSP.

### `Linked server creation failed: Msg 15457`

Means you're creating a linked server with SQL auth but the target instance rejects the password. Re-check:

- `grafana` SID matches between inventory and monitored instance (step `56__GrafanaLogin` with `-DropCreatedLogin $true` to force-sync).
- `TrustServerCertificate` or a valid cert on the target &mdash; TLS 1.2+ is mandatory on modern Windows SQL clients.

### `Invalid column name 'X'` during `2__AllDatabaseObjects`

Schema drift from a partial previous run. Rerun step 2 with an elevated error level:

```powershell
-OnlySteps '2__AllDatabaseObjects' -Verbose -ReturnInlineErrorMessage $true
```

If a specific table is the culprit and you can afford to lose its data:

```sql
DROP TABLE dbo.<table_name>;
-- then re-run step 2
```

### `The XEvent session 'XEventMetrics' already exists`

Either drop and re-create or skip:

```sql
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = 'XEventMetrics')
    DROP EVENT SESSION XEventMetrics ON SERVER;
```

Then `-OnlySteps '3__XEventSession'`.

## Collection-time

### `(dba) Collect-PerfmonData` keeps failing

Step output usually includes one of:

- **`logman: The data collector set was not found.`** &mdash; run `-OnlySteps '11__SetupPerfmonDataCollector'` again. Confirm the collector exists: `logman query DBA` on the host.
- **`Access to the path '\\host\C$\SQLMonitor\Perfmon\*.blg' is denied`** &mdash; the SQL Agent proxy account lacks SMB read on `C$` of the host. Grant it via a local group or re-use an admin account.
- **`No .blg files found`** &mdash; the Perfmon data collector is stopped. Start it: `logman start DBA` on the host.

### `(dba) Collect-XEvents` inserts no rows

Check `.xel` files are being created:

```powershell
Get-ChildItem -Path 'C:\SQLMonitor\XEvents' -Filter '*.xel' | Select-Object Name, LastWriteTime
```

If files exist but the job inserts zero rows, the XEvent session might be started but not firing. Confirm:

```sql
SELECT name, startup_state FROM sys.server_event_sessions WHERE name = 'XEventMetrics';
SELECT * FROM sys.dm_xe_sessions WHERE name = 'XEventMetrics';   -- is it running?
```

Start it: `ALTER EVENT SESSION XEventMetrics ON SERVER STATE = START;`

### `(dba) Get-AllServerVolatileInfo` errors with `Login failed for user 'grafana'`

The `grafana` login SIDs don't match between inventory and the target. Re-run:

```powershell
-OnlySteps '56__GrafanaLogin' -DropCreatedLogin $true
```

## Dashboarding

### Grafana panels say "No data"

1. Test the data source: Grafana &rarr; Connections &rarr; Data sources &rarr; `SQLMonitor` &rarr; **Save & test**.
2. If the test passes, run a panel's SQL directly in SSMS with Grafana's variable values substituted. Most "No data" is a time-filter problem &mdash; the panel default `$__timeFilter` resolves to a window where your collection hasn't run yet.
3. Confirm collection: `SELECT MAX(collection_time) FROM DBA.dbo.all_server_volatile_info` &mdash; should be within the last 1&ndash;2 minutes.

### Grafana: "Error evaluating ..."

Usually means a required variable is empty. Open the variable editor (top of the dashboard) and ensure `$instance` (or the relevant variable) has a value. Some dashboards will not render when a `multi-value` variable is `All` &mdash; pick one instance.

### Dashboard is slow

Open `Monitoring - Live - Distributed` &rarr; Panel title &rarr; Inspect &rarr; Query. Copy the SQL to SSMS and `SET STATISTICS TIME, IO ON`. Common causes:

- Missing non-clustered index on `collection_time` + instance &mdash; `dbo.usp_enable_page_compression` also creates the expected indexes; re-run step 55.
- `all_server_volatile_info_history` hasn't been hourly-rolled-up. Run `(dba) Compute-AllServerVolatileInfoHistoryHourly` manually.
- 20+ concurrent dashboard viewers &mdash; SQLMonitor's dynamically-parameterized queries help but a dedicated read replica of inventory is the long-term answer.

## Alert Engine

### Engine starts but fires nothing

Check `Alerting/SQLMonitorAlertEngineApp.py` logs: likely `usp_get_active_alert_by_*` returns zero rows. Confirm:

```sql
SELECT * FROM dbo.alert_history WHERE collection_time > DATEADD(HOUR, -1, GETDATE());
SELECT * FROM dbo.sma_alerts WHERE state = 'active';
```

If `alert_history` is empty, the `(dba) Capture-AlertMessages` job isn't writing there &mdash; look at its history.

## Where to report a bug

If nothing here helps, open an issue: <https://github.com/imajaydwivedi/SQLMonitor/issues>. Include:

- `Install-SQLMonitor.ps1` output with `-Verbose -ReturnInlineErrorMessage $true`.
- SQL Server version: `SELECT @@VERSION`.
- Windows version of the deployer and host.
- `dbatools` version: `Get-Module dbatools -ListAvailable`.
