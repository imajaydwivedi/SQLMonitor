# SQLMonitor - Linux inventory lane

Everything the **inventory server** needs when it runs on SQL Server on Linux.

Full guide: [Deployment &rarr; Linux Inventory Server](../../docs/deployment/linux-inventory.md).

```
linux/
├── install-inventory.sh              # replaces the inventory half of Install-SQLMonitor.ps1
├── remove-inventory.sh               # replaces the inventory half of Remove-SQLMonitor.ps1
├── sqlmonitor-inventory.conf.sample  # -> /etc/sqlmonitor/inventory.conf
├── lib/
│   └── sqlmonitor.sh                 # what dbatools used to provide
├── bin/                              # one script per former .ps1 / .bat
│   ├── check-instance-availability.sh
│   ├── sqlserver-versions-update.sh
│   ├── get-host-ip-addresses.sh
│   ├── populate-inventory-tables.sh
│   ├── stop-stuck-sqlmonitor-jobs.sh
│   ├── update-sqlmonitor-ip.sh
│   ├── collect-all-server-alert-messages.sh
│   ├── run-on-all-servers.sh
│   ├── update-sqlagent-jobs-threshold.sh
│   └── change-login-password-all-servers.sh
└── systemd/
    ├── sqlmonitor@.service           # templated runner: %i = script name
    └── sqlmonitor-*.timer            # one per job that left SQL Agent
```

## The constraint that shaped this

SQL Server on Linux does not implement the SQL Agent **CmdExec** or
**PowerShell** subsystems, nor SQL Agent **Alerts**, nor `xp_cmdshell`, nor
Windows integrated authentication for linked servers
([Microsoft Learn](https://learn.microsoft.com/sql/linux/sql-server-linux-editions-and-components-2022#unsupported-features-and-services)).

Every inventory job used to be a `CmdExec` step. So:

- jobs that only wrapped `sqlcmd -Q "EXEC ..."` were converted to the **`TSQL`
  subsystem** and stayed in SQL Agent;
- jobs that ran a real process became **systemd timers** calling the scripts in
  `bin/`.

## Dependencies

`bash` 4.3+, `sqlcmd` (mssql-tools18), `curl`, coreutils. Optionally `python3`
for `collect_all_server_alert_messages.py`, which stayed Python because it
already was.

No PowerShell, no dbatools, no WMI, no SMB.

## Conventions every script in `bin/` follows

- source `../lib/sqlmonitor.sh`, then call `sm_init`
- read `/etc/sqlmonitor/inventory.conf` (override with `$SQLMONITOR_CONF`)
- never take a password on the command line - the inventory password comes from
  `INVENTORY_PASSWORD_FILE`, fleet and third-party passwords from the
  Credential Manager via `sm_get_credential`
- log in the `yyyyMMMdd_HHmm LEVEL:  message` shape the PowerShell lane used
- record fleet failures in `dbo.sma_errorlog` with the job name the systemd
  timer replaced, so existing dashboards and alerts keep working
- exit non-zero when something failed, so `systemctl status` tells the truth

## Quick check

```bash
sudo ./install-inventory.sh --dry-run --verbose
sudo -u sqlmonitor /opt/sqlmonitor/bin/check-instance-availability.sh --verbose
systemctl list-timers 'sqlmonitor-*'
```
