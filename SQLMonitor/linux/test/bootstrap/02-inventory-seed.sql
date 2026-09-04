/*
	Seeds the inventory's own metadata so the (dba) Get-AllServer* jobs have
	something to collect. Applied to the INVENTORY instance only, after
	SCH-Create-All-Objects.sql and SCH-Create-Inventory-Specific-Objects.sql.

	sqlcmd variables the caller must supply with -v:
	    InventoryHost   hostname of the inventory container   (e.g. inventory)
	    MonitoredHost   hostname of the monitored container   (e.g. monitored1)
	    DbaEmail        an address that is NOT dba_team@gmail.com

	Idempotent: safe to re-run.
*/

USE [DBA];
GO
SET NOCOUNT ON;
GO

/* ------------------------------------------------------------ sma_params -- */
/*	dbo.usp_wrapper_GetAllServerInfo does this, at SCH-usp_wrapper_GetAllServerInfo.sql:89 -

	    IF (@recipients IS NULL OR @recipients = 'dba_team@gmail.com') AND @verbose = 0
	        raiserror ('@recipients is mandatory parameter', 20, -1) with log;

	@recipients is read from sma_params.dba_team_email_id, whose shipped value
	IS 'dba_team@gmail.com', and the jobs all run with @verbose = 0. So every
	Get-AllServer* job fails with a severity-20 error until this is changed.
	This is the single most important seed in the file.	*/
UPDATE dbo.sma_params SET param_value = '$(DbaEmail)'
WHERE param_key = 'dba_team_email_id' AND param_value <> '$(DbaEmail)';
PRINT 'sma_params.dba_team_email_id = $(DbaEmail)';
GO

/*	No Database Mail profile exists in the test rig, so suppress the failure
	mails the wrapper procs would otherwise try (and fail) to send.	*/
UPDATE dbo.sma_params SET param_value = '0'
WHERE param_key = 'send_sqlmonitor_job_failure_mail' AND param_value <> '0';
GO

UPDATE dbo.sma_params SET param_value = 'http://localhost:3000/d/'
WHERE param_key = 'GrafanaDashboardPortal' AND param_value <> 'http://localhost:3000/d/';
GO

/*	ORDER MATTERS, and it is enforced by both a foreign key and a trigger:

	    fk_host_name                            instance_details.host_name
	                                              -> instance_hosts.host_name
	    tgr_dml__fk_validation_sma_servers__server  "Server entry should exist in
	                                              [dbo].[instance_details] prior to
	                                              adding in [dbo].[sma_servers]."
	    fk_sma_sql_server_hosts__server         sma_sql_server_hosts.server
	                                              -> sma_servers.server

	So the only order that works is:
	    instance_hosts -> instance_details -> sma_servers -> sma_sql_server_hosts	*/

/* ---------------------------------------------------------- instance_hosts -- */
MERGE dbo.instance_hosts AS t
USING (VALUES ('$(InventoryHost)'), ('$(MonitoredHost)')) AS s (host_name)
   ON t.host_name = s.host_name
WHEN NOT MATCHED BY TARGET THEN
    INSERT (host_name) VALUES (s.host_name);
PRINT 'dbo.instance_hosts seeded';
GO

/* ------------------------------------------------------ instance_details -- */
/*	dbo.tgr_dml__instance_details__prevent_bulk_udpate rejects UPDATE/DELETE
	touching more than five rows unless HOST_NAME() is
	'check-instance-availability.sh'. Two rows is fine.

	sqlmonitor_script_path is /opt/sqlmonitor on Linux, not C:\SQLMonitor.	*/
MERGE dbo.instance_details AS t
USING (VALUES
        ('$(InventoryHost)', '$(InventoryHost)'),
        ('$(MonitoredHost)', '$(MonitoredHost)')
      ) AS s (sql_instance, host_name)
   ON t.sql_instance = s.sql_instance AND t.is_alias = 0
WHEN NOT MATCHED BY TARGET THEN
    INSERT (sql_instance, sql_instance_port, is_alias, host_name, [database],
            collector_tsql_jobs_server, collector_powershell_jobs_server,
            data_destination_sql_instance, dba_group_mail_id,
            sqlmonitor_script_path, sqlmonitor_version,
            is_available, is_enabled, is_linked_server_working)
    VALUES (s.sql_instance, '1433', 0, s.host_name, 'DBA',
            s.sql_instance, s.sql_instance,
            '$(InventoryHost)', '$(DbaEmail)',
            '/opt/sqlmonitor', '1.1.0',
            1, 1, 1)
WHEN MATCHED AND (t.is_enabled = 0 OR t.sqlmonitor_script_path <> '/opt/sqlmonitor') THEN
    UPDATE SET is_enabled = 1,
               is_available = 1,
               sqlmonitor_script_path = '/opt/sqlmonitor',
               dba_group_mail_id = '$(DbaEmail)';
PRINT 'dbo.instance_details seeded';
GO

/* ----------------------------------------------------------- sma_servers -- */
/*	System-versioned temporal table: never write valid_from / valid_to.	*/
MERGE dbo.sma_servers AS t
USING (VALUES
        ('$(InventoryHost)', 'inventory',  'SQLMonitor inventory server'),
        ('$(MonitoredHost)', 'monitored',  'SQLMonitor monitored instance')
      ) AS s (server, role_name, friendly_name)
   ON t.server = s.server
WHEN NOT MATCHED BY TARGET THEN
    INSERT (server, domain, friendly_name, stability, priority, server_type,
            hadr_strategy, is_monitoring_enabled, is_onboarded, is_decommissioned)
    VALUES (s.server, 'local', s.friendly_name, 'dev', 2, 'SQLServer',
            'standalone', 1, 1, 0)
WHEN MATCHED AND (t.is_monitoring_enabled = 0 OR t.is_decommissioned = 1 OR t.is_onboarded = 0) THEN
    UPDATE SET is_monitoring_enabled = 1, is_onboarded = 1, is_decommissioned = 0;
PRINT 'dbo.sma_servers seeded';
GO

/* -------------------------------------------------- sma_sql_server_hosts -- */
MERGE dbo.sma_sql_server_hosts AS t
USING (VALUES
        ('$(InventoryHost)', '$(InventoryHost)'),
        ('$(MonitoredHost)', '$(MonitoredHost)')
      ) AS s (server, host_name)
   ON t.server = s.server AND t.host_name = s.host_name
WHEN NOT MATCHED BY TARGET THEN
    INSERT (server, host_name, is_quarantined, is_decommissioned)
    VALUES (s.server, s.host_name, 0, 0)
WHEN MATCHED AND t.is_decommissioned = 1 THEN
    UPDATE SET is_decommissioned = 0;
PRINT 'dbo.sma_sql_server_hosts seeded';
GO

SELECT [instance]   = CONVERT(varchar(20), sql_instance),
       [host]       = CONVERT(varchar(20), host_name),
       [db]         = CONVERT(varchar(10), [database]),
       [enabled]    = is_enabled,
       [available]  = is_available,
       [script_path]= CONVERT(varchar(20), sqlmonitor_script_path)
FROM dbo.instance_details
ORDER BY sql_instance;
GO

PRINT 'Inventory seed complete.';
GO
