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

## Create mac service
```

sudo launchctl list | grep prometheus
brew services list | grep prometheus

brew services info prometheus

cat $(brew --prefix)/etc/prometheus.yml
brew services restart prometheus

# Update grafana
vim /opt/homebrew/etc/grafana/grafana.ini
brew services restart grafana
```

### Validate on Mac - Service Management

| Action         | Command |
|---------------|---|
| Check status | `sudo launchctl list \| grep sql_exporter` |
| Stop | `sudo launchctl unload /Library/LaunchDaemons/com.sql_exporter.plist` |
| Start | `sudo launchctl load /Library/LaunchDaemons/com.sql_exporter.plist` |
| View logs | `tail -f /usr/local/var/log/sql_exporter.log` |
| View errors | `tail -f /usr/local/var/log/sql_exporter.err.log` |
| Test metrics | `curl -s http://localhost:9399/metrics \| head -20` |

The service auto-starts on every reboot and auto-restarts if it crashes (KeepAlive).

# How to add in Prometheus

```
|------------$ sudo cat /etc/prometheus/prometheus.yml


# my global config
global:
  scrape_interval: 15s # Set the scrape interval to every 15 seconds. Default is every 1 minute.
  evaluation_interval: 15s # Evaluate rules every 15 seconds. The default is every 1 minute.
  # scrape_timeout is set to the global default (10s).

# Alertmanager configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets:
          # - alertmanager:9093

# Load rules once and periodically evaluate them according to the global 'evaluation_interval'.
rule_files:
  - "prometheus.rules.yml"
  # - "second_rules.yml"

# A scrape configuration containing exactly one endpoint to scrape:
# Here it's Prometheus itself.
scrape_configs:
  # The job name is added as a label `job=<job_name>` to any timeseries scraped from this config.
  - job_name: "prometheus"

    # metrics_path defaults to '/metrics'
    # scheme defaults to 'http'.

    static_configs:
      - targets: ["localhost:9091"]
       # The label name is added as a label `label_name=<label_value>` to any timeseries scraped from this config.
        labels:
          app: "prometheus"

  - job_name: "node_exporter"
    static_configs:
      - targets:
        - "localhost:9100"

  - job_name: 'win-exporter'
    static_configs:
      - targets:
        - 'sqlmonitor:9182'

  - job_name: mssql_exporter_common
    scrape_interval: 30s
    params:
      'jobs[]': [mssql_common]
    static_configs:
      - targets:
        - "sqlmonitor:9399"
        - "AgHost-1A:9399"
        - "AgHost-1B:9399"

  - job_name: mssql_exporter_longrunning
    scrape_interval: 2m
    params:
      'jobs[]': [mssql_long_running]
    static_configs:
      - targets:
        - "sqlmonitor:9399"
        - "AgHost-1A:9399"
        - "AgHost-1B:9399"

  - job_name: mssql_exporter_ag
    scrape_interval: 30s
    params:
      'jobs[]': [mssql_ag]
    static_configs:
      - targets:
        - "AgHost-1A:9399"
        - "AgHost-1B:9399"

```


# Collectors

`sql_exporter.yml` binds each collector file (`mssql_*.collector.yml`) to a
job; every target in the job runs every metric definition in the named
collectors.

