# Upgrade

Upgrading SQLMonitor is **the same as installing it** &mdash; the installer is idempotent for object creation and updates DDL in place. The only difference is you want to target a specific subset of steps.

## 1. Pull the latest code

```powershell
cd C:\Code\GitHub\SQLMonitor
git fetch
git checkout dev       # or 'main' if you pin there
git pull
```

## 2. Review the change log

Skim the commits since your last upgrade:

```powershell
git log --oneline <last-upgrade-commit>..HEAD -- SQLMonitor/ DDLs/
```

Anything that touched `DDLs/SCH-Create-All-Objects.sql`, `SCH-usp_*.sql`, `SCH-Job-*.sql` or `SQLMonitor/*.ps1` is material. `DDLs/SCH-[dbo].[purge_table].sql` changes may add new tables to purge.

## 3. Dry-run on a non-prod instance first

```powershell
.\Private\Wrapper-InstallSQLMonitor.ps1 -DryRun $true -Verbose
```

Any step that would drop/recreate state (linked servers, WhoIsActive table, PowerShell jobs) announces itself.

## 4. Apply to prod

**Targeted upgrade** (recommended): re-run only the steps that changed. Example after a DDL-only change:

```powershell
.\Private\Wrapper-InstallSQLMonitor.ps1 -OnlySteps '2__AllDatabaseObjects', '55__EnablePageCompression' -Verbose
```

**Full re-run** (safe, takes 5&ndash;15 min): no `-OnlySteps`. The installer will:

- `CREATE OR ALTER` every proc, view and function.
- Re-register every `(dba) *` job, preserving schedule *if the schedule hasn't changed*.
- Re-create the XEvent session if its definition drifted.
- Skip First-Responder-Kit / Darling-Data / Ola re-install unless those zips changed.

## 5. Upgrading the wrapper scripts

`Wrapper-Samples/` evolves too. After pulling, **diff** your `Private/Wrapper-*.ps1` against the new `Wrapper-Samples/Wrapper-*.ps1`:

```powershell
git diff --no-index Private\Wrapper-InstallSQLMonitor.ps1 Wrapper-Samples\Wrapper-InstallSQLMonitor.ps1
```

Apply any new parameters or logic to your `Private/` copy.

## 6. Upgrading Grafana dashboards

Dashboards evolve independently of the T-SQL codebase. After pulling:

1. In Grafana, **Export** your current dashboards with `Share &rarr; Export &rarr; Save to file` (back them up).
2. Import the new JSONs from `Grafana-Dashboards/`, letting Grafana overwrite by UID.
3. Re-apply any org-specific tags, variable defaults, or panel hacks you had.

## 7. Upgrading the Alert Engine

See `Alerting/Deployment-Instructions/alertengine-on-podman.sh`:

```bash
cd Alerting
podman build -t sqlmonitor/alert-engine:latest .
podman stop alertengine
podman rm alertengine
podman run -d --name alertengine \
    -p 5001:5001 \
    --env-file /etc/sqlmonitor/alert-engine.env \
    sqlmonitor/alert-engine:latest
```

## 8. Upgrading sql_exporter / Prometheus

See [Prometheus / sql_exporter](../prometheus.md) &mdash; `sql_exporter` collectors are plain YAML; most upgrades are:

```bash
# pull new YAMLs
cd /opt/sql_exporter
cp -a /opt/sqlmonitor-repo/sql_exporter/*.yml .
systemctl restart sql_exporter
```

## Roll-back

Because the installer uses `CREATE OR ALTER`, there is no automatic rollback. To revert:

- Pin your repo to the previous commit (`git checkout <commit>`).
- Re-run the installer with `-OnlySteps '2__AllDatabaseObjects'` &mdash; this re-applies the older DDL.
- Schedule and job changes won't revert automatically &mdash; manually drop/re-create jobs whose schedules changed.

## When a DDL change is destructive

If a schema change needs to **drop and recreate** a table (rare), the installer will detect it and log:

```text
[WARN] Table dbo.xevent_metrics schema drift detected. Dropping and recreating.
```

Losing the data in that table is usually acceptable (telemetry is re-populated within hours), but back up first if you are unsure.
