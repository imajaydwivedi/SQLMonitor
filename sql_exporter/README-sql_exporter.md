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

# Refresh Collectors
```
# E:\Github\SQLMonitor\sql_exporter\sql_exporter.exe --config.file E:\Github\SQLMonitor\sql_exporter\sql_exporter.yml

# Get local data collectors in Github Repo
$collectors = Get-ChildItem -Path "E:\Github\SQLMonitor\sql_exporter\mssql_*.collector.yml"

# Remove old collectors from remote machines
Get-ChildItem "\\aghost-1a\d$\sql_exporter\mssql_*.collector.yml" | ForEach-Object {if($_.Name -notin $collectors.Name){$_}} | Remove-Item
Get-ChildItem "\\aghost-1b\d$\sql_exporter\mssql_*.collector.yml" | ForEach-Object {if($_.Name -notin $collectors.Name){$_}} | Remove-Item

# Add new collectors to remote machines
$collectors | Copy-Item -Destination "\\aghost-1a\d$\sql_exporter\" -Verbose
$collectors | Copy-Item -Destination "\\aghost-1b\d$\sql_exporter\" -Verbose

# Restart sql_exporter service
get-service sql_exporter | Restart-Service
Invoke-Command -ComputerName aghost-1a -ScriptBlock {get-service sql_exporter | Restart-Service}
Invoke-Command -ComputerName aghost-1b -ScriptBlock {get-service sql_exporter | Restart-Service}


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




I want to build histogram panel in grafana based on mssql_waits__* metrics.

I want to have maximum 12 vertical sticks. Say $wait_sticks = 12.

Assume user want wait treand/histrogram for 2 hours. So internal time should be 120 minutes divide $wait_sticks = 10.

So take value of mssql_waits__wait_time_seconds for every 10 minutes, subtract its previous value and plot it in histogram.

Give me grafana promQL for same.

Wait Histogram Query
-----------------------
clamp_min(max by (wait_type) (mssql_waits__wait_time_seconds{instance=~"$Server"}) - max by (wait_type) (mssql_waits__wait_time_seconds{instance=~"$Server"} offset $wait_bucket), 0) > 0

clamp_min(max by (wait_type) (mssql_waits__wait_time_seconds{instance=~"sqlmonitor:9399"}) - max by (wait_type) (mssql_waits__wait_time_seconds{instance=~"sqlmonitor:9399"} offset $wait_bucket), 0) > 0

rate(mssql_log_growths{instance=\"$Server\"}[$__rate_interval])
```