| Collector file | Job | Scrape interval | What it publishes |
|---|---|---|---|
| `mssql_standard.collector.yml` | `mssql_common` | default | Upstream [sql_exporter](https://github.com/burningalchemist/sql_exporter/tree/master/examples/mssql_standard) baseline &mdash; `mssql_perfmon__*`, `mssql_up`, `mssql_sqlserver_*`. |
| `mssql_dba_cached.collector.yml` | `mssql_common` | 1m | `mssql_virtualfilestats__*`, `mssql_waits__*`, `mssql_cpu_utilization__*`. |
| `mssql_dba_regular.collector.yml` | `mssql_common` | default | `mssql_service_info`, `mssql_db_state`, registry/config snapshot. |
| `mssql_dba_stableinfo.collector.yml` | `mssql_common` | 10m | Low-churn info (CPU count, version, clustering). |
| `mssql_dba_aghealth.collector.yml` | `mssql_ag` | 1m | `mssql_aghealth__*` (AG sync_health / latency / queues). |
| `mssql_dba_whoisactive.collector.yml` | `mssql_long_running` | 2m | `mssql_whoisactive__*` &mdash; current sp_WhoIsActive snapshot. |
| `mssql_sqlagent_jobs.collector.yml` | `mssql_msdb` | 1m | `mssql_sqlagent_job__*` &mdash; job enabled / outcome / duration / next run / 24h step failures. |
| `mssql_backup_history.collector.yml` | `mssql_msdb` | 5m | `mssql_backup__*` &mdash; per-(db, backup_type) last-time / size / duration / age. |
| `mssql_xevent.collector.yml` | `mssql_xevent` | 1m | `mssql_xevent__*` &mdash; 5-minute aggregates of `DBA.dbo.xevent_metrics` (guarded; no-op where the XEvent proc isn't installed). |

The three **msdb / xevent** collectors are new in Phase 1 of the Prometheus
dashboard rollout and feed the new Grafana dashboards under
`sql_exporter/Prometheus-Dashboards/`. See [`Prometheus-Dashboards/README.md`](Prometheus-Dashboards/README.md)
for the generator / spec workflow and the per-dashboard panel inventory.


# Refresh Collectors
```
# E:\Github\SQLMonitor\sql_exporter\sql_exporter.exe --config.file E:\Github\SQLMonitor\sql_exporter\sql_exporter.yml

# Get local data collectors in Github Repo
$collectors = Get-ChildItem -Path "E:\Github\SQLMonitor\sql_exporter\mssql_*.collector.yml"

# Remove old collectors from remote machines
Get-ChildItem "\\aghost-1a\d$\sql_exporter\mssql_*.collector.yml" | ForEach-Object {if($_.Name -notin $collectors.Name){$_}} | Remove-Item
Get-ChildItem "\\aghost-1b\d$\sql_exporter\mssql_*.collector.yml" | ForEach-Object {if($_.Name -notin $collectors.Name){$_}} | Remove-Item

# Copy sql_exporter.yml config file
Get-ChildItem "E:\Github\SQLMonitor\sql_exporter\sql_exporter.yml" | Copy-Item -Destination "\\aghost-1a\d$\sql_exporter\" -Verbose -Force
Get-ChildItem "E:\Github\SQLMonitor\sql_exporter\sql_exporter.yml" | Copy-Item -Destination "\\aghost-1a\d$\sql_exporter\" -Verbose -Force

# Add new collectors to remote machines
$collectors | Copy-Item -Destination "\\aghost-1a\d$\sql_exporter\" -Verbose -Force
$collectors | Copy-Item -Destination "\\aghost-1b\d$\sql_exporter\" -Verbose -Force

# Restart sql_exporter service
# get-service sql_exporter | Stop-Service -PassThru
get-service sql_exporter | Restart-Service -PassThru
Invoke-Command -ComputerName aghost-1a -ScriptBlock {get-service sql_exporter | Restart-Service -PassThru}
Invoke-Command -ComputerName aghost-1b -ScriptBlock {get-service sql_exporter | Restart-Service -PassThru}

```


# PasteThePlan Bridge
- Uses `sql_exporter/pastetheplan-proxy.py` to bridge Grafana data link to PasteThePlan website.
  - Reads the raw query plan XML from the ?xml= URL query parameter
  - POSTs `{"queryplan_xml": "<xml>"}` to the same AWS Lambda API that the `sqlops-pastetheplan` extension uses
  - Redirects the browser to `https://www.brentozar.com/pastetheplan/?id=<planId>`
```

# Step 1 — Start the local HTTP server
cd sql_exporter

python3 pastetheplan-proxy.py          # Prometheus on localhost:9090
# OR if Prometheus is elsewhere:
python3 pastetheplan-proxy.py 8080 http://your-prometheus-host:9090

# → PasteThePlan proxy  →  http://localhost:8080/pastetheplan-bridge.html

# Step 2 — Import the updated dashboard JSON into Grafana.
# Step 3 — Click any non-empty query_plan cell → a "Paste The Plan" icon/link appears → click it → the bridge page opens, submits the XML, and auto-redirects you to the Brent Ozar plan viewer.
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

# Prompt for Augment to build data collector based on query result

```
Use below query to create metrics for ag health into aghealth collector.
Just like earlier, each numeric value should become a metric. 
Name should be like mssql_aghealth__<column_name>
Query result is unique for a combination of (replica_server_name, ag_name, database_name). So using these 3 columns, I have created a unique key column named [unique_key]. Use this as key label in all metrics.
Columns having numeric value as we as another column with description should be clubbed as one where description columnd should be used as label.
All the remaining string columns should go as label for metric mssql_aghealth__synchronization_health. 




```



