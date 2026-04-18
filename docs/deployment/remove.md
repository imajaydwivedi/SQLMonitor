# Remove SQLMonitor

`SQLMonitor/Remove-SQLMonitor.ps1` is the inverse of the installer. It removes an instance from SQLMonitor in the correct order &mdash; alerts &rarr; jobs &rarr; procs &rarr; views &rarr; tables &rarr; proxies &rarr; linked servers &rarr; inventory row.

## Quick uninstall

Copy the sample wrapper and run:

```powershell
Copy-Item .\Wrapper-Samples\Wrapper-RemoveSQLMonitor.ps1 .\Private\Wrapper-RemoveSQLMonitor.ps1
# Edit Private\Wrapper-RemoveSQLMonitor.ps1 to set SqlInstanceToBaseline / HostName / InventoryServer
.\Private\Wrapper-RemoveSQLMonitor.ps1 -Verbose
```

## What gets removed

The removal runs in this order to respect dependencies:

| Phase | Steps | What |
|---|---|---|
| 1 | `1__Remove_SQLAgentAlerts` | SQL Agent alerts for severities & specific error numbers |
| 2 | `2__*`&ndash;`30__RemoveJob_*` | All `(dba) *` SQL Agent jobs (both per-instance and inventory) |
| 3 | `31__*`&ndash;`68__DropProc_*` | All `dbo.usp_*` and helper procs |
| 4 | `69__*`&ndash;`75__DropView_*` | `vw_*` views and `sma_*` views |
| 5 | `77__DropXEvent_XEventMetrics` | The Extended Event session |
| 6 | `78__DropLinkedServer` | Linked server from inventory to this instance |
| 7 | `79__DropLogin_Grafana` | The `grafana` login *on this instance only* (leaves the inventory login alone) |
| 8 | `80__*`&ndash;`142__DropTable_*` | All `dbo.*` collection and inventory tables |
| 9 | `143__RemovePerfmonFilesFromDisk` | `.blg` files under `RemoteSQLMonitorPath` on the host |
| 10 | `144__RemoveXEventFilesFromDisk` | `.xel` files under `RemoteSQLMonitorPath` on the host |
| 11 | `145__DropProxy` | SQL Agent proxy |
| 12 | `146__DropCredential` | SQL credential |
| 13 | `147__RemoveInstanceFromInventory` | Delete the row from `dbo.sma_sql_instance` on inventory |

## Partial removal

Use `-OnlySteps`, `-SkipSteps`, `-StartAtStep`, `-StopAtStep` exactly as with the installer.

### Common recipes

```powershell
# Just decommission the jobs, keep the data
.\Remove-SQLMonitor.ps1 @commonArgs -StopAtStep '30__RemoveJob_StopStuckSQLMonitorJobs'

# Remove everything EXCEPT historical Blitz tables (keep the tuning history)
.\Remove-SQLMonitor.ps1 @commonArgs -SkipSteps '91__DropTable_Blitz','92__DropTable_BlitzWho','93__DropTable_BlitzCache','102__DropTable_BlitzIndex'

# Leave this instance in the inventory so the grafana UI still lists it as 'offline'
.\Remove-SQLMonitor.ps1 @commonArgs -SkipSteps '147__RemoveInstanceFromInventory'
```

## What does NOT get removed

Out of an abundance of caution the remove script leaves these alone:

- **The `DBA` database itself** &mdash; you may use it for other things. Drop it yourself with `DROP DATABASE DBA` if desired.
- **First-Responder-Kit / Darling-Data / Ola-Hallengren objects** &mdash; those were installed by name, not by SQLMonitor. Drop them via their own uninstall scripts if desired.
- **`sp_WhoIsActive`** &mdash; kept. Drop with `DROP PROC sp_WhoIsActive` if desired.
- **Database Mail profile & accounts** &mdash; kept.
- **Grafana dashboards** &mdash; delete via Grafana UI or API.
- **Anything under `C:\SQLMonitor\Private\`** &mdash; user-owned files are never touched.

## Removing the inventory server itself

If you want to tear down the **entire** SQLMonitor deployment (not just one monitored instance):

1. Run `Remove-SQLMonitor.ps1` against **every** monitored instance first, one at a time.
2. Then run it against the inventory server with `SqlInstanceToBaseline = $InventoryServer`. This drops the inventory-scoped jobs, procs and `all_server_*` tables.
3. Finally, drop the `DBA` database on the inventory if desired.

## Verifying removal

```sql
USE DBA;
SELECT name FROM sys.tables WHERE name LIKE 'performance_counters%';   -- should be empty
SELECT name FROM msdb.dbo.sysjobs WHERE name LIKE '(dba) %';           -- should be empty
SELECT name FROM sys.server_principals WHERE name = 'grafana';         -- should return 0 rows
```

On the inventory:

```sql
USE DBA;
SELECT sql_instance FROM dbo.sma_sql_instance WHERE sql_instance = 'MyInstance';  -- should be empty
```
