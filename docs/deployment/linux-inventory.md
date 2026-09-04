# Linux Inventory Server

The inventory server runs on **SQL Server on Linux**. There is no Windows
inventory lane any more: `Install-SQLMonitor.ps1` still onboards *monitored*
instances, but the inventory half is installed by
[`SQLMonitor/linux/install-inventory.sh`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/SQLMonitor/linux/install-inventory.sh).

## Why this is a separate lane, not a flag

Three platform facts force the shape of this design. All are from
[Editions and supported features of SQL Server on Linux &rarr; Unsupported features and services](https://learn.microsoft.com/sql/linux/sql-server-linux-editions-and-components-2022#unsupported-features-and-services):

| Unsupported on Linux | What it broke | What replaced it |
|---|---|---|
| SQL Agent subsystems **CmdExec** and **PowerShell** | Every inventory job was a `CmdExec` step | T-SQL-only jobs stayed in SQL Agent on the `TSQL` subsystem; the rest became **systemd timers** |
| SQL Agent **Alerts** | `32__CreateSQLAgentAlerts` | Alerting is the [Python alert engine](../alerting.md)'s job on this lane |
| **Windows integrated authentication** for linked servers, and `xp_cmdshell` | `sqlcmd -E`, `@useself='True'` | SQL logins everywhere; secrets come from the Credential Manager |

A single "`-Platform Linux`" switch inside `Install-SQLMonitor.ps1` could not
express this: a third of the jobs stop being SQL Agent jobs at all.

## What runs where now

### Still SQL Agent jobs (subsystem `TSQL`)

These only ever wrapped a stored-procedure call in `sqlcmd -Q`, so they were
converted in place - same job names, same schedules, same procs:

`(dba) Get-AllServerStableInfo` &middot; `(dba) Get-AllServerVolatileInfo` &middot;
`(dba) Get-AllServerCollectionLatencyInfo` &middot; `(dba) Get-AllServerSqlAgentJobs` &middot;
`(dba) Get-AllServerDiskSpace` &middot; `(dba) Get-AllServerLogSpaceConsumers` &middot;
`(dba) Get-AllServerTempdbSpaceUsage` &middot; `(dba) Get-AllServerAgHealthState` &middot;
`(dba) Get-AllServerServices` &middot; `(dba) Get-AllServerBackups` &middot;
`(dba) Get-AllServerAlertHistory` &middot; `(dba) Get-AllServerDashboardMail` &middot;
`(dba) Compute-AllServerVolatileInfoHistoryHourly` &middot;
`(dba) Collect Login Expiration Info` &middot; `(dba) Send login expiry eMails`

!!! note "One behavioural change"
    These steps no longer pass `sqlcmd -H "<friendly name>"`, so
    `dbo.sma_errorlog.executor_program_name` now records the SQL Agent job step
    identity instead of `SQLCMD`. That is strictly more informative - the old
    `-H` value never matched the `HOST_NAME() like '(dba) Get-AllServerInfo%'`
    test in `dbo.usp_wrapper_GetAllServerInfo` anyway.

### Now systemd timers

These ran an external process, so they left SQL Agent entirely.

| Was (SQL Agent job) | Now (systemd timer) | Schedule | Script |
|---|---|---|---|
| `(dba) Check-InstanceAvailability` | `sqlmonitor-check-instance-availability.timer` | every 2 min | `check-instance-availability.sh` |
| `(dba) Update-SqlServerVersions` | `sqlmonitor-sqlserver-versions-update.timer` | Wed & Fri 00:00 | `sqlserver-versions-update.sh` |
| `(dba) Populate Inventory Tables` | `sqlmonitor-populate-inventory-tables.timer` | daily 09:00 | `populate-inventory-tables.sh` |
| `(dba) Stop-StuckSQLMonitorJobs` | `sqlmonitor-stop-stuck-sqlmonitor-jobs.timer` | hourly | `stop-stuck-sqlmonitor-jobs.sh` |
| `(dba) Update-SQLMonitorIP` | `sqlmonitor-update-sqlmonitor-ip.timer` | every 5 min, opt-in | `update-sqlmonitor-ip.sh` |
| `(dba) Collect-AllServerAlertMessages` | `sqlmonitor-collect-all-server-alert-messages.timer` | every 10 s | `collect-all-server-alert-messages.sh` |

The schedules are the ones the SQL Agent job definitions carried; each timer
file names the job it replaced.

## PowerShell &rarr; bash map

| Removed | Replacement |
|---|---|
| `check-instance-availability.ps1` | `linux/bin/check-instance-availability.sh` |
| `sqlserver-versions-update.ps1` | `linux/bin/sqlserver-versions-update.sh` |
| `Wrapper-GetHostIpAddresses.ps1` | `linux/bin/get-host-ip-addresses.sh` |
| `Stop-SQLMonitorJobs-On-AllServers-With-Issues.ps1` | `linux/bin/stop-stuck-sqlmonitor-jobs.sh` |
| `Update-SQLMonitorIP.ps1` | `linux/bin/update-sqlmonitor-ip.sh` |
| `loop-through-all-sqlmonitor-servers.ps1` | `linux/bin/run-on-all-servers.sh` |
| `Wrapper-UpdateSQLAgentJobsThreshold.ps1` (both the `SQLMonitor/` and `PowerShell-Scripts-Miscellaneous/` copies) | `linux/bin/update-sqlagent-jobs-threshold.sh` &mdash; the second copy's extra `threshold = -1` predicate is behind `--include-unset-thresholds` |
| `Wrapper-ChangeLoginPasswordAllServers.ps1` | `linux/bin/change-login-password-all-servers.sh` |
| `wrapper-collect_all_server_alert_messages.bat` | `linux/bin/collect-all-server-alert-messages.sh` |
| `wrapper-check-instance-availability.bat` | `linux/bin/check-instance-availability.sh` |
| (inventory half of) `Install-SQLMonitor.ps1` | `linux/install-inventory.sh` |
| (inventory half of) `Remove-SQLMonitor.ps1` | `linux/remove-inventory.sh` |

What dbatools provided - connections, credential lookup, error logging, bounded
parallelism - lives in `linux/lib/sqlmonitor.sh`. The only runtime dependencies
are `bash` 4.3+, `sqlcmd` (mssql-tools18), `curl` and coreutils.

## Prerequisites

1. SQL Server 2017 (14.x) or later on a supported Linux distribution, with the
   `DBA` database already created.
2. SQL Server Agent enabled:

    ```bash
    sudo /opt/mssql/bin/mssql-conf set sqlagent.enabled true
    sudo systemctl restart mssql-server
    ```

3. `mssql-tools18` installed - see
   [Install sqlcmd and bcp on Linux](https://learn.microsoft.com/sql/linux/sql-server-linux-setup-tools).
4. A SQL login for the inventory scripts (`INVENTORY_LOGIN`) with rights on
   `DBA` and `msdb`, and a fleet login (`ALL_SERVER_LOGIN`) whose password is
   stored in the [Credential Manager](https://github.com/imajaydwivedi/SQLMonitor/tree/dev/Credential-Manager).

## Install

```bash
git clone https://github.com/imajaydwivedi/SQLMonitor.git /usr/local/src/SQLMonitor
cd /usr/local/src/SQLMonitor/SQLMonitor/linux

# 1. Configure
sudo install -d -m 0750 /etc/sqlmonitor
sudo cp sqlmonitor-inventory.conf.sample /etc/sqlmonitor/inventory.conf
sudo vi /etc/sqlmonitor/inventory.conf
printf '%s' 'YourInventoryPassword' | sudo tee /etc/sqlmonitor/inventory.password >/dev/null
sudo chmod 0640 /etc/sqlmonitor/inventory.password

# 2. Look before you leap
sudo ./install-inventory.sh --dry-run --verbose

# 3. Install
sudo ./install-inventory.sh
```

The installer runs nine named steps and supports `--only` / `--skip`, the same
way `Install-SQLMonitor.ps1` supports `-OnlySteps` / `-SkipSteps`:

```bash
sudo ./install-inventory.sh --only agent-jobs,verify
sudo ./install-inventory.sh --skip systemd
```

Step `verify` fails loudly if any `(dba) SQLMonitor` job step is still on the
`CmdExec` or `PowerShell` subsystem, because such a step can never run on Linux.

## Linked servers

Create one linked server per monitored instance using
`DDLs/SCH-Linked-Servers-Sample-Linux.sql`. It differs from the Windows sample
in two ways that matter on Linux:

- the provider is `MSOLEDBSQL`, chosen from `SERVERPROPERTY('HostPlatform')`,
  because `SQLNCLI` is not registered on Linux;
- `remote proc transaction promotion` is off, because there is no MS DTC.

## Migrating an existing Windows inventory server

1. Back up and restore `DBA` onto the Linux instance (`WITH MOVE`; see
   [Migrate a database from Windows to Linux](https://learn.microsoft.com/sql/linux/migrate/restore-database)).
2. Run `DDLs/SCH-Drop-Inventory-CmdExec-Jobs.sql` there so the six external jobs
   do not linger and alert.
3. Run `install-inventory.sh`.
4. Recreate the linked servers with the `-Linux` sample.
5. Point Grafana's data source at the new instance.

`SCH-Create-Inventory-Specific-Objects.sql` changed in two ways that matter to
a migration:

- the MemoryOptimized filegroup file is derived from
  `SERVERPROPERTY('InstanceDefaultDataPath')` instead of the old hardcoded
  `E:\Data\MemoryOptimized.ndf`, so it lands in `/var/opt/mssql/data` without
  editing;
- the `dbo.tgr_dml__instance_details__prevent_bulk_udpate` trigger's escape
  hatch now keys on `HOST_NAME()` = `check-instance-availability.sh` rather than
  `PROGRAM_NAME()` = `check-instance-availability.ps1`. `PROGRAM_NAME()` is
  always `SQLCMD` for a sqlcmd connection, so without this the availability
  script could not flip `is_available` for more than five instances at once.

## Operating

```bash
# what is scheduled and when it next fires
systemctl list-timers 'sqlmonitor-*'

# run one task now, in the foreground
sudo -u sqlmonitor /opt/sqlmonitor/bin/check-instance-availability.sh --verbose

# logs
journalctl -u 'sqlmonitor@*' --since '1 hour ago'

# the errors the scripts recorded for the fleet
sqlcmd -S localhost -d DBA -C -Q "select top 50 * from dbo.sma_errorlog order by collection_time desc"
```

## Remove

```bash
sudo ./remove-inventory.sh                 # timers + jobs, files kept
sudo ./remove-inventory.sh --purge-files --purge-config --purge-user
```

The `DBA` database is never dropped by the remover.
