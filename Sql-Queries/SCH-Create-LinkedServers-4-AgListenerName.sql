USE [master]
go

declare @_alias_server_name nvarchar(500) = 'Facebook';
declare @_alias_server_ip nvarchar(500) = '192.168.100.21';
declare @_dba_database nvarchar(500) = 'DBA';

EXEC master.dbo.sp_addlinkedserver @server = @_alias_server_name, @srvproduct=N'', @provider=N'SQLNCLI', @datasrc=@_alias_server_ip, @catalog=@_dba_database;

EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=@_alias_server_name, @useself=N'False',@locallogin=NULL,@rmtuser=N'grafana',@rmtpassword='grafana';

EXEC master.dbo.sp_serveroption @server=@_alias_server_name, @optname=N'data access', @optvalue=N'true';

EXEC master.dbo.sp_serveroption @server=@_alias_server_name, @optname=N'rpc', @optvalue=N'true';

EXEC master.dbo.sp_serveroption @server=@_alias_server_name, @optname=N'rpc out', @optvalue=N'true';

EXEC master.dbo.sp_serveroption @server=@_alias_server_name, @optname=N'connect timeout', @optvalue=N'0';

EXEC master.dbo.sp_serveroption @server=@_alias_server_name, @optname=N'collation name', @optvalue=null;

EXEC master.dbo.sp_serveroption @server=@_alias_server_name, @optname=N'query timeout', @optvalue=N'0';

EXEC master.dbo.sp_serveroption @server=@_alias_server_name, @optname=N'use remote collation', @optvalue=N'true';

EXEC master.dbo.sp_serveroption @server=@_alias_server_name, @optname=N'remote proc transaction promotion', @optvalue=N'true'
GO

