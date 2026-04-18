# Install-SQLMonitor Parameters

Full reference for every parameter of `SQLMonitor/Install-SQLMonitor.ps1`. Parameter names and defaults are verified against the script header.

!!! tip "Authoritative source"
    The parameter block in [`Install-SQLMonitor.ps1`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/SQLMonitor/Install-SQLMonitor.ps1) is the source of truth. Re-check there for the most recent parameter list.

## Identity & placement

| Parameter | Required | Default | Purpose |
|---|---|---|---|
| `SqlInstanceToBaseline` | :material-check: | | The monitored SQL instance onto which SQLMonitor objects and jobs are installed. |
| `InventoryServer` | :material-check: | | SQL instance holding `all_server_*` tables. |
| `DbaToolsFolderPath` | :material-check: | | Path to the `dbatools` PowerShell module folder on the deployer (e.g. `D:\Downloads\dbatools\2.1.12\`). Used to import the module across PSRemoting sessions. |
| `InventoryDatabase` | | `DBA` | Database name on the inventory server. |
| `DbaDatabase` | | `DBA` | Name of the database created on the monitored instance. |
| `HostName` | | | Windows hostname of the monitored instance (PSRemoting target). Required for non-Managed-Instance installs. Must match the `SERVERPROPERTY('ComputerNamePhysicalNetBIOS')` of a non-clustered host or the physical node for an FCI/AG. |
| `SqlInstanceAsDataDestination` | | `$SqlInstanceToBaseline` | Where collection data is pushed. Set to a different instance to separate monitoring writes from the monitored instance. |
| `SqlInstanceForTsqlJobs` | | `$SqlInstanceToBaseline` | Where T-SQL SQL-Agent jobs are registered. |
| `SqlInstanceForPowershellJobs` | | `$SqlInstanceToBaseline` | Where PowerShell / CmdExec jobs are registered (Perfmon, disk space, OS processes). |
| `SQLMonitorPath` | | repo root | Path to this cloned SQLMonitor repo on the deployer. Auto-detected from the script location when not supplied. |
| `RemoteSQLMonitorPath` | | `C:\SQLMonitor` | Where collectors and Perfmon BLGs live on the monitored host. |
| `XEventDirectory` | | | Override folder for the XEvent session's file target. Default is under `RemoteSQLMonitorPath`. |

## Credentials & mail

| Parameter | Required | Default | Purpose |
|---|---|---|---|
| `SqlCredential` | | Current Windows identity | SQL credential used for CREATE LOGIN, CREATE DATABASE, job creation, etc. Omit to use integrated auth. |
| `WindowsCredential` | | Current Windows identity | Windows credential used for PSRemoting and wrapped by the SQL Agent proxy. |
| `DbaGroupMailId` | | | One or more email addresses that Database-Mail jobs send to (dashboard mail, login-expiry mail, stuck-job alerts). Can be a DL or comma-separated list. |

## Third-party kits

| Parameter | Default | Purpose |
|---|---|---|
| `FirstResponderKitZipFile` | | Path to the First-Responder-Kit zip. Expanded and scripts run against the `DBA` database in step `4__FirstResponderKitObjects`. |
| `DarlingDataZipFile` | | Path to the `DarlingData-main.zip` release. Used by step `5__DarlingDataObjects`. |
| `OlaHallengrenSolutionZipFile` | | Path to `sql-server-maintenance-solution-master.zip`. Used by step `6__OlaHallengrenSolutionObjects`. |

## Behavior toggles

| Parameter | Default | Purpose |
|---|---|---|
| `MemoryOptimizedObjectsUsage` | `$true` | Use Memory-Optimized tables for `all_server_volatile_info*`. Set `$false` on Standard Edition inventory servers. |
| `IsManagedInstance` | `$false` | Skip host-side steps (Perfmon, disk-space via Windows, OS processes). |
| `InstanceScopeFeaturesOnly` | `$false` | Install only per-instance collectors; skip all inventory-side jobs/tables. |
| `RetentionDays` | script default | Default retention. Overridable per-table via `dbo.purge_table`. |
| `JobsExecutionWaitTimeoutMinutes` | `5` | How long the installer waits for a newly-created job's first run to complete. |
| `DryRun` | `$false` | Print what would be done without making changes. |
| `PreQuery` / `PostQuery` | | Free-form T-SQL executed before/after the step sequence. |
| `ReturnInlineErrorMessage` | `$false` | Surface inner-exception messages verbatim for machine parsing. |
| `GrafanaDashboardPortal` | `https://sqlmonitor.ajaydwivedi.com:3000/` | Value stamped into the `dashboard_url` columns so dashboard emails point at the right Grafana. |

## Skip / force flags

Fine-grained flags to opt out of specific validations or re-run specific steps destructively.

| Parameter | Default | Purpose |
|---|---|---|
| `DropCreatePowerShellJobs` | `$false` | Drop & recreate PowerShell-subsystem jobs even if they exist. |
| `DropCreateWhoIsActiveTable` | `$false` | Drop & recreate `dbo.WhoIsActive` (wipes history). |
| `DropCreateLinkedServerOnInventory` | `$false` | Drop & recreate linked server on inventory. |
| `DropCreateLinkedServerForDataDestinationServer` | `$false` | Drop & recreate linked server for a non-local data-destination instance. |
| `SkipPowerShellJobs` | `$false` | Do not create PowerShell-subsystem jobs. |
| `SkipTsqlJobs` | `$false` | Do not create T-SQL jobs. |
| `SkipRDPSessionSteps` | `$false` | Do not attempt anything over PSRemoting (headless / locked-down hosts). |
| `SkipInventorySteps` | `$false` | Do not touch the inventory server. |
| `SkipMultiMailJobSteps` | `$true` | Do not create dashboard-mail jobs (kept off by default to avoid inbox floods). |
| `SkipMultiServerviewsUpgrade` | `$true` | Do not reshape multi-server views during upgrade. |
| `SkipWindowsAdminAccessTest` | `$false` | Skip the admin-rights precheck on the monitored host. |
| `SkipMailProfileCheck` | `$false` | Don't fail if Database Mail isn't configured on the inventory. |
| `SkipCollationCheck` | `$false` | Skip the collation match check between monitored and inventory instances. |
| `SkipPageCompression` | `$false` | Skip step `55__EnablePageCompression`. |
| `SkipDriveCheck` | `$false` | Skip drive-space pre-check. |
| `SkipPingCheck` | `$false` | Skip ICMP reachability check. |
| `HasCustomizedTsqlJobs` | `$false` | Declare that the target has customized T-SQL jobs you want preserved. |
| `HasCustomizedPowerShellJobs` | `$false` | Same for PowerShell jobs. |
| `OverrideCustomizedTsqlJobs` | `$false` | Overwrite customized T-SQL jobs anyway. |
| `OverrideCustomizedPowerShellJobs` | `$false` | Overwrite customized PowerShell jobs anyway. |
| `ForceTSQLStepType4TsqlJobs` | `$true` | Force job steps to run as T-SQL subsystem where applicable. |
| `ForceSetupOfTaskSchedulerJobs` | `$false` | Set up Windows Task Scheduler jobs in addition to SQL Agent jobs. |
| `ConfirmValidationOfMultiInstance` | `$false` | Required when onboarding an instance that has multiple SQL services on one host. |
| `ConfirmSetupOfTaskSchedulerJobs` | `$false` | Required confirmation flag when `ForceSetupOfTaskSchedulerJobs=$true`. |
| `UpdateSQLAgentJobsThreshold` | `$true` | Refresh `dbo.sql_agent_job_thresholds` with defaults for new jobs. |

## Step control

All four parameters below accept the same 59-value set. See [Install Steps](steps.md) for the full list.

| Parameter | Behavior |
|---|---|
| `OnlySteps` | Run **only** these steps (useful for partial re-runs). |
| `SkipSteps` | Run everything **except** these steps. |
| `StartAtStep` | Resume from this step (inclusive); skip everything before. |
| `StopAtStep` | Stop after this step (inclusive). |

Examples:

```powershell
# Just re-register the jobs
.\Install-SQLMonitor.ps1 @commonArgs -OnlySteps 'CreateJobCategory','CreateJobs'

# Resume a failed install from step 7
.\Install-SQLMonitor.ps1 @commonArgs -StartAtStep '7__PerfmonDataCollectorSet'

# Everything except the kits
.\Install-SQLMonitor.ps1 @commonArgs -SkipSteps 'FirstResponderKit','DarlingData','OlaHallengrenSolution'
```

## Parameter combinations by scenario

### Small lab / single server (Distributed, monitored = inventory)

```powershell
$commonArgs = @{
    SqlInstanceToBaseline        = 'Lab-01'
    HostName                     = 'Lab-01-VM'
    InventoryServer              = 'Lab-01'
    SqlInstanceAsDataDestination = 'Lab-01'
    SqlCredential                = $SqlCredential
    WindowsCredential            = $WindowsCredential
    DbaGroupMailId               = 'me@example.com'
    ...
}
```

### Fleet with dedicated inventory (Distributed)

```powershell
$commonArgs = @{
    SqlInstanceToBaseline        = 'Prod-Sales-01'
    HostName                     = 'Prod-Sales-01-VM'
    InventoryServer              = 'SQLMon-Inv-01'
    SqlInstanceAsDataDestination = 'Prod-Sales-01'
    ...
}
```

### Central topology (all jobs on inventory)

```powershell
$commonArgs = @{
    SqlInstanceToBaseline        = 'Prod-Sales-01'
    HostName                     = 'SQLMon-Inv-01-VM'          # host of the central collector
    InventoryServer              = 'SQLMon-Inv-01'
    SqlInstanceAsDataDestination = 'SQLMon-Inv-01'
    SqlInstanceForTsqlJobs       = 'SQLMon-Inv-01'
    SqlInstanceForPowershellJobs = 'SQLMon-Inv-01'
    ...
}
```

### Managed Instance / RDS (no host)

```powershell
$commonArgs = @{
    SqlInstanceToBaseline        = 'mi-prod-01.database.windows.net'
    InventoryServer              = 'SQLMon-Inv-01'
    IsManagedInstance            = $true
    SqlInstanceForPowershellJobs = 'SQLMon-Inv-01'  # host-side collectors run on inventory
    SkipSteps                    = @('7__PerfmonDataCollectorSet','8__SetupCollectorTask')
    ...
}
```
