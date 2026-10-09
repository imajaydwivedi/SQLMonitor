/*
	Seeds ONE monitored instance into the inventory. Called once per entry in
	sqlmonitor.monitoredInstances (Helm) / $MONITORED_SERVERS (bootstrap.sh).

	Kept separate from 02-inventory-seed.sql so that an inventory with no
	monitored instances yet is a clean, valid state.

	ORDER MATTERS, enforced by a foreign key and a trigger:
	    fk_host_name                                instance_details.host_name
	                                                  -> instance_hosts.host_name
	    tgr_dml__fk_validation_sma_servers__server  "Server entry should exist in
	                                                  [dbo].[instance_details] prior
	                                                  to adding in [dbo].[sma_servers]."
	    fk_sma_sql_server_hosts__server             sma_sql_server_hosts.server
	                                                  -> sma_servers.server

	sqlcmd variables:
	    MonitoredHost   instance name (bare host, no port)
	    DbaEmail        an address that is NOT dba_team@gmail.com

	Idempotent: safe to re-run.
*/

USE [DBA];
GO
SET NOCOUNT ON;
GO

MERGE dbo.instance_hosts AS t
USING (VALUES ('$(MonitoredHost)')) AS s (host_name)
   ON t.host_name = s.host_name
WHEN NOT MATCHED BY TARGET THEN
    INSERT (host_name) VALUES (s.host_name);
GO

MERGE dbo.instance_details AS t
USING (VALUES ('$(MonitoredHost)', '$(MonitoredHost)')) AS s (sql_instance, host_name)
   ON t.sql_instance = s.sql_instance AND t.is_alias = 0
WHEN NOT MATCHED BY TARGET THEN
    INSERT (sql_instance, sql_instance_port, is_alias, host_name, [database],
            collector_tsql_jobs_server, collector_powershell_jobs_server,
            data_destination_sql_instance, dba_group_mail_id,
            sqlmonitor_script_path, sqlmonitor_version,
            is_available, is_enabled, is_linked_server_working)
    VALUES (s.sql_instance, '1433', 0, s.host_name, 'DBA',
            s.sql_instance, s.sql_instance,
            s.sql_instance, '$(DbaEmail)',
            '/opt/sqlmonitor', '1.1.0',
            1, 1, 1)
WHEN MATCHED AND t.is_enabled = 0 THEN
    UPDATE SET is_enabled = 1, is_available = 1, dba_group_mail_id = '$(DbaEmail)';
PRINT 'dbo.instance_details <- $(MonitoredHost)';
GO

MERGE dbo.sma_servers AS t
USING (VALUES ('$(MonitoredHost)', 'SQLMonitor monitored instance')) AS s (server, friendly_name)
   ON t.server = s.server
WHEN NOT MATCHED BY TARGET THEN
    INSERT (server, domain, friendly_name, stability, priority, server_type,
            hadr_strategy, is_monitoring_enabled, is_onboarded, is_decommissioned)
    VALUES (s.server, 'local', s.friendly_name, 'dev', 2, 'SQLServer',
            'standalone', 1, 1, 0)
WHEN MATCHED AND (t.is_monitoring_enabled = 0 OR t.is_decommissioned = 1 OR t.is_onboarded = 0) THEN
    UPDATE SET is_monitoring_enabled = 1, is_onboarded = 1, is_decommissioned = 0;
GO

MERGE dbo.sma_sql_server_hosts AS t
USING (VALUES ('$(MonitoredHost)', '$(MonitoredHost)')) AS s (server, host_name)
   ON t.server = s.server AND t.host_name = s.host_name
WHEN NOT MATCHED BY TARGET THEN
    INSERT (server, host_name, is_quarantined, is_decommissioned)
    VALUES (s.server, s.host_name, 0, 0)
WHEN MATCHED AND t.is_decommissioned = 1 THEN
    UPDATE SET is_decommissioned = 0;
GO
