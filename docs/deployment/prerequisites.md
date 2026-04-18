# Prerequisites

Everything SQLMonitor expects to find before `Install-SQLMonitor.ps1` is run.

## 1. Central deployer machine

The machine *from which* you run the installer (can be your workstation, a jump host, or the inventory server itself).

- Windows 10 / 11 / Server 2016+ with PowerShell 5.1 **or** PowerShell 7+.
- Git (to clone the repo) or ability to download the repo ZIP.
- `dbatools` PowerShell module &mdash; the installer uses it heavily. Download in advance:

    ```powershell
    Save-Module dbatools -Path "$env:USERPROFILE\Downloads\"
    ```

- `PoshRSJob` PowerShell module (for parallel multi-server wrappers):

    ```powershell
    Install-Module PoshRSJob -Scope AllUsers
    ```

- Local admin rights on the monitored instance's Windows host (or a `WindowsCredential` that has them) &mdash; used for Perfmon data-collector setup, copying files to `C:\SQLMonitor`, and PsRemoting checks.
- Network access to:
    - Monitored instance (SQL, 1433 or custom) and its Windows host (SMB, WinRM).
    - Inventory server (SQL).
    - Data destination server, if different.

## 2. Monitored SQL Server instance

Supported editions: **SQL Server 2012 onwards** (any edition that supports Extended Events). SQL Server 2008 R2 works but XEvent collection is disabled.

Before running the installer:

- `sa`-equivalent SQL credentials (or a Windows login that is `sysadmin`).
- A dedicated **Windows domain account** for the SQL Agent proxy (used by PowerShell and CmdExec subsystems). This account needs:
    - `Administrators`, `Performance Log Users`, `Performance Monitor Users` membership on the monitored host.
    - Read access to `$env:USERPROFILE\Downloads\` on the deployer (for initial copy).
- **Database Mail** profile configured on the inventory server (for dashboard mail / login-expiry mail). You can skip this with `-SkipMailProfileCheck $true`.
- **TDE / Encryption compatibility**: if your instance is TDE-encrypted, confirm the data destination is also TDE-capable (or use the same instance).

## 3. Inventory SQL Server instance

- A SQL Server instance that will hold the `all_server_*` aggregates.
- Enterprise / Developer edition **recommended** for Memory-Optimized tables (the installer's default). For Standard Edition, run with `-MemoryOptimizedObjectsUsage $false`.
- Can be **the same** instance you are monitoring (small fleets / labs), or a dedicated observability server.
- `sa`-equivalent credentials.

## 4. Grafana

- Grafana 10+ (any distribution: Grafana OSS, Grafana Cloud, self-hosted).
- A **Microsoft SQL Server** data source pointed at your inventory server, named `SQLMonitor`.
- Credentials: a SQL login named `grafana` with `db_datareader` on the `DBA` database. The installer creates this login on every instance and copies its SID from the inventory server so the same login password works cluster-wide (step `56__GrafanaLogin`).
- Optional but recommended: a folder in Grafana called **SQLMonitor** to house the dashboards.

## 5. Third-party kits (optional but bundled into the install flow)

Download in advance and point the installer at the ZIPs:

- **First Responder Kit** &mdash; latest release from [BrentOzarULTD/SQL-Server-First-Responder-Kit](https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/releases). Supply via `FirstResponderKitZipFile`.
- **Darling Data** &mdash; `main.zip` from [erikdarlingdata/DarlingData](https://github.com/erikdarlingdata/DarlingData). Supply via `DarlingDataZipFile`.
- **Ola Hallengren Maintenance Solution** &mdash; `master.zip` from [olahallengren/sql-server-maintenance-solution](https://github.com/olahallengren/sql-server-maintenance-solution). Supply via `OlaHallengrenSolutionZipFile`.

The exact download commands are documented in [`Wrapper-Samples/Wrapper-InstallSQLMonitor.ps1`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/Wrapper-Samples/Wrapper-InstallSQLMonitor.ps1).

## 6. PowerShell remoting (deployer &harr; monitored host)

The installer uses PSRemoting to lay down `C:\SQLMonitor\*`, set up Perfmon's `logman` data collector, and run the collectors as scheduled tasks where needed.

On the **monitored host**, one-time setup:

```powershell
Enable-PSRemoting -Force -SkipNetworkProfileCheck
Set-Item WSMAN:\Localhost\Client\TrustedHosts -Value "SQLMonitor.Lab.com" -Concatenate -Force
Set-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name LocalAccountTokenFilterPolicy -Value 1
```

On the **deployer**:

```powershell
Set-Item WSMAN:\Localhost\Client\TrustedHosts -Value "*" -Force  # or scope to hostnames
```

## 7. Ports and firewall

| From &rarr; To | Port | Reason |
|---|---|---|
| Deployer &rarr; Monitored host | 445 (SMB) | Copy SQLMonitor files to `C:\SQLMonitor`, ingest Perfmon .blg |
| Deployer &rarr; Monitored host | 5985/5986 (WinRM) | PSRemoting |
| Monitored instance &harr; Inventory instance | 1433 (or custom SQL) | Linked server aggregation |
| Grafana &rarr; Inventory instance | 1433 | Dashboard queries |
| Alert Engine &rarr; Inventory instance | 1433 | Alert reads + writes |
| sql_exporter &rarr; Monitored instance (if using Prom path) | 1433 | Metric scrapes |
| Prometheus &rarr; sql_exporter | 9399 | Scraping |
| Prometheus &rarr; windows_exporter | 9182 | Scraping |

## Pre-flight check

A fast sanity check before you run the installer:

```powershell
# 1. Can you reach the monitored instance?
Invoke-Sqlcmd -ServerInstance 'MyInstance' -Query "SELECT @@VERSION" -TrustServerCertificate

# 2. Can PSRemoting work?
Test-WSMan 'MyInstanceHost' -Credential $WindowsCredential -Authentication Negotiate

# 3. Is the dbatools module loadable?
Import-Module 'D:\Downloads\dbatools\<version>\dbatools.psd1' -Force

# 4. Does the inventory instance have Database Mail?
Invoke-Sqlcmd -ServerInstance 'Inventory' -Query "SELECT name FROM msdb.dbo.sysmail_profile"
```

When all four succeed, continue to **[Install Walkthrough](install.md)**.
