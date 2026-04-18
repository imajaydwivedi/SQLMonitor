# Support

## Community support (free)

The fastest place to get help is the **`#sqlmonitor`** channel on the SQL Community Slack.

[:fontawesome-brands-slack: Join `#sqlmonitor` on Slack](https://ajaydwivedi.com/sqlmonitor/slack){ .md-button .md-button--primary } &nbsp; [:fontawesome-brands-slack: Request workspace invite](https://ajaydwivedi.com/join/slack){ .md-button }

When asking a question please include:

- SQL Server major version & edition (Standard/Enterprise)
- OS (Windows / Linux / managed instance)
- `Install-SQLMonitor.ps1` step where the error occurred (the script writes a step name before every block)
- The relevant snippet of the installer transcript &mdash; use `-Verbose` when re-running
- `SELECT @@VERSION` and the output of `DBA.dbo.usp_get_sma_health`

For schema questions it also helps to paste the top ~50 rows of the affected table.

## Paid / private support

For dedicated consulting, customizations, or time-bound production help, reach out directly over Slack DM on the same workspace, or:

- GitHub sponsors: <https://github.com/sponsors/imajaydwivedi>
- Blog contact form: <https://ajaydwivedi.com/contact>

## Filing bugs

Use [GitHub Issues](https://github.com/imajaydwivedi/SQLMonitor/issues) for:

- Installer failures that are reproducible
- Dashboard panels showing wrong numbers
- SQL Agent jobs failing with the same error repeatedly
- Typos / documentation fixes

Please **don't** file an issue for "how do I&hellip;" &mdash; use Slack for that; GitHub Issues is best for defects that have a fix.

### Good issue template

```markdown
**SQL Server version:** 2019 Enterprise 15.0.4316.3
**OS:** Windows Server 2022
**SQLMonitor commit:** <paste `git rev-parse HEAD`>
**Step that failed:** `08__CreateProc_usp_collect_wait_stats`

**What I expected:**
Step completes and creates `dbo.usp_collect_wait_stats`.

**What happened:**
Msg 102, Level 15, State 1, Procedure usp_collect_wait_stats, Line 42
Incorrect syntax near '...'.

**Reproduction:**
1. Fresh SQL 2019 Enterprise install
2. Copy `Wrapper-Samples\Wrapper-InstallSQLMonitor.ps1` to `Private\`
3. Run with `-OnlySteps '08__CreateProc_usp_collect_wait_stats'`

**Installer transcript:** <paste or attach>
```

## Frequently asked questions

### Does it support Azure SQL Database / Managed Instance?

Azure SQL **Managed Instance** is supported &mdash; the installer detects it and skips steps that require OS-level access (xp_cmdshell, Perfmon files, XEvent files on disk). Use the `*-ManagedInstance.sql` variants.

Azure SQL **Database** (PaaS) is *not* supported by the collector side (no SQL Agent jobs on DB-as-a-service). You can still add it as a target for the **Prometheus path** using `sql_exporter`.

### Can I point all my instances at an Azure SQL Database inventory?

No. The inventory server is read/written by SQL Agent jobs across every monitored instance &mdash; it needs cross-database queries, linked servers, and a SQL Agent. Use a VM or Managed Instance as the inventory.

### How much overhead does the collection add?

Under 1% CPU on a typical OLTP workload. The single most expensive collector is `Collect-XEvents` (which parses the query workload XEvent file) &mdash; if you are near capacity, reduce its frequency or disable it.

### Does it work on SQL Server 2008 R2?

Partially. `dbo.xevent_metrics` is unavailable (no XEvents on 2008R2). Everything else &mdash; wait stats, Perfmon, Blitz, WhoIsActive &mdash; works. The installer detects the version and skips unsupported steps.

### Can I use my own Grafana / does it need to be on the inventory?

Any Grafana 9.x+ works. Grafana is usually run on the inventory host for network-locality, but you can run it anywhere that can reach the inventory SQL port (1433 by default) and the `sql_exporter` ports (9399) if you use the Prometheus path.

### How do I update an existing deployment?

`git pull` + re-run your `Wrapper-Install-SQLMonitor.ps1`. The installer is idempotent &mdash; every step checks before it changes anything. See [Deployment &rarr; Upgrade](deployment/upgrade.md).

### The dashboards show "no data" for one instance &mdash; what do I check?

1. `dbo.all_server_collection_latency_info` on the inventory &mdash; is the instance listed and recent?
2. `dbo.sql_agent_jobs_all_servers` &mdash; are the `(dba) *` jobs succeeding on that instance?
3. Linked server test: `SELECT TOP 1 * FROM [MyInstance].DBA.sys.tables;`
4. Grafana variable `sql_instance` &mdash; does it include the instance? (Common cause: instance not yet in `dbo.sma_sql_instance`.)

See [Deployment &rarr; Troubleshooting](deployment/troubleshooting.md) for the full decision tree.

## Related links

- **GitHub Repo:** <https://github.com/imajaydwivedi/SQLMonitor>
- **Live Demo:** <https://sqlmonitor.ajaydwivedi.com> &mdash; credentials on the [Live Demo](dashboards/live-demo.md) page
- **YouTube Playlist:** <https://ajaydwivedi.com/youtube/sqlmonitor>
- **Blog Posts:** <https://ajaydwivedi.com/category/sqlmonitor>
- **Slack Community:** <https://ajaydwivedi.com/sqlmonitor/slack>

## Contributing

PRs welcome. Please:

1. Branch off `dev`, not `main`.
2. Keep collector changes backwards-compatible &mdash; the installer is idempotent and upgrade paths must not break existing deployments.
3. Add/update the corresponding `SCH-Job-*.sql` alongside any new stored procedure.
4. If you change a dashboard, export it via Grafana's &ldquo;Share &rarr; Export &rarr; Save to file&rdquo; so we get the deterministic JSON.
5. Update `mkdocs.yml` and `docs/*.md` for any user-visible change.

See the repo [`CONTRIBUTING` guidance in the wiki](https://github.com/imajaydwivedi/SQLMonitor) for the full checklist.
