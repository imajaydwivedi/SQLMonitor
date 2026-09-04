# SQLMonitor Linux inventory - local test workspace

A throwaway rig that stands up **SQL Server on Linux in containers** and runs the
real [`install-inventory.sh`](../install-inventory.sh) against it, so the Linux
inventory lane can be exercised end to end before it goes anywhere near a real
fleet.

```bash
cp .env.example .env      # review it
make up                   # SQL Server x2 + tools container
make bootstrap            # DBA database, DDLs, seed data, linked servers
make install              # the real install-inventory.sh
make jobs                 # start every inventory job once
make verify               # assert it is actually collecting
```

`make` on its own lists every target.

---

## What it stands up

| Service | What it is |
|---|---|
| `inventory` | SQL Server on Linux, SQL Agent enabled. What `install-inventory.sh` targets. |
| `monitored1` | A second instance for the inventory to collect from over a linked server. |
| `tools` | Debian userland + `sqlcmd`, with the repo bind-mounted at `/repo`. Where the bash scripts run. |
| `grafana` | Optional (`make grafana`), pointed at the inventory `DBA` database. |

The `tools` image is built **FROM the SQL Server image**, so it needs no second
download and its `sqlcmd` is exactly the version the server ships.

---

## Which edition?

The rig defaults to **`MSSQL_PID=Express`**, and that works: Express on Linux
runs SQL Server Agent, In-Memory OLTP, partitioning, page compression and
linked servers, so the whole inventory installs and collects. Verified, not
assumed.

Two Express caveats the rig handles or documents:

- **`AUTO_CLOSE`.** Express creates databases with `AUTO_CLOSE = ON`, which
  hard-blocks the `MEMORY_OPTIMIZED_DATA` filegroup the inventory needs:
  *"The operation 'AUTO_CLOSE' is not supported with databases that have a
  MEMORY_OPTIMIZED_DATA filegroup."*
  `SCH-Create-Inventory-Specific-Objects.sql` now turns it off first.
- **Database Mail is not supported on Express.** `(dba) Get-AllServerDashboardMail`
  and `(dba) Send Login Expiry EMails` are therefore disabled by
  [`bootstrap/04-disable-mail-jobs.sql`](bootstrap/04-disable-mail-jobs.sql).

For full fidelity set `MSSQL_PID=Developer` in `.env` (free, all features,
licensed for dev/test only) and re-run `make reset && make all`.

---

## Apple Silicon

Microsoft's SQL Server images are **x86-64 only**, and the quickstart is explicit:

