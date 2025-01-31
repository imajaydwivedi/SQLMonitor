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

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_check_instance_availability')
    EXEC ('CREATE PROC dbo.usp_check_instance_availability AS SELECT ''stub version, to be replaced''')
GO

-- DROP PROCEDURE dbo.usp_check_instance_availability
go

ALTER PROCEDURE dbo.usp_check_instance_availability
(	@verbose tinyint = 0 /* display debugging messages. 0 = No messages. 1 = Only print messages. 2 = Print & Table Results */
	,@test_all_servers bit = 0 /* Check availability for all servers ignoring dbo.instance_details.is_available column */
)
	--WITH EXECUTE AS OWNER --,RECOMPILE
AS
BEGIN

	/*
		Version:		2024-03-31
		Date:			2024-02-20 - Enhancement#29 - Add additional verification step for Instance-Availability apart from job [(dba) Check-InstanceAvailability]
		Help:			https://www.sommarskog.se/grantperm.html
						https://stackoverflow.com/questions/10191193/how-to-test-linkedservers-connectivity-in-tsql

		exec dbo.usp_check_instance_availability @verbose = 2, @test_all_servers = 1
	*/
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET LOCK_TIMEOUT 60000; -- 60 seconds

	--DECLARE @_tbl_output_columns table (column_name varchar(125));
	DECLARE @_params NVARCHAR(max);
	DECLARE @_sql NVARCHAR(max);

	declare @_srv_name	nvarchar (125);

	declare @_result table (sql_instance nvarchar(125), at_server_name nvarchar(125), [database] nvarchar(125));

	IF @verbose >= 2
	BEGIN
		select distinct [RunningQuery] = 'Cursor-Servers', [srvname] = sql_instance
		from dbo.instance_details id
		where is_enabled = 1 and is_alias = 0
		and (@test_all_servers = 1 or is_available = 0)
		and id.host_name <> CONVERT(varchar,COALESCE(SERVERPROPERTY('ComputerNamePhysicalNetBIOS'),SERVERPROPERTY('ServerName')));
	END

	DECLARE cur_servers CURSOR LOCAL FORWARD_ONLY FOR
		select distinct [srvname] = sql_instance
		from dbo.instance_details id
		where is_enabled = 1 and is_alias = 0
		and (@test_all_servers = 1 or is_available = 0)
		and id.host_name <> CONVERT(varchar,COALESCE(SERVERPROPERTY('ComputerNamePhysicalNetBIOS'),SERVERPROPERTY('ServerName')));

	OPEN cur_servers;
	FETCH NEXT FROM cur_servers INTO @_srv_name;

	set @_params = N'@srv_name nvarchar(125)';

	--set quoted_identifier off;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		if @verbose > 0
			print char(10)+'***** Looping through '+quotename(@_srv_name)+' *******';

		-- Loop through servers, and test linked server connectivity
		if ( 1=1 )
		begin
			begin try
				if @verbose >= 1
					print 'Attempt [sys].[sp_testlinkedserver] on linked server..';
				exec sys.sp_testlinkedserver @_srv_name;

				if @verbose >= 1
					print 'Execute OPENQUERY() on linked server..';
				set @_sql = "select	[at_server_name] = CONVERT(varchar,  @@SERVERNAME), [database] = db_name();";
				set @_sql = 'select [sql_instance] = @srv_name,* from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
				
				insert @_result (sql_instance, at_server_name, [database])
				exec sp_executesql @_sql, @_params, @srv_name = @_srv_name;
			end try
			begin catch
				print '	ERROR => Linked Server '+quotename(@_srv_name)+' not connecting.';
				if @verbose >= 1
				begin
					print  '	ErrorNumber => '+convert(varchar,ERROR_NUMBER());
					print  '	ErrorSeverity => '+convert(varchar,ERROR_SEVERITY());
					print  '	ErrorState => '+convert(varchar,ERROR_STATE());
					--print  '	ErrorProcedure => '+ERROR_PROCEDURE();
					print  '	ErrorLine => '+convert(varchar,ERROR_LINE());
					print  '	ErrorMessage => '+ERROR_MESSAGE();
				end
			end catch;
		end

		FETCH NEXT FROM cur_servers INTO @_srv_name;
	END
	
	
	CLOSE cur_servers;  
	DEALLOCATE cur_servers;

	IF @verbose >= 2
	BEGIN
		if @verbose >= 1
			print 'Resultset of "Online-Servers"..';

		select q.[RunningQuery], r.*
		from @_result r
		full outer join
			(select RunningQuery = 'Online-Servers') q
			on 1=1;
	END

	if @verbose >= 1
		print 'Updating dbo.instance_details for online servers..';

	--select RunningQuery = 'Join-Result-InstanceDetails', r.*, id.*
	update id set is_available = 1
	from @_result r
	inner join dbo.instance_details id
		on id.sql_instance = r.sql_instance
		and id.is_enabled = 1
		and id.is_alias = 0
		and id.is_available = 0;

	print 'Updated [is_available] for '+convert(varchar,@@rowcount)+' rows in dbo.instance_details.';
END
set quoted_identifier on;
GO

exec dbo.usp_check_instance_availability --@verbose = 2, @test_all_servers = 1
go