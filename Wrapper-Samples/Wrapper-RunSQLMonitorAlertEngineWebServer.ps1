# In powershell
& python E:\GitHub\SQLMonitor\Alerting\Run-SQLMonitorAlertEngineWebServer.py --inventory_server localhost --verbose True #--login_password 'SomeStrongSApassword'

# In powershell with port
#& python E:\GitHub\SQLMonitor\Alerting\Run-SQLMonitorAlertEngineWebServer.py --inventory_server sqlmonitor.ajaydwivedi.com,1433 --login_password 'SomeStrongSApassword' --verbose True

# Command Prompt with port
# python E:\GitHub\SQLMonitor\Alerting\Run-SQLMonitorAlertEngineWebServer.py --inventory_server sqlmonitor.ajaydwivedi.com,1433 --login_password "SomeStrongSApassword" --verbose True