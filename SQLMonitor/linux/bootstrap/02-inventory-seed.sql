/*
	Seeds the INVENTORY's own metadata so the (dba) Get-AllServer* jobs have
	something to collect. Applied to the INVENTORY instance only, after
	SCH-Create-All-Objects.sql and SCH-Create-Inventory-Specific-Objects.sql.

	Monitored instances are seeded one at a time by 02b-seed-monitored.sql, so
	an inventory with none configured yet is a clean, valid state.

	The inventory's own identity comes from SERVERPROPERTY('ServerName'), NOT
	from a caller-supplied hostname. dbo.usp_GetAllServerInfo decides whether a
	row is "this instance" by comparing it to the server's own name; seed
	anything else - a Kubernetes Service FQDN, a load-balancer address - and
	the inventory fails to recognise itself, tries to reach itself over a
	linked server that does not exist, and collects nothing.

	sqlcmd variables the caller must supply with -v:
	    DbaEmail   an address that is NOT one of the shipped @gmail.com placeholders

	Idempotent: safe to re-run.
*/

USE [DBA];
GO
SET NOCOUNT ON;
GO

/* ------------------------------------------------------------ sma_params -- */
/*	dbo.usp_wrapper_GetAllServerInfo does this, at
	SCH-usp_wrapper_GetAllServerInfo.sql:89 -

	    IF (@recipients IS NULL OR @recipients = 'dba_team@gmail.com') AND @verbose = 0
	        raiserror ('@recipients is mandatory parameter', 20, -1) with log;

	@recipients is read from sma_params.dba_team_email_id, whose shipped value
	IS 'dba_team@gmail.com', and the jobs all run with @verbose = 0. So every
	Get-AllServer* job fails with a severity-20 error until it is changed.

	And it is not the only one: usp_wrapper_populate_sma_sql_instance guards
	@dba_manager_email_id the same way, usp_send_login_expiry_emails guards the
	CTO/SRE addresses, and so on. Every shipped placeholder is an @gmail.com
	address, so rewrite them all rather than discovering them one severity-20
	at a time.	*/
UPDATE dbo.sma_params
SET param_value = '$(DbaEmail)'
WHERE param_key LIKE '%email%'
  AND param_value LIKE '%@gmail.com'
  AND param_value <> '$(DbaEmail)';

SELECT [seeded_email_param] = CONVERT(varchar(40), param_key),
       [value]              = CONVERT(varchar(40), param_value)
FROM dbo.sma_params
WHERE param_key LIKE '%email%'
ORDER BY param_key;
GO

/*	No Database Mail profile is assumed, so suppress the failure mails the
	wrapper procs would otherwise try (and fail) to send.	*/
UPDATE dbo.sma_params SET param_value = '0'
WHERE param_key = 'send_sqlmonitor_job_failure_mail' AND param_value <> '0';
GO

/*	ORDER MATTERS, and it is enforced by both a foreign key and a trigger:

	    fk_host_name                                instance_details.host_name
	                                                  -> instance_hosts.host_name
	    tgr_dml__fk_validation_sma_servers__server  "Server entry should exist in
	                                                  [dbo].[instance_details] prior
	                                                  to adding in [dbo].[sma_servers]."
	    fk_sma_sql_server_hosts__server             sma_sql_server_hosts.server
	                                                  -> sma_servers.server

	So: instance_hosts -> instance_details -> sma_servers -> sma_sql_server_hosts	*/

/* --------------------------------------------------------- instance_hosts -- */
DECLARE @_self sysname = CONVERT(sysname, SERVERPROPERTY('ServerName'));
PRINT 'Inventory identifies itself as [' + @_self + ']';

MERGE dbo.instance_hosts AS t
USING (VALUES (@_self)) AS s (host_name)
   ON t.host_name = s.host_name
WHEN NOT MATCHED BY TARGET THEN
    INSERT (host_name) VALUES (s.host_name);
GO

/* ------------------------------------------------------- instance_details -- */
/*	dbo.tgr_dml__instance_details__prevent_bulk_udpate rejects UPDATE/DELETE
	touching more than five rows unless HOST_NAME() is
	'check-instance-availability.sh'. One row is fine.

	sqlmonitor_script_path is /opt/sqlmonitor on Linux, not C:\SQLMonitor.	*/
DECLARE @_self sysname = CONVERT(sysname, SERVERPROPERTY('ServerName'));

MERGE dbo.instance_details AS t
USING (VALUES (@_self, @_self)) AS s (sql_instance, host_name)
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
WHEN MATCHED AND (t.is_enabled = 0 OR t.sqlmonitor_script_path <> '/opt/sqlmonitor') THEN
    UPDATE SET is_enabled = 1,
               is_available = 1,
               sqlmonitor_script_path = '/opt/sqlmonitor',
               dba_group_mail_id = '$(DbaEmail)';
PRINT 'dbo.instance_details seeded';
GO

/* ------------------------------------------------------------ sma_servers -- */
/*	System-versioned temporal table: never write valid_from / valid_to.	*/
DECLARE @_self sysname = CONVERT(sysname, SERVERPROPERTY('ServerName'));

MERGE dbo.sma_servers AS t
USING (VALUES (@_self, 'SQLMonitor inventory server')) AS s (server, friendly_name)
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

/* --------------------------------------------------- sma_sql_server_hosts -- */
DECLARE @_self sysname = CONVERT(sysname, SERVERPROPERTY('ServerName'));

MERGE dbo.sma_sql_server_hosts AS t
USING (VALUES (@_self, @_self)) AS s (server, host_name)
   ON t.server = s.server AND t.host_name = s.host_name
WHEN NOT MATCHED BY TARGET THEN
    INSERT (server, host_name, is_quarantined, is_decommissioned)
    VALUES (s.server, s.host_name, 0, 0)
WHEN MATCHED AND t.is_decommissioned = 1 THEN
    UPDATE SET is_decommissioned = 0;
PRINT 'dbo.sma_sql_server_hosts seeded';
GO

SELECT [instance]    = CONVERT(varchar(30), sql_instance),
       [host]        = CONVERT(varchar(30), host_name),
       [db]          = CONVERT(varchar(10), [database]),
       [enabled]     = is_enabled,
       [available]   = is_available,
       [script_path] = CONVERT(varchar(20), sqlmonitor_script_path)
FROM dbo.instance_details
ORDER BY sql_instance;
GO

PRINT 'Inventory seed complete.';
GO
