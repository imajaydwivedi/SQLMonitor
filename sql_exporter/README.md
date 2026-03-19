# [sql_exporter](https://github.com/burningalchemist/sql_exporter)

## Create windows service
```
New-Service -Name "sql_exporter" `
  -BinaryPathName "E:\Github\SQLMonitor\sql_exporter\sql_exporter.exe --config.file E:\Github\SQLMonitor\sql_exporter\sql_exporter.yml" `
  -StartupType Automatic `
  -DisplayName "SQL Exporter for Prometheus"

# Set service account to Lab\SQLService

# Start the service
Start-Service sql_exporter

# Check the service status
Get-Service sql_exporter

# Remove the service
Stop-Service sql_exporter
sc.exe delete sql_exporter

# Add firewall rule
New-NetFirewallRule -DisplayName "SQL Exporter (TCP/9399)" -Direction Inbound -Protocol TCP -LocalPort 9399 -Action Allow

# Validate at http://localhost:9399/metrics
```


# Grafana Dashboard Specifications for AI Tool

```
# Step 01
I want you to check dashboards present in folder Grafana-Dashboards. Don't modify them. Just read to check all metrics that are covered.
Similarly, read procedure code in file DDLs\SCH-usp_collect_performance_metrics.sql. Check all the metrics that are collected in this procedure also.

Ensure that any metric/data that is found in Step 01 are present in sql_exporter\mssql_*.collector.yml files. If missing, add them in dba collector.

# Step 02
Copy perfmon dashboard Grafana-Dashboards\Monitoring - Perfmon Counters - Quest Softwares - Distributed.json to sql_exporter directory.
Modify queries of this new perfmon dashboard to use sql_exporter collected metrics. Don't change panels layout or thresholds or titles.
Just change datasource and queries.

Do this activity with Resumable Retry Plan. That means, break the work into multiple steps. keep saving intermediate result and progress so that you can resume the timed out work from last step.
```
