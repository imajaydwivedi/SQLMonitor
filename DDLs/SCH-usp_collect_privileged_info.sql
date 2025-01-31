IF APP_NAME() = 'Microsoft SQL Server Management Studio - Query'
BEGIN
	SET QUOTED_IDENTIFIER OFF;
	SET ANSI_PADDING ON;
	SET CONCAT_NULL_YIELDS_NULL ON;
	SET ANSI_WARNINGS ON;
	SET NUMERIC_ROUNDABORT OFF;
	SET ARITHABORT ON;
END
GO

IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_collect_privileged_info')
    EXEC ('CREATE PROC dbo.usp_collect_privileged_info AS SELECT ''stub version, to be replaced''')
GO

-- DROP PROCEDURE dbo.usp_collect_privileged_info
go

ALTER PROCEDURE dbo.usp_collect_privileged_info
(	@result_to_table nvarchar(125), /* table that need to be populated */
	@verbose tinyint = 0, /* display debugging messages. 0 = No messages. 1 = Only print messages. 2 = Print & Table Results */
	@truncate_table bit = 1, /* when enabled, table would be truncated */
	@has_staging_table bit = 1 /* when enabled, assume there is no staging table */
)
AS
BEGIN

	/*
		Version:		0.0.0
		Purpose:		Fetch information that need Sysadmin access in general & Save in some table.
		Modifications:	2023-08-30 - Initial Draft

		exec dbo.usp_collect_privileged_info
					@result_to_table = 'dbo.server_privileged_info',
					@truncate_table = 1,
					@has_staging_table = 0,
					@verbose = 2;
		https://stackoverflow.com/questions/10191193/how-to-test-linkedservers-connectivity-in-tsql
	*/
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET LOCK_TIMEOUT 60000; -- 60 seconds

	IF @result_to_table NOT IN ('dbo.server_privileged_info')
		THROW 50001, '''result_to_table'' Parameter value is invalid.', 1;		

	DECLARE @_sql NVARCHAR(max);
	DECLARE @_params NVARCHAR(max);
	DECLARE @_crlf NCHAR(2);
	DECLARE @_str_variable nvarchar(500);
	DECLARE @_int_variable int = 0;

	DECLARE @_srv_name	nvarchar (125);
	DECLARE @_at_server_name varchar (125);
	DECLARE @_staging_table nvarchar(125);

	SET @_staging_table = @result_to_table + (case when @has_staging_table = 1 then '__staging' else '' end);
	SET @_crlf = NCHAR(10)+NCHAR(13);

	IF @truncate_table = 1
	BEGIN
		SET @_sql = 'truncate table '+@_staging_table+';';
		IF @verbose >= 1
			PRINT @_sql;
		EXEC (@_sql);
	END

	-- dbo.server_privileged_info
	if @result_to_table = 'dbo.server_privileged_info'
	begin -- dbo.server_privileged_info
		set @_sql =  "
SET QUOTED_IDENTIFIER ON;
declare @host_distribution nvarchar(500);
declare @processor_name nvarchar(500);
declare @fqdn nvarchar(100);

exec usp_extended_results @host_distribution = @host_distribution output;
exec usp_extended_results @processor_name = @processor_name output;
exec usp_extended_results @fqdn = @fqdn output;

select	[host_name] = CONVERT(varchar,COALESCE(SERVERPROPERTY('ComputerNamePhysicalNetBIOS'),SERVERPROPERTY('ServerName'))),
		[host_distribution] = @host_distribution,
		[processor_name] = @processor_name,
		[fqdn] = (case when default_domain() = 'WORKGROUP' then 'WORKGROUP' ELSE @fqdn END);
"
		-- Decorate for remote query if LinkedServer
		if @verbose >= 1
			print @_crlf+@_sql+@_crlf;
		
		begin try
			insert into [dbo].[server_privileged_info]
			(	[host_name], [host_distribution], [processor_name], [fqdn] )
			exec (@_sql);
		end try
		begin catch
			-- print @_sql;
			print char(10)+char(13)+'Error occurred while executing below query on '+quotename(@_srv_name)+char(10)+'     '+@_sql;
			print  '	ErrorNumber => '+convert(varchar,ERROR_NUMBER());
			print  '	ErrorSeverity => '+convert(varchar,ERROR_SEVERITY());
			print  '	ErrorState => '+convert(varchar,ERROR_STATE());
			--print  '	ErrorProcedure => '+ERROR_PROCEDURE();
			print  '	ErrorLine => '+convert(varchar,ERROR_LINE());
			print  '	ErrorMessage => '+ERROR_MESSAGE();
		end catch
	end -- dbo.server_privileged_info

	IF @has_staging_table = 1
	BEGIN
		SET @_sql =
		'BEGIN TRAN
			TRUNCATE TABLE '+@result_to_table+';
			ALTER TABLE '+@result_to_table+'__staging SWITCH TO '+@result_to_table+';
		COMMIT TRAN';
		IF @verbose >= 1
			print @_crlf+@_sql+@_crlf;
		EXEC (@_sql);
	END

	PRINT 'Transaction Counts => '+convert(varchar,@@trancount);
END
set quoted_identifier on;
GO
