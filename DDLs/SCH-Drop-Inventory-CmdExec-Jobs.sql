/*
	Purpose:		Remove the inventory SQL Agent jobs that cannot exist on a
					Linux inventory server.

	Background:		SQL Server on Linux does not implement the CmdExec or
					PowerShell SQL Agent subsystems, nor SQL Agent alerts:
					https://learn.microsoft.com/sql/linux/sql-server-linux-editions-and-components-2022#unsupported-features-and-services

					Every inventory job that only wrapped a T-SQL call in
					"sqlcmd -Q" was converted to the TSQL subsystem in place.
					The six jobs below actually ran an external process, so
					they moved out of SQL Agent entirely and are now driven by
					systemd timers on the inventory host:

					    (dba) Check-InstanceAvailability
					        -> sqlmonitor-check-instance-availability.timer
					    (dba) Update-SqlServerVersions
					        -> sqlmonitor-sqlserver-versions-update.timer
					    (dba) Populate Inventory Tables
					        -> sqlmonitor-populate-inventory-tables.timer
					    (dba) Stop-StuckSQLMonitorJobs
					        -> sqlmonitor-stop-stuck-sqlmonitor-jobs.timer
					    (dba) Update-SQLMonitorIP
					        -> sqlmonitor-update-sqlmonitor-ip.timer
					    (dba) Collect-AllServerAlertMessages
					        -> sqlmonitor-collect-all-server-alert-messages.timer

	When to run:	Automatically, by SQLMonitor/linux/install-inventory.sh.
					Also run it by hand when migrating an existing Windows
					inventory server onto Linux, so the dead jobs do not linger
					and fire failure alerts.

	Safe to rerun:	Yes. Each drop is guarded by an existence check.
*/

USE [msdb]
GO

SET NOCOUNT ON;

DECLARE @_jobs table (job_name nvarchar(255) not null primary key, replacement_timer nvarchar(255) not null);

INSERT INTO @_jobs (job_name, replacement_timer)
VALUES  (N'(dba) Check-InstanceAvailability',    N'sqlmonitor-check-instance-availability.timer'),
        (N'(dba) Update-SqlServerVersions',      N'sqlmonitor-sqlserver-versions-update.timer'),
        (N'(dba) Populate Inventory Tables',     N'sqlmonitor-populate-inventory-tables.timer'),
        (N'(dba) Stop-StuckSQLMonitorJobs',      N'sqlmonitor-stop-stuck-sqlmonitor-jobs.timer'),
        (N'(dba) Update-SQLMonitorIP',           N'sqlmonitor-update-sqlmonitor-ip.timer'),
        (N'(dba) Collect-AllServerAlertMessages', N'sqlmonitor-collect-all-server-alert-messages.timer');

DECLARE @_job_name nvarchar(255), @_replacement nvarchar(255);

DECLARE job_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT j.job_name, j.replacement_timer FROM @_jobs j;

OPEN job_cursor;
FETCH NEXT FROM job_cursor INTO @_job_name, @_replacement;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF EXISTS (SELECT * FROM msdb.dbo.sysjobs_view WHERE name = @_job_name)
    BEGIN
        PRINT 'Dropping job ' + QUOTENAME(@_job_name) + ' - replaced by ' + @_replacement;
        EXEC msdb.dbo.sp_delete_job @job_name = @_job_name, @delete_unused_schedule = 1;
    END
    ELSE
        PRINT 'Job ' + QUOTENAME(@_job_name) + ' not present - nothing to drop.';

    FETCH NEXT FROM job_cursor INTO @_job_name, @_replacement;
END

CLOSE job_cursor;
DEALLOCATE job_cursor;
GO

/*	Report any inventory job still using a subsystem the Linux Agent cannot
	run, so a partial migration is visible instead of silently failing.	*/
IF EXISTS (
        SELECT *
        FROM msdb.dbo.sysjobs j
        JOIN msdb.dbo.sysjobsteps s ON s.job_id = j.job_id
        JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id
        WHERE c.name = N'(dba) SQLMonitor'
          AND s.subsystem IN (N'CmdExec', N'PowerShell')
    )
BEGIN
    PRINT '';
    PRINT '*** WARNING: the following (dba) SQLMonitor job steps still use CmdExec/PowerShell,';
    PRINT '*** which SQL Server Agent on Linux does not support. They will never run.';

    SELECT [job_name] = j.name, [step_name] = s.step_name, s.subsystem, s.command
    FROM msdb.dbo.sysjobs j
    JOIN msdb.dbo.sysjobsteps s ON s.job_id = j.job_id
    JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id
    WHERE c.name = N'(dba) SQLMonitor'
      AND s.subsystem IN (N'CmdExec', N'PowerShell')
    ORDER BY j.name, s.step_id;
END
ELSE
    PRINT 'No (dba) SQLMonitor job step uses CmdExec or PowerShell. Inventory is Linux-clean.';
GO
