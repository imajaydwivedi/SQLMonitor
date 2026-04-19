# Deployment

SQLMonitor deploys in three phases:

1. **Bootstrap the central server** &mdash; install Grafana, the DBA database, and the SQLMonitor repo on a machine that will orchestrate deployment.
2. **Onboard an instance** &mdash; run `Install-SQLMonitor.ps1` against the target instance. This creates objects, loads 3rd-party kits (First Responder Kit, Darling Data, Ola Hallengren), sets up Perfmon, creates jobs, creates partitions, sets up linked servers, and wires up the Grafana login.
3. **Import dashboards** &mdash; import the JSONs in `Grafana-Dashboards/` into the `SQLMonitor` folder in your Grafana instance, pointing them at the `SQLMonitor` data source.

## Pages in this section

- **[Prerequisites](prerequisites.md)** &mdash; what you need in place before running the installer.
- **[Install Walkthrough](install.md)** &mdash; step-by-step first install.
- **[Install-SQLMonitor Parameters](parameters.md)** &mdash; full reference for every parameter of `Install-SQLMonitor.ps1`.
- **[Install Steps](steps.md)** &mdash; every named install step, in order, and what it does.
- **[Upgrade](upgrade.md)** &mdash; how to refresh an already-deployed instance.
- **[Remove](remove.md)** &mdash; `Remove-SQLMonitor.ps1` walkthrough.
- **[Troubleshooting](troubleshooting.md)** &mdash; common errors and fixes.

## High-level flow

``` mermaid
flowchart LR
    A[Close repo to<br/>central server] --> B[Install Grafana<br/>+ data source]
    B --> C[Copy Wrapper-Samples/<br/>*.ps1 to Private/]
    C --> D[Edit Private/<br/>Wrapper-InstallSQLMonitor.ps1]
    D --> E[Run wrapper &rarr;<br/>Install-SQLMonitor.ps1]
    E --> F[59 install steps]
    F --> G[Import<br/>Grafana-Dashboards/*.json]
    G --> H[Deploy Alert Engine<br/>optional]
    H --> I[Deploy sql_exporter<br/>optional]
```

## Deploy-time decisions

Before you run the installer, decide:

| Decision | Options | Where it maps in the installer |
|---|---|---|
| Topology | Distributed vs Central vs Hybrid | `SqlInstanceForTsqlJobs`, `SqlInstanceForPowershellJobs`, `SqlInstanceAsDataDestination` |
| Inventory server identity | Hostname of the observability SQL instance | `InventoryServer` |
| Data destination | Same as monitored instance? Or push elsewhere? | `SqlInstanceAsDataDestination` |
| Memory-Optimized usage | On by default; disable for non-supporting editions | `MemoryOptimizedObjectsUsage` |
| Retention | Per-table (via `dbo.purge_table`) or a single fleet default | `RetentionDays` |
| 3rd-party kits | Use bundled ZIPs or reference existing installs | `FirstResponderKitZipFile`, `DarlingDataZipFile`, `OlaHallengrenSolutionZipFile` |
| Managed Instance? | If yes, a different disk-space / perfmon path is used | `IsManagedInstance` |

## What the installer is not

- **Not idempotent-across-versions by default.** It is idempotent for the same version; when upgrading SQLMonitor itself, run it again &mdash; it will upgrade objects in place. See [Upgrade](upgrade.md).
- **Not a replacement for change control.** The installer creates SQL Agent jobs, proxies, credentials, linked servers and logins on both the monitored and inventory instances. Treat it as a production change.
