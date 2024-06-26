USE [master]
go

declare @_alias_server nvarchar(500) = '192.168.100.21';
declare @_dba_database nvarchar(500) = 'DBA';

EXEC master.dbo.sp_addlinkedserver @server = @_alias_server, @srvproduct=N'', @provider=N'SQLNCLI', @datasrc=@_alias_server, @catalog=@_dba_database;

EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=@_alias_server,@useself=N'False',@locallogin=NULL,@rmtuser=N'grafana',@rmtpassword='grafana';

EXEC master.dbo.sp_serveroption @server=@_alias_server, @optname=N'data access', @optvalue=N'true';

EXEC master.dbo.sp_serveroption @server=@_alias_server, @optname=N'rpc', @optvalue=N'true';

EXEC master.dbo.sp_serveroption @server=@_alias_server, @optname=N'rpc out', @optvalue=N'true';

EXEC master.dbo.sp_serveroption @server=@_alias_server, @optname=N'connect timeout', @optvalue=N'0';

EXEC master.dbo.sp_serveroption @server=@_alias_server, @optname=N'collation name', @optvalue=null;

EXEC master.dbo.sp_serveroption @server=@_alias_server, @optname=N'query timeout', @optvalue=N'0';

EXEC master.dbo.sp_serveroption @server=@_alias_server, @optname=N'use remote collation', @optvalue=N'true';

EXEC master.dbo.sp_serveroption @server=@_alias_server, @optname=N'remote proc transaction promotion', @optvalue=N'true'
GO

