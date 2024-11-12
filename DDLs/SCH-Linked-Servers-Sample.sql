USE [master]
GO

EXEC master.dbo.sp_addlinkedserver @server = N'YourSqlInstanceNameHere', @srvproduct=N'', @provider=N'SQLNCLI', @datasrc=N'YourSqlInstanceNameHere', @catalog=N'DBA'

EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=N'YourSqlInstanceNameHere',@useself=N'False',@locallogin=NULL,@rmtuser=N'grafana',@rmtpassword='grafana'
GO

EXEC master.dbo.sp_serveroption @server=N'YourSqlInstanceNameHere', @optname=N'collation compatible', @optvalue=N'false'
GO

EXEC master.dbo.sp_serveroption @server=N'YourSqlInstanceNameHere', @optname=N'data access', @optvalue=N'true'
GO

EXEC master.dbo.sp_serveroption @server=N'YourSqlInstanceNameHere', @optname=N'dist', @optvalue=N'false'
GO

EXEC master.dbo.sp_serveroption @server=N'YourSqlInstanceNameHere', @optname=N'pub', @optvalue=N'false'
GO

EXEC master.dbo.sp_serveroption @server=N'YourSqlInstanceNameHere', @optname=N'rpc', @optvalue=N'true'
GO

EXEC master.dbo.sp_serveroption @server=N'YourSqlInstanceNameHere', @optname=N'rpc out', @optvalue=N'true'
GO

EXEC master.dbo.sp_serveroption @server=N'YourSqlInstanceNameHere', @optname=N'sub', @optvalue=N'false'
GO

EXEC master.dbo.sp_serveroption @server=N'YourSqlInstanceNameHere', @optname=N'connect timeout', @optvalue=N'0'
GO

EXEC master.dbo.sp_serveroption @server=N'YourSqlInstanceNameHere', @optname=N'collation name', @optvalue=null
GO

EXEC master.dbo.sp_serveroption @server=N'YourSqlInstanceNameHere', @optname=N'lazy schema validation', @optvalue=N'false'
GO

EXEC master.dbo.sp_serveroption @server=N'YourSqlInstanceNameHere', @optname=N'query timeout', @optvalue=N'0'
GO

EXEC master.dbo.sp_serveroption @server=N'YourSqlInstanceNameHere', @optname=N'use remote collation', @optvalue=N'true'
GO

EXEC master.dbo.sp_serveroption @server=N'YourSqlInstanceNameHere', @optname=N'remote proc transaction promotion', @optvalue=N'true'
GO


