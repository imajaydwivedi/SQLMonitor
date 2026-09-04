/*
	Applied to EVERY instance in the test rig (inventory and monitored alike),
	before any SQLMonitor DDL.

	sqlcmd variables the caller must supply with -v:
	    GrafanaPassword      password for the read-only [grafana] login
	    InventoryLogin       login the bash scripts connect as
	    InventoryPassword    its password

	This is a THROWAWAY TEST RIG. [$(InventoryLogin)] is made sysadmin so the
	installer, the DDLs and msdb job creation all just work. Do not copy this
	file into anything real - see README.md "Security".
*/

SET NOCOUNT ON;
GO

/* ---------------------------------------------------------------- DBA db -- */
IF DB_ID('DBA') IS NULL
BEGIN
    PRINT 'Creating database [DBA]';
    EXEC ('CREATE DATABASE [DBA]');
END
ELSE
    PRINT 'Database [DBA] already exists';
GO

/*	SQL Server Express creates databases with AUTO_CLOSE = ON, which blocks the
	MEMORY_OPTIMIZED_DATA filegroup that SCH-Create-Inventory-Specific-Objects.sql
	adds, and would cripple a monitoring database anyway.
	SCH-Create-Inventory-Specific-Objects.sql fixes this too; doing it here means
	a monitored instance gets the same treatment.	*/
IF EXISTS (SELECT * FROM sys.databases WHERE name = 'DBA' AND is_auto_close_on = 1)
BEGIN
    PRINT 'Setting AUTO_CLOSE OFF on [DBA] (SQLExpress default)';
    ALTER DATABASE [DBA] SET AUTO_CLOSE OFF WITH NO_WAIT;
END
GO

/* ------------------------------------------------------- service logins --- */
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = '$(InventoryLogin)')
BEGIN
    PRINT 'Creating login [$(InventoryLogin)]';
    EXEC ('CREATE LOGIN [$(InventoryLogin)] WITH PASSWORD = ''$(InventoryPassword)'', CHECK_POLICY = OFF');
END
ELSE
    EXEC ('ALTER LOGIN [$(InventoryLogin)] WITH PASSWORD = ''$(InventoryPassword)''');
GO

IF NOT EXISTS (SELECT * FROM sys.server_role_members rm
               JOIN sys.server_principals r ON r.principal_id = rm.role_principal_id AND r.name = 'sysadmin'
               JOIN sys.server_principals m ON m.principal_id = rm.member_principal_id AND m.name = '$(InventoryLogin)')
BEGIN
    PRINT 'Granting sysadmin to [$(InventoryLogin)] (TEST RIG ONLY)';
    ALTER SERVER ROLE [sysadmin] ADD MEMBER [$(InventoryLogin)];
END
GO

/*	[grafana] is what the linked servers impersonate and what the Grafana
	datasource uses. Read-only, plus EXECUTE on the reporting procs - this
	mirrors step 56__GrafanaLogin of Install-SQLMonitor.ps1.	*/
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'grafana')
BEGIN
    PRINT 'Creating login [grafana]';
    EXEC ('CREATE LOGIN [grafana] WITH PASSWORD = ''$(GrafanaPassword)'', CHECK_POLICY = OFF, DEFAULT_DATABASE = [DBA]');
END
ELSE
    EXEC ('ALTER LOGIN [grafana] WITH PASSWORD = ''$(GrafanaPassword)''');
GO

/*	VIEW SERVER STATE so the inventory can read sys.dm_os_host_info and the
	collection procs can read the DMVs over the linked server.	*/
GRANT VIEW SERVER STATE TO [grafana];
GRANT VIEW ANY DEFINITION TO [grafana];
GO

USE [DBA];
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'grafana')
BEGIN
    PRINT 'Creating user [grafana] in [DBA]';
    CREATE USER [grafana] FOR LOGIN [grafana];
END
GO

ALTER ROLE [db_datareader] ADD MEMBER [grafana];
GO

USE [master];
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'grafana')
    CREATE USER [grafana] FOR LOGIN [grafana];
GO

USE [msdb];
GO

/*	The inventory's Get-AllServerSqlAgentJobs pulls msdb job history from every
	monitored instance over the linked server as [grafana].	*/
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'grafana')
    CREATE USER [grafana] FOR LOGIN [grafana];
GO

ALTER ROLE [db_datareader] ADD MEMBER [grafana];
GO

PRINT 'Instance common bootstrap complete.';
GO
