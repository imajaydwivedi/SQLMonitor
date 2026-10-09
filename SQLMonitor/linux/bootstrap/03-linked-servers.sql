/*
	Creates one linked server FROM the Linux inventory instance TO a monitored
	instance, the way the (dba) Get-AllServer* jobs need it.

	This is the parameterised twin of DDLs/SCH-Linked-Servers-Sample-Linux.sql -
	same provider choice and same options, driven by sqlcmd -v instead of the
	placeholder substitution install-inventory.sh does.

	sqlcmd variables:
	    LinkedServer     linked server name (== the remote instance name)
	    DataSource       network address, "host" or "host,port"
	    RemoteLogin      SQL login to impersonate remotely (grafana)
	    RemotePassword   its password
	    Catalog          default catalog (DBA)
*/

USE [master];
GO
SET NOCOUNT ON;
GO

DECLARE @_linked_server   sysname       = N'$(LinkedServer)';
DECLARE @_data_source     nvarchar(400) = N'$(DataSource)';
DECLARE @_remote_login    sysname       = N'$(RemoteLogin)';
DECLARE @_remote_password nvarchar(256) = N'$(RemotePassword)';
DECLARE @_catalog         sysname       = N'$(Catalog)';

/*	There is no SERVERPROPERTY('HostPlatform') - it returns NULL.
	sys.dm_os_host_info is the supported source.
	SQLNCLI is not registered on SQL Server on Linux; MSOLEDBSQL is in-box.	*/
DECLARE @_host_platform nvarchar(50) = (SELECT TOP 1 CONVERT(nvarchar(50), host_platform) FROM sys.dm_os_host_info);
DECLARE @_provider      sysname      = CASE WHEN @_host_platform = N'Linux' THEN N'MSOLEDBSQL' ELSE N'SQLNCLI' END;

IF EXISTS (SELECT * FROM sys.servers WHERE name = @_linked_server AND is_linked = 1)
BEGIN
    PRINT 'Dropping existing linked server ' + QUOTENAME(@_linked_server);
    EXEC master.dbo.sp_dropserver @server = @_linked_server, @droplogins = 'droplogins';
END

PRINT 'Creating linked server ' + QUOTENAME(@_linked_server)
    + ' -> ' + @_data_source
    + ' (host platform ' + ISNULL(@_host_platform, 'unknown') + ', provider ' + @_provider + ')';

EXEC master.dbo.sp_addlinkedserver
    @server     = @_linked_server,
    @srvproduct = N'',
    @provider   = @_provider,
    @datasrc    = @_data_source,
    @catalog    = @_catalog;

EXEC master.dbo.sp_addlinkedsrvlogin
    @rmtsrvname  = @_linked_server,
    @useself     = N'False',
    @locallogin  = NULL,
    @rmtuser     = @_remote_login,
    @rmtpassword = @_remote_password;
GO

DECLARE @_linked_server sysname = N'$(LinkedServer)';
DECLARE @_remote_login  sysname = N'$(RemoteLogin)';

/*	SQL Server on Linux presents a self-signed certificate unless one was
	configured, so the hop must trust it or the handshake fails.	*/
/*	T-SQL does not accept an expression as a stored-procedure argument, so the
	provider string has to be built into a variable first.	*/
DECLARE @_provider_string nvarchar(400) =
    N'Encrypt=yes;TrustServerCertificate=yes;User ID=' + @_remote_login;

EXEC master.dbo.sp_serveroption @server = @_linked_server,
    @optname  = 'provider string',
    @optvalue = @_provider_string;

EXEC master.dbo.sp_serveroption @server = @_linked_server, @optname = N'collation compatible',   @optvalue = N'false';
EXEC master.dbo.sp_serveroption @server = @_linked_server, @optname = N'data access',            @optvalue = N'true';
EXEC master.dbo.sp_serveroption @server = @_linked_server, @optname = N'rpc',                    @optvalue = N'true';
EXEC master.dbo.sp_serveroption @server = @_linked_server, @optname = N'rpc out',                @optvalue = N'true';
EXEC master.dbo.sp_serveroption @server = @_linked_server, @optname = N'connect timeout',        @optvalue = N'0';
EXEC master.dbo.sp_serveroption @server = @_linked_server, @optname = N'query timeout',          @optvalue = N'0';
EXEC master.dbo.sp_serveroption @server = @_linked_server, @optname = N'use remote collation',   @optvalue = N'true';
EXEC master.dbo.sp_serveroption @server = @_linked_server, @optname = N'lazy schema validation', @optvalue = N'false';

/*	No MS DTC on Linux, so promotion can only fail.	*/
EXEC master.dbo.sp_serveroption @server = @_linked_server,
    @optname = N'remote proc transaction promotion', @optvalue = N'false';
GO

/* ------------------------------- prove the hop actually works ------------- */
DECLARE @_linked_server sysname = N'$(LinkedServer)';
DECLARE @_sql nvarchar(max);
BEGIN TRY
    EXEC sys.sp_testlinkedserver @_linked_server;
    PRINT 'sp_testlinkedserver OK for ' + QUOTENAME(@_linked_server);

    SET @_sql = N'select [remote_server] = srv.srvname, [remote_db] = q.db
                  from (select db = [name] from ' + QUOTENAME(@_linked_server) + N'.master.sys.databases where [name] = ''DBA'') q
                  cross join (select srvname = @ls) srv;';
    EXEC sp_executesql @_sql, N'@ls sysname', @ls = @_linked_server;
END TRY
BEGIN CATCH
    PRINT '*** Linked server ' + QUOTENAME(@_linked_server) + ' FAILED: ' + ERROR_MESSAGE();
    THROW;
END CATCH
GO
