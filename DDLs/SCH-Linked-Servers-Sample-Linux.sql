/*
	Purpose:		Create the linked server FROM a Linux inventory server TO a
					monitored SQL Server instance, for the (dba) Get-AllServer*
					jobs.

	Why a separate file from SCH-Linked-Servers-Sample.sql:

	  1) Provider. SQLNCLI is not registered on SQL Server on Linux, so
	     @provider=N'SQLNCLI' fails there. The in-box OLE DB driver is
	     MSOLEDBSQL. This script picks the provider from
	     sys.dm_os_host_info.host_platform so the same file works either way.
	     (There is no SERVERPROPERTY('HostPlatform') - it returns NULL.)

	  2) Authentication. "Windows integrated authentication for linked servers"
	     is explicitly unsupported on Linux, so @useself must stay 'False' with
	     an explicit remote SQL login. See
	     https://learn.microsoft.com/sql/linux/sql-server-linux-editions-and-components-2022#unsupported-features-and-services

	  3) Only SQL Server data sources are supported as linked servers on Linux.
	     That is all SQLMonitor needs.

	Placeholders replaced by SQLMonitor/linux/install-inventory.sh:
	    YourSqlInstanceNameHere  - linked server name (instance, no port)
	    YourDataSourceHere       - network address, "host" or "host,port"
	    YourRemoteLoginHere      - remote SQL login (default: grafana)
	    YourRemotePasswordHere   - its password
	    YourCatalogHere          - default catalog (default: DBA)
*/

USE [master]
GO

SET NOCOUNT ON;

DECLARE @_linked_server  sysname       = N'YourSqlInstanceNameHere';
DECLARE @_data_source    nvarchar(400) = N'YourDataSourceHere';
DECLARE @_remote_login   sysname       = N'YourRemoteLoginHere';
DECLARE @_remote_password nvarchar(256) = N'YourRemotePasswordHere';
DECLARE @_catalog        sysname       = N'YourCatalogHere';

DECLARE @_host_platform  nvarchar(50)  = (SELECT TOP 1 CONVERT(nvarchar(50), host_platform) FROM sys.dm_os_host_info);
DECLARE @_provider       sysname       = CASE WHEN @_host_platform = N'Linux' THEN N'MSOLEDBSQL' ELSE N'SQLNCLI' END;

IF EXISTS (SELECT * FROM sys.servers WHERE name = @_linked_server AND is_linked = 1)
BEGIN
    PRINT 'Linked server ' + QUOTENAME(@_linked_server) + ' already exists - leaving it alone.';
END
ELSE
BEGIN
    PRINT 'Creating linked server ' + QUOTENAME(@_linked_server)
        + ' (host platform ' + ISNULL(@_host_platform, 'unknown')
        + ', provider ' + @_provider + ').';

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
END
GO

DECLARE @_linked_server sysname = N'YourSqlInstanceNameHere';
DECLARE @_remote_login  sysname = N'YourRemoteLoginHere';

/*	Encrypt the hop and trust the certificate. SQL Server on Linux presents a
	self-signed certificate unless one was configured, and the Get-AllServer*
	jobs would otherwise fail the TLS handshake.	*/
/*	T-SQL does not accept an expression as a stored-procedure argument, so the
	provider string has to be built into a variable first.	*/
DECLARE @_provider_string nvarchar(400) =
    N'Encrypt=yes;TrustServerCertificate=yes;User ID=' + @_remote_login;

IF (SELECT LEFT(CAST(SERVERPROPERTY('productversion') AS varchar),
                CHARINDEX('.', CAST(SERVERPROPERTY('productversion') AS varchar)) - 1)) > 12
    EXEC master.dbo.sp_serveroption @server = @_linked_server,
        @optname  = 'provider string',
        @optvalue = @_provider_string;

EXEC master.dbo.sp_serveroption @server = @_linked_server, @optname = N'collation compatible',            @optvalue = N'false';
EXEC master.dbo.sp_serveroption @server = @_linked_server, @optname = N'data access',                     @optvalue = N'true';
EXEC master.dbo.sp_serveroption @server = @_linked_server, @optname = N'dist',                            @optvalue = N'false';
EXEC master.dbo.sp_serveroption @server = @_linked_server, @optname = N'pub',                             @optvalue = N'false';
EXEC master.dbo.sp_serveroption @server = @_linked_server, @optname = N'rpc',                             @optvalue = N'true';
EXEC master.dbo.sp_serveroption @server = @_linked_server, @optname = N'rpc out',                         @optvalue = N'true';
EXEC master.dbo.sp_serveroption @server = @_linked_server, @optname = N'sub',                             @optvalue = N'false';
EXEC master.dbo.sp_serveroption @server = @_linked_server, @optname = N'connect timeout',                 @optvalue = N'0';
EXEC master.dbo.sp_serveroption @server = @_linked_server, @optname = N'collation name',                  @optvalue = NULL;
EXEC master.dbo.sp_serveroption @server = @_linked_server, @optname = N'lazy schema validation',          @optvalue = N'false';
EXEC master.dbo.sp_serveroption @server = @_linked_server, @optname = N'query timeout',                   @optvalue = N'0';
EXEC master.dbo.sp_serveroption @server = @_linked_server, @optname = N'use remote collation',            @optvalue = N'true';

/*	MS DTC is not available on SQL Server on Linux, so promoting a linked
	server call into a distributed transaction can only fail. The Get-AllServer*
	jobs never need it, so promotion stays off.	*/
EXEC master.dbo.sp_serveroption @server = @_linked_server,
    @optname  = N'remote proc transaction promotion',
    @optvalue = N'false';
GO