> SQL Server container images are supported only on Linux hosts running on Intel
> and AMD x86-64 CPUs. Emulation or translation environments (for example,
> Rosetta 2, Prism, or QEMU) aren't tested or supported.
> &mdash; [Docker quickstart](https://learn.microsoft.com/sql/linux/install-upgrade/quickstart-install-docker)

They nonetheless run fine under Rosetta for a test rig. Enable
**Settings &rarr; General &rarr; Use Rosetta for x86_64/amd64 emulation** in Docker
Desktop. `MSSQL_PLATFORM=linux/amd64` in `.env` does the rest.

Give Docker Desktop at least **8 GB** (Settings &rarr; Resources); two SQL Server
containers at `MSSQL_MEMORY_LIMIT_MB=1536` plus the tools container fit, but
there is not much headroom. Bump it if you add a third instance.

Volumes are **named volumes, not bind mounts** - bind-mounting `/var/opt/mssql`
does not work on Docker for macOS.

---

## What `make bootstrap` does, and why the order matters

Nothing here is arbitrary; each step exists because the previous ordering failed:

1. **`01-instance-common.sql`** - `DBA` database, `AUTO_CLOSE OFF`, the service
   login, the `grafana` login.
2. **`DDLs/SCH-Create-All-Objects.sql`** - tables, views, partition schemes.
3. **`DDLs/SCH-usp_*.sql`** - the collection and reporting procs. The twelve
   procs that read `all_server_*` tables are skipped here and applied later,
   because those tables do not exist yet.
4. **`DDLs/DCL-[grafana-login].sql`** - upstream's own grafana grants. Without
   the `EXECUTE` grants in it, every `Get-AllServer*` run logs
   *"The EXECUTE permission was denied on the object 'usp_avg_disk_latency_ms'"*.
5. **sp_WhoIsActive + First Responder Kit**, then one run of each, so
   `dbo.WhoIsActive` and `dbo.BlitzIndex*` exist. Set
   `INSTALL_OPTIONAL_TOOLS=0` to skip (faster bootstrap, noisier error log).
6. **Collector priming** - three tables are created at *runtime* by their proc,
   never by a DDL file:
   `dbo.tempdb_space_usage` &larr; `usp_TempDbSaver`,
   `dbo.log_space_consumers` &larr; `usp_LogSaver`,
   `dbo.sql_agent_job_thresholds` &larr; `usp_check_sql_agent_jobs`.
   Each runs in its **own connection**, because several raise
   `raiserror(..., 20, -1)` on a missing mandatory parameter and a severity-20
   error kills the session - `TRY/CATCH` cannot contain it.
7. **Credential Manager**, then **`SCH-Create-Inventory-Specific-Objects.sql`**,
   then the twelve inventory-only procs.
8. **`02-inventory-seed.sql`** - `sma_params`, then
   `instance_hosts` &rarr; `instance_details` &rarr; `sma_servers` &rarr;
   `sma_sql_server_hosts`. That order is forced by a foreign key
   (`fk_host_name`), a trigger
   (*"Server entry should exist in [dbo].[instance_details] prior to adding in
   [dbo].[sma_servers]"*) and a second foreign key.
9. **`03-linked-servers.sql`** - one linked server per monitored instance, then
   `sp_testlinkedserver` plus a real cross-server query to prove the hop works.

### The seed that matters most

`dbo.sma_params.dba_team_email_id` ships as `dba_team@gmail.com`, and
[`SCH-usp_wrapper_GetAllServerInfo.sql:89`](../../../DDLs/SCH-usp_wrapper_GetAllServerInfo.sql)
does:

```sql
IF (@recipients IS NULL OR @recipients = 'dba_team@gmail.com') AND @verbose = 0
    raiserror ('@recipients is mandatory parameter', 20, -1) with log;
```

The jobs all run with `@verbose = 0`. So **every `Get-AllServer*` job fails with
a severity-20 error until that parameter is changed.** The seed changes it.

---

## Non-idempotent scripts

`SCH-Create-Inventory-Specific-Objects.sql` drops its tables and recreates them
with unguarded `CREATE`s. On a **second** run it raises `Msg 2714` partway
through, and with `sqlcmd -b` execution stops *after the drops and before the
recreates* - leaving the inventory without its `all_server_*` tables and every
job failing with "Invalid object name".

Both this rig and `install-inventory.sh` therefore run that file **without
`-b`** and then **assert the resulting table set**, failing loudly if anything
is missing. `make bootstrap` and `make install` are safe to re-run.

---

## Timers

The rig has no systemd, so `make install` runs the installer with
`--skip systemd` and [`tools/run-timers.sh`](tools/run-timers.sh) stands in:
one background loop per task, on the intervals the real `.timer` units declare
(including the 10-second one, which cron cannot express).

```bash
make timers        # run the loops in the foreground, Ctrl-C to stop
make timers-once   # one pass of each task
make run TASK=check-instance-availability
```

It is a test harness. It has no persistence, no catch-up after downtime and no
jitter - all things systemd provides. Production uses the real timers.

---

## Verifying

`make verify` runs [`verify.sh`](verify.sh), which asserts fourteen things and
exits non-zero on any failure, so it works as a CI smoke test:

- the instance really is SQL Server on Linux
- no `(dba) SQLMonitor` job step uses `CmdExec`/`PowerShell`
- every step is `TSQL` subsystem, nothing unexpectedly disabled
- the linked servers answer and use `MSOLEDBSQL`
- no inventory job has FAILED, and some have SUCCEEDED
- the `all_server_*` tables hold rows for every enabled instance
- `dbo.sma_errorlog` is empty for the last 30 minutes

Useful companions: `make job-status`, `make data`, `make errors`, `make sql`.

---

## Security

**This rig is not a security model.** The service login is `sysadmin`, the
`grafana` password is `grafana`, passwords sit in `.env`, and TLS certificates
are trusted blindly (`-C`). It is meant to be created with `make up` and
destroyed with `make reset`. Do not copy `bootstrap/01-instance-common.sql`
into anything real.

`.env` is gitignored.

---

## Known quirks

| Symptom | Cause |
|---|---|
| `usp_LogSaver` reports `Msg 245 ... '44s' to data type int` | Only on the forced `@log_used_pct_threshold = 0` path, which runs `DBCC OPENTRAN ... WITH TABLERESULTS`; its output does not match what the proc expects. The table is still created, which is all the rig needs. Upstream issue, unrelated to the Linux port. |
| Bootstrap takes ~3-4 minutes | The First Responder Kit is a 2.2 MB script applied to both instances under emulation. `INSTALL_OPTIONAL_TOOLS=0` skips it. |
| `(dba) Get-AllServerDashboardMail` shows Failed once | It runs once at install before `04-disable-mail-jobs.sql` disables it. |
