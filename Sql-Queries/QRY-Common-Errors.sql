/*	ERROR 01: BEGIN	********************************** */
Msg 50000, Level 11, State 2, Server SomeServerNameHere, Procedure master.dbo.sp_BlitzIndex, Line 6167
Could not find server 'SomeServerNameHere' in sys.servers. Verify that the correct server name was specified. If necessary, execute the stored procedure sp_addlinkedserver to add the server to sys.servers.
go

select *
from sys.servers
go

select /* Get old server name */ * from dbo.instance_details
go

sp_dropserver 'MyOldServerName'
GO
sp_addserver  'NewServerName',local
GO

EXEC sp_serveroption
  @server = 'NewServerName',
  @optname = 'DATA ACCESS',
  @optvalue = 'TRUE';
go
/*	ERROR 02: BEGIN	********************************** */
