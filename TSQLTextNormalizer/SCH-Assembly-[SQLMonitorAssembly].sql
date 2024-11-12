/*	https://stackoverflow.com/a/4975299
	https://sqldatapartners.com/2021/09/15/episode-233-scriptdom/
	How to normalize SQL Text similar to tools like ClearTrace, RML Utilities

	Path of assembly file
	C:\SQLMonitor\TSQLTextNormalizer.dll

	MS_SQLEnableSystemAssemblyLoadingKey
	SQLMonitor_TSQLTextNormalizer_Key

	select *
	from sys.asymmetric_keys ak
	join sys.server_principals p
	on p.sid = ak.sid
*/

USE master;
GO
--DROP ASYMMETRIC KEY SQLMonitor_TSQLTextNormalizer_Key
CREATE ASYMMETRIC KEY SQLMonitor_TSQLTextNormalizer_Key FROM EXECUTABLE FILE = 'C:\SQLMonitor\TSQLTextNormalizer.dll';
--DROP ASYMMETRIC KEY SQLMonitor_ScriptDom_Key
CREATE ASYMMETRIC KEY SQLMonitor_ScriptDom_Key FROM EXECUTABLE FILE = 'C:\SQLMonitor\Microsoft.SqlServer.TransactSql.ScriptDom.dll';
GO
--DROP LOGIN SQLMonitor_TSQLTextNormalizer_Key_Login
CREATE LOGIN SQLMonitor_TSQLTextNormalizer_Key_Login FROM ASYMMETRIC KEY SQLMonitor_TSQLTextNormalizer_Key;
--DROP LOGIN SQLMonitor_ScriptDom_Key_Login
CREATE LOGIN SQLMonitor_ScriptDom_Key_Login FROM ASYMMETRIC KEY MS_SQLEnableSystemAssemblyLoadingKey;
--CREATE LOGIN SQLMonitor_ScriptDom_Key_Login FROM ASYMMETRIC KEY MS_SQLEnableSystemAssemblyLoadingKey;
GO

GRANT UNSAFE ASSEMBLY TO SQLMonitor_TSQLTextNormalizer_Key_Login;
GRANT UNSAFE ASSEMBLY TO SQLMonitor_ScriptDom_Key_Login;
GO

USE DBA;
GO
--DROP USER SQLMonitor_TSQLTextNormalizer_Key_Login
CREATE USER SQLMonitor_TSQLTextNormalizer_Key_Login FOR LOGIN SQLMonitor_TSQLTextNormalizer_Key_Login;
--DROP USER SQLMonitor_ScriptDom_Key_Login
CREATE USER SQLMonitor_ScriptDom_Key_Login FOR LOGIN SQLMonitor_ScriptDom_Key_Login;
GO

--DROP ASSEMBLY TSQLTextNormalizer
CREATE ASSEMBLY TSQLTextNormalizer FROM 'C:\SQLMonitor\TSQLTextNormalizer.dll' WITH PERMISSION_SET = UNSAFE;
GO

-- drop function normalized_sql_text
CREATE FUNCTION normalized_sql_text(@sql_text NVARCHAR(max), @compat_level int,@is_case_sensitive bit)
RETURNS NVARCHAR(max) WITH EXECUTE AS CALLER, RETURNS NULL ON NULL INPUT
AS EXTERNAL NAME [TSQLTextNormalizer].[TSQLTextNormalizer.StringOp].[sqlsig]
GO

EXEC sp_configure 'show advanced options', 1
RECONFIGURE;
EXEC sp_configure 'clr strict security', 0;
RECONFIGURE;
Go
EXEC sp_configure 'clr enabled', 1;
RECONFIGURE;

select * from sys.configurations c
where c.name like '%clr%'

-- select sqlsig = DBA.dbo.normalized_sql_text('exec sp_WhoIsActive 110',150,0)

declare @c_sql_text nvarchar(max);
declare cur_rows cursor local fast_forward for
	select top 100 sql_text
	from DBA.dbo.xevent_metrics rc
	where rc.event_time between dateadd(hour,-1,getdate()) and getdate()
	order by row_id;

open cur_rows;
fetch next from cur_rows into @c_sql_text;
while @@fetch_status = 0
begin
	select convert(xml,(select @c_sql_text for xml path ('query'))) as [sql_text-2-normalize];
	begin try
		select sqlsig = dbo.sqlReplace(@c_sql_text,150,0);
	end try
	begin catch
		select error_message() as err_Message;
	end catch
	fetch next from cur_rows into @c_sql_text;
end
close cur_rows
deallocate cur_rows
go




