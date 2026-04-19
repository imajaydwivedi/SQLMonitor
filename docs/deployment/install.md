# Install Walkthrough

End-to-end, first-time install of SQLMonitor on a single SQL Server instance.

> **Prerequisites not met?** See [Prerequisites](prerequisites.md) first.

## 1. Clone the repo

On your deployer machine:

```powershell
# Pick a permanent home
$repoRoot = 'C:\Code\GitHub'
git clone https://github.com/imajaydwivedi/SQLMonitor.git $repoRoot\SQLMonitor
cd $repoRoot\SQLMonitor
```

## 2. Copy the wrapper to `Private/`

`Wrapper-Samples/` contains sanitized wrappers. **Do not edit them in-place** &mdash; the `Private/` folder is in `.gitignore` so your secrets won't leak.

```powershell
New-Item -ItemType Directory -Path .\Private -Force | Out-Null
Copy-Item .\Wrapper-Samples\Wrapper-InstallSQLMonitor.ps1 .\Private\Wrapper-InstallSQLMonitor.ps1
```

## 3. Edit your wrapper

Open `Private\Wrapper-InstallSQLMonitor.ps1` and fill in:

```powershell
# --- Credentials ---
$SqlCredential       = Get-Credential -UserName 'sa'       -Message 'SA password'
$WindowsCredential   = Get-Credential -UserName 'DOMAIN\svc_sqlmonitor' -Message 'Domain svc acct'
$DbaGroupMailId      = 'dba@contoso.com'

# --- Topology ---
$SqlInstanceToBaseline        = 'DB-01'                    # the instance you are onboarding
$InventoryServer              = 'SQLMon-Inv-01'            # where all_server_* live
$HostName                     = 'DB-01-VM'                 # Windows host of the monitored instance
$SqlInstanceAsDataDestination = 'DB-01'                    # same instance = Distributed
$SqlInstanceForTsqlJobs       = 'DB-01'                    # default: same as monitored
$SqlInstanceForPowershellJobs = 'DB-01'                    # default: same as monitored

# --- 3rd-party zips (downloaded in step 0 of the wrapper) ---
$FirstResponderKitZipFile     = 'C:\Code\GitHub\SQLMonitor\BrentOzarULTD-SQL-Server-First-Responder-Kit-*.zip'
$DarlingDataZipFile           = 'C:\Code\GitHub\SQLMonitor\DarlingData-main.zip'
$OlaHallengrenSolutionZipFile = 'C:\Code\GitHub\SQLMonitor\sql-server-maintenance-solution-master.zip'
```

## 4. Dry-run first

Run the wrapper with `-WhatIf` style control by using `-OnlySteps 1__CreateDbaDatabase`:

```powershell
cd $repoRoot\SQLMonitor
.\Private\Wrapper-InstallSQLMonitor.ps1 `
    -OnlySteps '1__CreateDbaDatabase' `
    -Verbose
```

If this succeeds, database `DBA` exists on `DB-01`, the SQL recovery model & file sizes are set, and Query Store is turned on.

## 5. Run the full install

```powershell
.\Private\Wrapper-InstallSQLMonitor.ps1 -Verbose
```

You will see each step announce itself:

```text
[Start-Step]  1__CreateDbaDatabase
[Start-Step]  2__AllDatabaseObjects
[Start-Step]  3__FirstResponderKit
...
[Start-Step]  59__DartingData
[Install-SQLMonitor]  FINISHED in 00:12:43
```

First install on a modest instance takes **5&ndash;15 minutes**, most of which is the First-Responder-Kit / Darling-Data / Ola-Hallengren object deployment.

## 6. Verify

### On the monitored instance

```sql
USE DBA;
SELECT name FROM sys.tables WHERE name LIKE 'performance_counters%';   -- collection tables exist
SELECT TOP 10 collection_time, object_name, counter_name FROM dbo.performance_counters ORDER BY 1 DESC;
SELECT job_id, name, enabled FROM msdb.dbo.sysjobs WHERE name LIKE '(dba) %' ORDER BY name;
```

Expected: 40+ `(dba) *` jobs, enabled, owned by `sa`.

### On the inventory instance

```sql
USE DBA;
SELECT sql_instance, host_name, last_modified FROM dbo.sma_sql_instance ORDER BY sql_instance;
SELECT TOP 10 * FROM dbo.all_server_volatile_info;
```

After 5&ndash;10 minutes the `all_server_volatile_info` table should show one row per onboarded instance.

### In Grafana

1. Add / confirm data source:
    - Type: **Microsoft SQL Server**.
    - Name: **`SQLMonitor`** (exact).
    - Host: `<inventory-server>:1433`.
    - Database: `DBA`.
    - User / Password: `grafana` / `<password>`.
2. Import each JSON from `Grafana-Dashboards/` into a folder named `SQLMonitor`:
    - Grafana &rarr; Dashboards &rarr; Import &rarr; Upload JSON file &rarr; pick the `SQLMonitor` data source.
3. Open `Monitoring - Live - Distributed`. Within a minute or two of data collection, panels will populate.

## 7. Next steps

- Review [Install Steps](steps.md) to understand what the installer just did.
- If panels stay empty after 15 minutes, see [Troubleshooting](troubleshooting.md).
- Onboard more servers by changing `$SqlInstanceToBaseline` / `$HostName` and re-running. Or use `Wrapper-All-Servers-*` scripts for parallel multi-server onboarding.
- Set up [Alerting](../alerting.md) once you have a week of baseline data.

## Parallel multi-server install

For a fleet, use `Wrapper-Samples/Wrapper-All-Servers-*.ps1` with `PoshRSJob`. Copy one to `Private/`, edit the server list, run:

```powershell
.\Private\Wrapper-Install-SQLMonitor-Servers-Parallel.ps1 -Verbose
```

This parallelizes `Install-SQLMonitor.ps1` across instances (default 6 concurrent runspaces).
