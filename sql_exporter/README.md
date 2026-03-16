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


