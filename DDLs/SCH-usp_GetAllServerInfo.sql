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

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_GetAllServerInfo')
    EXEC ('CREATE PROC dbo.usp_GetAllServerInfo AS SELECT ''stub version, to be replaced''')
GO

-- DROP PROCEDURE dbo.usp_GetAllServerInfo
go

ALTER PROCEDURE dbo.usp_GetAllServerInfo
(	@servers varchar(max) = null, /* comma separated list of servers to query */
	@blocked_threshold_seconds int = 60, 
	@output nvarchar(max) = null, /* comma separated list of columns required in output */
	@result_to_table nvarchar(125) = null, /* temp table that should be populated with result */
	@paginate bit = 0, /* when true, means this proc is running in multiple sessions. So table should not be truncated */
	@page_count int = 1, /* Divide the server count in these pages */
	@page_no int = 1, /* Compulate info for servers of this page */
	@verbose tinyint = 0 /* display debugging messages. 0 = No messages. 1 = Only print messages. 2 = Print & Table Results */
)
	--WITH EXECUTE AS OWNER --,RECOMPILE
AS
BEGIN

	/*
		Version:		2024-11-13
		Date:			2024-11-13 - Enhancement#4 - Get Max Server Memory in dbo.all_server_stable_info
						2024-06-05 - Enhancement#42 - Get [avg_disk_wait_ms]
						2023-08-17 - Enhancement#274 - Populate [is_linked_server_working]
						2023-07-14 - Enhancement#268 - Add tables sql_agent_job_stats & memory_clerks in Collection Latency Dashboard
						2023-06-19 - Enhancement#262 - Add is_enabled field
						2023-03-04 - Enhancement#245 - Add SQL Port Support
						2022-03-31 - Enhancement#227 - Add CollectionTime of Each Table Data
						2022-10-16 - Bug/Fix - Inventory server not appearing when Named Instance
						
		Help:			https://www.sommarskog.se/grantperm.html
						https://stackoverflow.com/questions/10191193/how-to-test-linkedservers-connectivity-in-tsql

		declare @srv_name varchar(125) = convert(varchar,serverproperty('MachineName'));
		exec dbo.usp_GetAllServerInfo @servers = @srv_name
		--exec dbo.usp_GetAllServerInfo @servers = 'Workstation,SqlPractice,SqlMonitor' ,@output = 'srv_name, os_start_time_utc'
		--exec dbo.usp_GetAllServerInfo @servers = 'SQLMONITOR' ,@output = 'system_high_memory_signal_state'
		

		exec dbo.usp_GetAllServerInfo 
				@servers = 'SqlPractice'
				,@output = 'memory_grants_pending'
				,@verbose = 2
	*/
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	declare @_start_time datetime2 = sysdatetime();
	declare @_crlf nchar(2) = char(10)+char(13);
	declare @_long_star_line varchar(500) = replicate('*',75);
	declare @_caller_program nvarchar(255);
	DECLARE	@_errorNumber int,
			@_errorSeverity int,
			@_errorState int,
			@_errorLine int,
			@_errorMessage nvarchar(4000);

	DECLARE @_tbl_servers table (srv_name varchar(125));
	DECLARE @_tbl_output_columns table (column_name varchar(125));
	DECLARE @_linked_server_failed bit = 0;
	DECLARE @_sql NVARCHAR(max);
	DECLARE @_isLocalHost bit = 0;
	create table #server_details (
			srv_name varchar(125), at_server_name varchar(125), machine_name varchar(125), server_name varchar(125), 
			ip varchar(30), domain varchar(125), host_name varchar(125), fqdn varchar(255), host_distribution varchar(200),  
			processor_name varchar(200), product_version varchar(30), edition varchar(50), sqlserver_start_time_utc datetime2, 
			os_cpu decimal(20,2), sql_cpu decimal(20,2), pcnt_kernel_mode decimal(20,2), page_faults_kb decimal(20,2), 
			blocked_counts int, blocked_duration_max_seconds bigint, total_physical_memory_kb bigint, 
			available_physical_memory_kb bigint, system_high_memory_signal_state varchar(20), 
			physical_memory_in_use_kb decimal(20,2), memory_grants_pending int, connection_count int, 
			active_requests_count int, waits_per_core_per_minute decimal(20,2), avg_disk_wait_ms decimal(20,2), [avg_disk_latency_ms] int,
			os_start_time_utc datetime2, cpu_count smallint, scheduler_count smallint, major_version_number smallint, 
			minor_version_number smallint, max_server_memory_mb int, page_life_expectancy int, memory_consumers int, 
			target_server_memory_kb bigint, total_server_memory_kb bigint,

			performance_counters__latency_minutes int, xevent_metrics__latency_minutes int, WhoIsActive__latency_minutes int,
			os_task_list__latency_minutes int, disk_space__latency_minutes int, file_io_stats__latency_minutes int,
			sql_agent_job_stats__latency_minutes int, memory_clerks__latency_minutes int, wait_stats__latency_minutes int, 
			BlitzIndex__latency_days int, BlitzIndex_Mode0__latency_days int, BlitzIndex_Mode1__latency_days int, 
			BlitzIndex_Mode4__latency_days int
		);

	declare @_srv_name	nvarchar (125);
	declare @_at_server_name	varchar (125);
	declare @_machine_name	varchar (125);
	declare @_server_name	varchar (125);
	declare @_ip	varchar (30);
	declare @_domain	varchar (125);
	declare @_host_name	varchar (125);
	declare @_fqdn varchar(225);
	declare @_host_distribution	varchar (200);
	declare @_processor_name	varchar (200);
	declare @_product_version	varchar (30);
	declare @_edition varchar(50);
	declare @_sqlserver_start_time_utc	datetime2;
	declare @_os_cpu	decimal(20,2);
	declare @_sql_cpu	decimal(20,2);
	declare @_pcnt_kernel_mode	decimal(20,2);
	declare @_page_faults_kb	decimal(20,2);
	declare @_blocked_counts	int;
	declare @_blocked_duration_max_seconds	bigint;
	declare @_total_physical_memory_kb	bigint;
	declare @_available_physical_memory_kb	bigint;
	declare @_system_high_memory_signal_state	varchar (20);
	declare @_physical_memory_in_use_kb	decimal(20,2);
	declare @_memory_grants_pending	int;
	declare @_connection_count	int;
	declare @_active_requests_count	int;
	declare @_waits_per_core_per_minute	decimal(20,2);
	declare @_avg_disk_wait_ms	decimal(20,2);
	declare @_avg_disk_latency_ms int;
	declare @_os_start_time_utc	datetime2;
	declare @_cpu_count int;
	declare @_scheduler_count int;
	declare @_major_version_number smallint;
	declare @_minor_version_number smallint;
	declare @_max_server_memory_mb int;
	declare @_page_life_expectancy int;
	declare @_memory_consumers int;
	declare @_target_server_memory_kb bigint;
	declare @_total_server_memory_kb bigint;

	declare @_BlitzIndex__latency_days int;
	declare @_BlitzIndex_Mode0__latency_days int;
	declare @_BlitzIndex_Mode1__latency_days int;
	declare @_BlitzIndex_Mode4__latency_days int;
	declare @_disk_space__latency_minutes int;
	declare @_file_io_stats__latency_minutes int;
	declare @_sql_agent_job_stats__latency_minutes int;
	declare @_memory_clerks__latency_minutes int;
	declare @_os_task_list__latency_minutes int;
	declare @_performance_counters__latency_minutes int;
	declare @_xevent_metrics__latency_minutes int;
	declare @_xevent_metrics_queries__latency_minutes int;
	declare @_wait_stats__latency_minutes int;
	declare @_WhoIsActive__latency_minutes int;
	declare @_rows_affected int;

	declare @_int_variable int;
	declare @_smallint_variable smallint;
	declare @_tinyint_variable tinyint;
	declare @_bigint_variable bigint;
	declare @_datetime_variable datetime;
	declare @_datetime2_variable datetime2;
	declare @_date_variable date;
	DECLARE @enable_lock_timeout bit = 1 /* when enabled, lock timeout is used for each remote query connection */

	if (@servers is null and @output is not null) or @verbose > 0
		select @enable_lock_timeout = convert(bit,param_value) from dbo.sma_params where param_key = 'usp_GetAllServerInfo-enable-LOCK_TIMEOUT';

	declare @_result table (col_bigint bigint null, col_int int null, col_varchar varchar(255) null, 
							col_decimal decimal(20,2) null, col_datetime datetime2 null, col_datetime2 datetime2 null);

	set @_caller_program = case when HOST_NAME() like '(dba) Get-AllServerInfo%'
								then HOST_NAME()
								else PROGRAM_NAME()
								end;

	IF @verbose >= 1
		PRINT 'Extracting server names from @servers ('+@servers+') parameter value..';
	;WITH t1(srv_name, [Servers]) AS 
	(
		SELECT	CAST(LEFT(@servers, CHARINDEX(',',@servers+',')-1) AS VARCHAR(500)) as srv_name,
				STUFF(@servers, 1, CHARINDEX(',',@servers+','), '') as [Servers]
		--
		UNION ALL
		--
		SELECT	CAST(LEFT([Servers], CHARINDEX(',',[Servers]+',')-1) AS VARChAR(500)) AS srv_name,
				STUFF([Servers], 1, CHARINDEX(',',[Servers]+','), '')  as [Servers]
		FROM t1
		WHERE [Servers] > ''	
	)
	INSERT @_tbl_servers (srv_name)
	SELECT ltrim(rtrim(srv_name))
	FROM t1
	OPTION (MAXRECURSION 32000);

	IF @verbose >= 2
	BEGIN
		SELECT @_int_variable = COUNT(1) FROM @_tbl_servers;
		PRINT 'No of servers to process => '+CONVERT(varchar,@_int_variable)+'';
		SELECT [RunningQuery] = 'select * from @_tbl_servers', *
		FROM @_tbl_servers;
	END

	-- Extract output column names
	;WITH t1(column_name, [Columns]) AS 
	(
		SELECT	CAST(LEFT(@output, CHARINDEX(',',@output+',')-1) AS VARCHAR(500)) as column_name,
				STUFF(@output, 1, CHARINDEX(',',@output+','), '') as [Columns]
		--
		UNION ALL
		--
		SELECT	CAST(LEFT([Columns], CHARINDEX(',',[Columns]+',')-1) AS VARChAR(500)) AS column_name,
				STUFF([Columns], 1, CHARINDEX(',',[Columns]+','), '')  as [Columns]
		FROM t1
		WHERE [Columns] > ''	
	)
	INSERT @_tbl_output_columns (column_name)
	SELECT ltrim(rtrim(column_name))
	FROM t1
	OPTION (MAXRECURSION 32000);

	IF @verbose >= 2
	BEGIN
		SELECT @_int_variable = COUNT(1) FROM @_tbl_output_columns;
		PRINT 'No of columns to return in result => '+CONVERT(varchar,@_int_variable)+'';
		SELECT [RunningQuery] = 'select * from @_tbl_output_columns', *
		FROM @_tbl_output_columns;
	END

	-- Populate table to get list of Servers to process
	if object_id('tempdb..#instance_details') is not null
		drop table #instance_details
	;with cte_instance_details as (
		select distinct [srvname] = sql_instance
		from dbo.instance_details
		where is_available = 1 and is_enabled = 1
		and	(	(	@servers is null
				and	is_alias = 0
				)
			or	(	@servers is not null
				and	(	sql_instance in (select srv_name from @_tbl_servers) 
					--or	source_sql_instance in (select srv_name from @_tbl_servers)
					)
				)
			)
	)
	,cte_instance_details_paged as (
		select srvname, page_no = NTILE(@page_count) over (order by srvname)
		from cte_instance_details
	)
	select srvname
	into #instance_details
	from cte_instance_details_paged
	where 1=1
		and (	@paginate = 0
			or	( @paginate = 1 and page_no = @page_no )
			);

	IF @verbose >= 2
	BEGIN
		select [RunningQuery] = 'Cursor-Servers', srvname
		from #instance_details
	END

	DECLARE cur_servers CURSOR LOCAL FORWARD_ONLY FOR
		select srvname
		from #instance_details;

	OPEN cur_servers;
	FETCH NEXT FROM cur_servers INTO @_srv_name;
	
	--set quoted_identifier off;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		if @verbose > 0
			print char(10)+'***** Looping through '+quotename(@_srv_name)+' *******';
		set @_linked_server_failed = 0;
		set @_at_server_name = NULL;
		set @_machine_name = NULL;
		set @_server_name = NULL;
		set @_ip = NULL;
		set @_domain = NULL;
		set @_host_name = NULL;
		set @_fqdn = NULL;
		set @_host_distribution = NULL;
		set @_processor_name = NULL;
		set @_product_version = NULL;
		set @_edition = NULL;
		set @_sqlserver_start_time_utc = NULL;
		set @_os_cpu = NULL;
		set @_sql_cpu = NULL;
		set @_pcnt_kernel_mode = NULL;
		set @_page_faults_kb = NULL;
		set @_blocked_counts = NULL;
		set @_blocked_duration_max_seconds = NULL;
		set @_total_physical_memory_kb = NULL;
		set @_available_physical_memory_kb = NULL;
		set @_system_high_memory_signal_state = NULL;
		set @_physical_memory_in_use_kb = NULL;
		set @_memory_grants_pending = NULL;
		set @_connection_count = NULL;
		set @_active_requests_count = NULL;
		set @_waits_per_core_per_minute = NULL;
		set @_avg_disk_wait_ms = NULL;
		set @_avg_disk_latency_ms = NULL;
		set @_os_start_time_utc	= NULL;
		set @_cpu_count = NULL;
		set @_scheduler_count = NULL;
		set @_major_version_number = NULL;
		set @_minor_version_number = NULL;
		set @_max_server_memory_mb = NULL;
		set @_page_life_expectancy = NULL;
		set @_memory_consumers = NULL;
		set @_target_server_memory_kb = NULL;
		set @_total_server_memory_kb = NULL;
		set @_BlitzIndex__latency_days = NULL;
		set @_BlitzIndex_Mode0__latency_days = NULL;
		set @_BlitzIndex_Mode1__latency_days = NULL;
		set @_BlitzIndex_Mode4__latency_days = NULL;
		set @_disk_space__latency_minutes = NULL;
		set @_file_io_stats__latency_minutes = NULL;
		set @_sql_agent_job_stats__latency_minutes = NULL;
		set @_memory_clerks__latency_minutes = NULL;
		set @_os_task_list__latency_minutes = NULL;
		set @_performance_counters__latency_minutes = NULL;
		set @_xevent_metrics__latency_minutes = NULL;
		set @_xevent_metrics_queries__latency_minutes = NULL;
		set @_wait_stats__latency_minutes = NULL;
		set @_WhoIsActive__latency_minutes = NULL;

		-- If not local server
		if ( (CONVERT(varchar,SERVERPROPERTY('MachineName')) = @_srv_name) 
			or (CONVERT(varchar,SERVERPROPERTY('ServerName')) = @_srv_name)
			)
		begin
			set @_isLocalHost = 1;
			set @_linked_server_failed = 0;
		end
		else
		begin
			set @_isLocalHost = 0
			begin try
				exec sys.sp_testlinkedserver @_srv_name;
			end try
			begin catch
				set @_errorMessage = 'Linked Server '+quotename(@_srv_name)+' not connecting.';
				print '	ERROR => Linked Server '+quotename(@_srv_name)+' not connecting.';

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'sys.sp_testlinkedserver '+@_srv_name, [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				if @verbose >= 1
				begin
					print  '	ErrorNumber => '+convert(varchar,ERROR_NUMBER());
					print  '	ErrorSeverity => '+convert(varchar,ERROR_SEVERITY());
					print  '	ErrorState => '+convert(varchar,ERROR_STATE());
					--print  '	ErrorProcedure => '+ERROR_PROCEDURE();
					print  '	ErrorLine => '+convert(varchar,ERROR_LINE());
					print  '	ErrorMessage => '+ERROR_MESSAGE();
				end
				set @_linked_server_failed = 1;
				--fetch next from cur_servers into @_srv_name;
				--continue;
			end catch;
		end


		if ( (@_isLocalHost = 1) or (@_linked_server_failed = 0) )
		begin
			if exists (select 1/0 from dbo.instance_details id where is_linked_server_working = 0 
										and (	id.sql_instance = @_srv_name or	(id.source_sql_instance = @_srv_name and @_isLocalHost = 1)	)
					)
			begin
				if @verbose >= 1
					print 'Update [is_linked_server_working] flag if required for '+quotename(@_srv_name);
				set @_sql = "
				update id set [is_linked_server_working] = 1
				from dbo.instance_details id
				where [is_linked_server_working] = 0
					and (	id.sql_instance = @_srv_name
						or	(id.source_sql_instance = @_srv_name and @_isLocalHost = 1)
						);
				";

				exec sp_executesql @_sql, N'@_srv_name nvarchar(125), @_isLocalHost bit', @_srv_name = @_srv_name, @_isLocalHost = @_isLocalHost;
			end
		end
		
		if(@_linked_server_failed = 1)
		begin
			if exists (select 1/0 from dbo.instance_details where is_linked_server_working = 1 and sql_instance = @_srv_name)
			begin
				if @verbose >= 1
					print 'Update [is_linked_server_working] flag if required for '+quotename(@_srv_name);
				set @_sql = "
				update id set [is_linked_server_working] = 0
				from dbo.instance_details id
				where [is_linked_server_working] = 1
					and id.sql_instance = @_srv_name;
				";

				exec sp_executesql @_sql, N'@_srv_name nvarchar(125)', @_srv_name = @_srv_name;
			end
		end


		-- [@@SERVERNAME] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and (@output is null or exists (select * from @_tbl_output_columns where column_name = 'at_server_name'))
		begin
			delete from @_result;
			set @_sql = "SELECT	[at_server_name] = CONVERT(varchar,  @@SERVERNAME )";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_varchar)
				exec (@_sql);

				-- set @_ip
				select @_at_server_name = col_varchar from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'at_server_name', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [machine_name] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and (@output is null or exists (select * from @_tbl_output_columns where column_name = 'machine_name'))
		begin
			delete from @_result;
			set @_sql = "select CONVERT(varchar,SERVERPROPERTY('MachineName')) as [machine_name]";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_varchar)
				exec (@_sql);

				-- set @_ip
				select @_machine_name = col_varchar from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'machine_name', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [server_name] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and (@output is null or exists (select * from @_tbl_output_columns where column_name = 'server_name'))
		begin
			delete from @_result;
			set @_sql = "select CONVERT(varchar,SERVERPROPERTY('ServerName')) as [server_name]";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_varchar)
				exec (@_sql);

				-- set @_ip
				select @_server_name = col_varchar from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'server_name', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [ip] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and (@output is null or exists (select * from @_tbl_output_columns where column_name = 'ip'))
		begin
			delete from @_result;
			set @_sql = "SELECT	[ip] = CONVERT(varchar,  CONNECTIONPROPERTY('local_net_address') )";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_varchar)
				exec (@_sql);

				-- set @_ip
				select @_ip = col_varchar from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'ip', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [domain] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'domain') )
		begin
			delete from @_result;
			set @_sql = "select default_domain() as [domain];";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_varchar)
				exec (@_sql);

				-- set @_ip
				select @_domain = col_varchar from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'domain', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [host_name] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'host_name') )
		begin
			delete from @_result;
			set @_sql = "select CONVERT(varchar,SERVERPROPERTY('ComputerNamePhysicalNetBIOS')) as [host_name]";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_varchar)
				exec (@_sql);

				-- set @_ip
				select @_host_name = col_varchar from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'host_name', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end

		-- [fqdn] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'fqdn') )
		begin
			delete from @_result;
			set @_sql = "select top 1 fqdn from dbo.server_privileged_info;";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_varchar)
				exec (@_sql);

				-- set @_ip
				select @_fqdn = col_varchar from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'fqdn', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [host_distribution] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'host_distribution') )
		begin
			delete from @_result;
			set @_sql = "select top 1 host_distribution from dbo.server_privileged_info;";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_varchar)
				exec (@_sql);

				-- set @_ip
				select @_host_distribution = col_varchar from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'host_distribution', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [processor_name] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'processor_name') )
		begin
			delete from @_result;
			set @_sql = "select top 1 processor_name from dbo.server_privileged_info;";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_varchar)
				exec (@_sql);

				-- set @_ip
				select @_processor_name = col_varchar from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'processor_name', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [product_version] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'product_version') )
		begin
			delete from @_result;
			set @_sql = "select CONVERT(varchar,SERVERPROPERTY('ProductVersion')) as [product_version]";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_varchar)
				exec (@_sql);

				-- set @_ip
				select @_product_version = col_varchar from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'product_version', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [edition] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'edition') )
		begin
			delete from @_result;
			set @_sql = "select CONVERT(varchar,SERVERPROPERTY('Edition')) as [Edition]";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_varchar)
				exec (@_sql);

				-- set @_ip
				select @_edition = col_varchar from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'edition', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [sqlserver_start_time_utc] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'sqlserver_start_time_utc') )
		begin
			delete from @_result;
			set @_sql = "select [sqlserver_start_time_utc] = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), sqlserver_start_time) from sys.dm_os_sys_info as osi";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_datetime)
				exec (@_sql);

				-- set @_ip
				select @_sqlserver_start_time_utc = col_datetime from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'sqlserver_start_time_utc', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [os_cpu] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'os_cpu') )
		begin
			delete from @_result;
			set @_sql =  "
SET QUOTED_IDENTIFIER ON;
SELECT system_cpu
FROM (
		SELECT	DATEADD (ms, -1 * (ts_now - [timestamp]), GETDATE()) AS event_time
				,DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), DATEADD (ms, -1 * (ts_now - [timestamp]), GETDATE())) AS event_time_utc
				,100-record.value('(Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS system_cpu
				,record.value('(Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS sql_cpu
				,record.value('(Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS idle_system_cpu
				,record.value('(Record/SchedulerMonitorEvent/SystemHealth/UserModeTime)[1]', 'bigint')/10000 AS user_mode_time_ms
				,record.value('(Record/SchedulerMonitorEvent/SystemHealth/KernelModeTime)[1]', 'bigint')/10000 AS kernel_mode_time_ms
				,record.value('(Record/SchedulerMonitorEvent/SystemHealth/PageFaults)[1]', 'bigint')*8.0 AS page_faults_kb
				,record
		FROM (	SELECT	TOP 1 timestamp, CONVERT (xml, record) AS record, cpu_ticks / (cpu_ticks/ms_ticks) as ts_now
				FROM sys.dm_os_ring_buffers orb cross apply sys.dm_os_sys_info osi
				WHERE ring_buffer_type = 'RING_BUFFER_SCHEDULER_MONITOR'
				AND record LIKE '%<SystemHealth>%'
				ORDER BY [timestamp] DESC
		) AS rd
) as t;
"
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_decimal)
				exec (@_sql);

				-- set @_ip
				select @_os_cpu = col_decimal from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'os_cpu', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [sql_cpu] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'sql_cpu') )
		begin
			delete from @_result;
			set @_sql =  "
SET QUOTED_IDENTIFIER ON;
SELECT	sql_cpu
FROM (
		SELECT	DATEADD (ms, -1 * (ts_now - [timestamp]), GETDATE()) AS event_time
				,DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), DATEADD (ms, -1 * (ts_now - [timestamp]), GETDATE())) AS event_time_utc
				,100-record.value('(Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS system_cpu
				,record.value('(Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS sql_cpu
				,record.value('(Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS idle_system_cpu
				,record.value('(Record/SchedulerMonitorEvent/SystemHealth/UserModeTime)[1]', 'bigint')/10000 AS user_mode_time_ms
				,record.value('(Record/SchedulerMonitorEvent/SystemHealth/KernelModeTime)[1]', 'bigint')/10000 AS kernel_mode_time_ms
				,record.value('(Record/SchedulerMonitorEvent/SystemHealth/PageFaults)[1]', 'bigint')*8.0 AS page_faults_kb
				,record
		FROM (	SELECT	TOP 1 timestamp, CONVERT (xml, record) AS record, cpu_ticks / (cpu_ticks/ms_ticks) as ts_now
				FROM sys.dm_os_ring_buffers orb cross apply sys.dm_os_sys_info osi
				WHERE ring_buffer_type = 'RING_BUFFER_SCHEDULER_MONITOR'
				AND record LIKE '%<SystemHealth>%'
				ORDER BY [timestamp] DESC
		) AS rd
) as t;

"
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_decimal)
				exec (@_sql);

				-- set @_ip
				select @_sql_cpu = col_decimal from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'sql_cpu', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [pcnt_kernel_mode] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'pcnt_kernel_mode') )
		begin
			delete from @_result;
			set @_sql =  "
SET QUOTED_IDENTIFIER ON;
SELECT	kernel_mode_time_ms * 100 / (user_mode_time_ms + kernel_mode_time_ms) as [pcnt_kernel_mode]
FROM (
		SELECT	DATEADD (ms, -1 * (ts_now - [timestamp]), GETDATE()) AS event_time
				,DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), DATEADD (ms, -1 * (ts_now - [timestamp]), GETDATE())) AS event_time_utc
				,100-record.value('(Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS system_cpu
				,record.value('(Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS sql_cpu
				,record.value('(Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS idle_system_cpu
				,record.value('(Record/SchedulerMonitorEvent/SystemHealth/UserModeTime)[1]', 'bigint')/10000 AS user_mode_time_ms
				,record.value('(Record/SchedulerMonitorEvent/SystemHealth/KernelModeTime)[1]', 'bigint')/10000 AS kernel_mode_time_ms
				,record.value('(Record/SchedulerMonitorEvent/SystemHealth/PageFaults)[1]', 'bigint')*8.0 AS page_faults_kb
				,record
		FROM (	SELECT	TOP 1 timestamp, CONVERT (xml, record) AS record, cpu_ticks / (cpu_ticks/ms_ticks) as ts_now
				FROM sys.dm_os_ring_buffers orb cross apply sys.dm_os_sys_info osi
				WHERE ring_buffer_type = 'RING_BUFFER_SCHEDULER_MONITOR'
				AND record LIKE '%<SystemHealth>%'
				ORDER BY [timestamp] DESC
		) AS rd
) as t;

"
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_decimal)
				exec (@_sql);

				-- set @_ip
				select @_pcnt_kernel_mode = col_decimal from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'pcnt_kernel_mode', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [page_faults_kb] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'page_faults_kb') )
		begin
			delete from @_result;
			set @_sql =  "
SET QUOTED_IDENTIFIER ON;
SELECT page_faults_kb
FROM (
		SELECT	DATEADD (ms, -1 * (ts_now - [timestamp]), GETDATE()) AS event_time
				,DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), DATEADD (ms, -1 * (ts_now - [timestamp]), GETDATE())) AS event_time_utc
				,100-record.value('(Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS system_cpu
				,record.value('(Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS sql_cpu
				,record.value('(Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS idle_system_cpu
				,record.value('(Record/SchedulerMonitorEvent/SystemHealth/UserModeTime)[1]', 'bigint')/10000 AS user_mode_time_ms
				,record.value('(Record/SchedulerMonitorEvent/SystemHealth/KernelModeTime)[1]', 'bigint')/10000 AS kernel_mode_time_ms
				,record.value('(Record/SchedulerMonitorEvent/SystemHealth/PageFaults)[1]', 'bigint')*8.0 AS page_faults_kb
				,record
		FROM (	SELECT	TOP 1 timestamp, CONVERT (xml, record) AS record, cpu_ticks / (cpu_ticks/ms_ticks) as ts_now
				FROM sys.dm_os_ring_buffers orb cross apply sys.dm_os_sys_info osi
				WHERE ring_buffer_type = 'RING_BUFFER_SCHEDULER_MONITOR'
				AND record LIKE '%<SystemHealth>%'
				ORDER BY [timestamp] DESC
		) AS rd
) as t;

"
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_decimal)
				exec (@_sql);

				-- set @_ip
				select @_page_faults_kb = col_decimal from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'page_faults_kb', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [blocked_counts] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'blocked_counts') )
		begin
			delete from @_result;
			set @_sql =  "
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
select count(*) as blocked_counts --, max(wait_time)/1000 as wait_time_s
from sys.dm_exec_requests r with (nolock) 
where r.blocking_session_id <> 0
and wait_time >= ("+convert(varchar,@blocked_threshold_seconds)+"*1000) -- Over 60 seconds

"
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_int)
				exec (@_sql);

				-- set @_ip
				select @_blocked_counts = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'blocked_counts', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [blocked_duration_max_seconds] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'blocked_duration_max_seconds') )
		begin
			delete from @_result;
			set @_sql =  "
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
declare @_wait_time_s bigint = 0;

select @_wait_time_s = floor(max(wait_time)/1000) --,count(*) as blocked_counts
from sys.dm_exec_requests r with (nolock) 
where r.blocking_session_id <> 0
and wait_time >= ("+convert(varchar,@blocked_threshold_seconds)+"*1000) -- Over 60 seconds

select isnull(@_wait_time_s,0) as [blocked_duration_max_seconds];

"
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_bigint)
				exec (@_sql);

				-- set @_ip
				select @_blocked_duration_max_seconds = col_bigint from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'blocked_duration_max_seconds', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [total_physical_memory_kb] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'total_physical_memory_kb') )
		begin
			delete from @_result;
			set @_sql =  "
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
select	osm.total_physical_memory_kb
		--,osm.available_physical_memory_kb
		--,case when system_high_memory_signal_state = 1 then 'High' else 'Low' end as [Memory State]
		--,opm.physical_memory_in_use_kb
		--,opm.memory_utilization_percentage
from sys.dm_os_sys_memory osm, sys.dm_os_process_memory opm;

"
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_bigint)
				exec (@_sql);

				-- set @_ip
				select @_total_physical_memory_kb = col_bigint from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'total_physical_memory_kb', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [available_physical_memory_kb] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'available_physical_memory_kb') )
		begin
			delete from @_result;
			set @_sql =  "
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
select	--osm.total_physical_memory_kb
		osm.available_physical_memory_kb
		--,case when system_high_memory_signal_state = 1 then 'High' else 'Low' end as [Memory State]
		--,opm.physical_memory_in_use_kb
		--,opm.memory_utilization_percentage
from sys.dm_os_sys_memory osm, sys.dm_os_process_memory opm;

"
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_bigint)
				exec (@_sql);

				-- set @_ip
				select @_available_physical_memory_kb = col_bigint from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'available_physical_memory_kb', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [system_high_memory_signal_state] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'system_high_memory_signal_state') )
		begin
			delete from @_result;
			set @_sql =  "
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
select	--osm.total_physical_memory_kb
		--osm.available_physical_memory_kb
		case when system_high_memory_signal_state = 1 then 'High' else 'Low' end as [Memory State]
		--,opm.physical_memory_in_use_kb
		--,opm.memory_utilization_percentage
from sys.dm_os_sys_memory osm, sys.dm_os_process_memory opm;

"
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_varchar)
				exec (@_sql);

				-- set @_ip
				select @_system_high_memory_signal_state = col_varchar from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'system_high_memory_signal_state', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [physical_memory_in_use_kb] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'physical_memory_in_use_kb') )
		begin
			delete from @_result;
			set @_sql =  "
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
select	--osm.total_physical_memory_kb
		--osm.available_physical_memory_kb
		--,case when system_high_memory_signal_state = 1 then 'High' else 'Low' end as [Memory State]
		opm.physical_memory_in_use_kb
		--,opm.memory_utilization_percentage
from sys.dm_os_sys_memory osm, sys.dm_os_process_memory opm;

"
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_decimal)
				exec (@_sql);

				-- set @_ip
				select @_physical_memory_in_use_kb = col_decimal from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'physical_memory_in_use_kb', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end

		-- [memory_grants_pending] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'memory_grants_pending') )
		begin
			delete from @_result;
			set @_sql =  "
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
declare @object_name varchar(255);
set @object_name = (case when @@SERVICENAME = 'MSSQLSERVER' then 'SQLServer' else 'MSSQL$'+@@SERVICENAME end);

SELECT cntr_value
FROM sys.dm_os_performance_counters WITH (NOLOCK) 
WHERE 1=1
and [object_name] like (@object_name+':Memory Manager%')
AND counter_name = N'Memory Grants Pending';
"
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_int)
				exec (@_sql);

				-- set @_ip
				select @_memory_grants_pending = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'memory_grants_pending', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [connection_count] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'connection_count') )
		begin
			delete from @_result;
			set @_sql =  "
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
select count(*) as counts from sys.dm_exec_connections with (nolock)
"
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_int)
				exec (@_sql);

				-- set @_ip
				select @_connection_count = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'connection_count', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [active_requests_count] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'active_requests_count') )
		begin
			delete from @_result;
			set @_sql =  "
SET NOCOUNT ON;
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
exec usp_active_requests_count;
"
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_int)
				exec (@_sql);

				-- set @_ip
				select @_active_requests_count = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'active_requests_count', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [waits_per_core_per_minute] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'waits_per_core_per_minute') )
		begin
			delete from @_result;
			set @_sql =  "
SET NOCOUNT ON;
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
exec usp_waits_per_core_per_minute;
"
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_decimal)
				exec (@_sql);

				-- set @_ip
				select @_waits_per_core_per_minute = col_decimal from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'waits_per_core_per_minute', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [avg_disk_wait_ms] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'avg_disk_wait_ms') )
		begin
			delete from @_result;
			set @_sql =  "
SET NOCOUNT ON;
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
exec usp_avg_disk_wait_ms;
"
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_decimal)
				exec (@_sql);

				-- set @_avg_disk_wait_ms
				select @_avg_disk_wait_ms = col_decimal from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'avg_disk_wait_ms', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [avg_disk_latency_ms] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'avg_disk_latency_ms') )
		begin
			delete from @_result;
			set @_sql =  "
SET NOCOUNT ON;
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
exec usp_avg_disk_latency_ms;
"
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_int)
				exec (@_sql);

				-- set @_avg_disk_latency_ms
				select @_avg_disk_latency_ms = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'avg_disk_latency_ms', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [os_start_time_utc] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'os_start_time_utc') )
		begin
			delete from @_result;
			set @_sql = "
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
select [os_start_time_utc] = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), dateadd(SECOND,-osi.ms_ticks/1000,GETDATE())) from sys.dm_os_sys_info as osi";
			
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_datetime)
				exec (@_sql);

				-- set @_ip
				select @_os_start_time_utc = col_datetime from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'os_start_time_utc', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [cpu_count] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'cpu_count') )
		begin
			delete from @_result;
			set @_sql = "select osi.cpu_count /* osi.scheduler_count */ from sys.dm_os_sys_info as osi";
			
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_int)
				exec (@_sql);

				-- set @_ip
				select @_cpu_count = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'cpu_count', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [scheduler_count] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'scheduler_count') )
		begin
			delete from @_result;
			set @_sql = "select osi.scheduler_count from sys.dm_os_sys_info as osi";
			
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_int)
				exec (@_sql);

				-- set @_ip
				select @_scheduler_count = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'scheduler_count', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [major_version_number] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'major_version_number') )
		begin
			delete from @_result;
			set @_sql = "
declare @server_major_version_number tinyint;
SET @server_major_version_number = CONVERT(tinyint, SERVERPROPERTY('ProductMajorVersion'))

if @server_major_version_number is null
begin
	;with t_versions as 
	( select CONVERT(varchar,SERVERPROPERTY('ProductVersion')) as ProductVersion
			 ,LEFT(CONVERT(varchar,SERVERPROPERTY('ProductVersion')), CHARINDEX('.',CONVERT(varchar,SERVERPROPERTY('ProductVersion')))-1) AS MajorVersion
	)
	select @server_major_version_number = MajorVersion from t_versions;
end

select	[@server_major_version_number] = @server_major_version_number;			
";
			
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_int)
				exec (@_sql);

				-- set @_ip
				select @_major_version_number = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'major_version_number', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [minor_version_number] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'minor_version_number') )
		begin
			delete from @_result;
			set @_sql = "
declare @server_product_version varchar(20);
declare @server_major_version_number tinyint;
declare @server_minor_version_number smallint;

SET @server_product_version = CONVERT(varchar,SERVERPROPERTY('ProductVersion'));
SET @server_major_version_number = CONVERT(tinyint, SERVERPROPERTY('ProductMajorVersion'));

if @server_major_version_number is null
begin
	;with t_versions as 
	( select CONVERT(varchar,SERVERPROPERTY('ProductVersion')) as ProductVersion
			 ,LEFT(CONVERT(varchar,SERVERPROPERTY('ProductVersion')), CHARINDEX('.',CONVERT(varchar,SERVERPROPERTY('ProductVersion')))-1) AS MajorVersion
	)
	select @server_major_version_number = MajorVersion from t_versions;
end

declare @server_minor_version_number_intermediate varchar(20);
set @server_minor_version_number_intermediate = REPLACE(@server_product_version,CONVERT(varchar,@server_major_version_number)+'.'+CONVERT(varchar, SERVERPROPERTY('ProductMinorVersion'))+'.','');

if(@server_minor_version_number_intermediate is null)
begin
	;with t_versions as
	( select replace(@server_product_version,CONVERT(varchar,@server_major_version_number)+'.','') as VrsnString )
	select @server_minor_version_number_intermediate = REPLACE(@server_product_version,CONVERT(varchar,@server_major_version_number)+'.'+LEFT(VrsnString,CHARINDEX('.',VrsnString)-1)+'.','')
	from t_versions;
end

set @server_minor_version_number = left(@server_minor_version_number_intermediate,charindex('.',@server_minor_version_number_intermediate)-1);

SELECT	[@server_minor_version_number] = @server_minor_version_number
";
			
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_int)
				exec (@_sql);

				-- set @_ip
				select @_minor_version_number = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'minor_version_number', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [max_server_memory_mb] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'max_server_memory_mb') )
		begin
			delete from @_result;
			set @_sql = "
select [max_server_memory_mb] = convert(int, c.value_in_use)
from sys.configurations c
where c.name = 'max server memory (MB)'		
";
			
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_int)
				exec (@_sql);

				-- set @_max_server_memory_mb
				select @_max_server_memory_mb = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'max_server_memory_mb', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [page_life_expectancy] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'page_life_expectancy') )
		begin
			delete from @_result;
			set @_sql = "
declare @object_name varchar(255);
set @object_name = (case when @@SERVICENAME = 'MSSQLSERVER' then 'SQLServer' else 'MSSQL$'+@@SERVICENAME end);

SELECT [page_life_expectancy] = cntr_value 
FROM sys.dm_os_performance_counters WITH (NOLOCK) 
WHERE 1=1
and [object_name] like (@object_name+':Buffer Manager%') 
and counter_name = N'Page life expectancy'
";
			
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_int)
				exec (@_sql);

				-- set @_ip
				select @_page_life_expectancy = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'page_life_expectancy', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [memory_consumers] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'memory_consumers') )
		begin
			delete from @_result;
			set @_sql = "
declare @granted_memory_threshold_mb int = 500;
select [memory_consumers] = count(*)
from sys.dm_exec_requests der
where 1=1
and (der.granted_query_memory*8) > (@granted_memory_threshold_mb*1024) -- convert to kb for comparision
";
			
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_int)
				exec (@_sql);

				-- set @_ip
				select @_memory_consumers = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'memory_consumers', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [target_server_memory_kb] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'target_server_memory_kb') )
		begin
			delete from @_result;
			set @_sql = "
declare @object_name varchar(255);
set @object_name = (case when @@SERVICENAME = 'MSSQLSERVER' then 'SQLServer' else 'MSSQL$'+@@SERVICENAME end);

SELECT [target_server_memory_kb] = cntr_value
FROM sys.dm_os_performance_counters WITH (NOLOCK) 
WHERE 1=1
and [object_name] like (@object_name+':Memory Manager%') 
AND counter_name = N'Target Server Memory (KB)'
";
			
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_int)
				exec (@_sql);

				-- set @_ip
				select @_target_server_memory_kb = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'target_server_memory_kb', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [total_server_memory_kb] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'total_server_memory_kb') )
		begin
			delete from @_result;
			set @_sql = "
declare @object_name varchar(255);
set @object_name = (case when @@SERVICENAME = 'MSSQLSERVER' then 'SQLServer' else 'MSSQL$'+@@SERVICENAME end);

SELECT [total_server_memory_kb] = cntr_value
FROM sys.dm_os_performance_counters WITH (NOLOCK) 
WHERE 1=1
and [object_name] like (@object_name+':Memory Manager%') 
AND counter_name = N'Total Server Memory (KB)'
";
			
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
		
			begin try
				insert @_result (col_int)
				exec (@_sql);

				-- set @_ip
				select @_total_server_memory_kb = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'total_server_memory_kb', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [performance_counters__latency_minutes] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'performance_counters__latency_minutes') )
		begin
			delete from @_result;
			set @_sql = "
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
select [latency_minutes] = coalesce(latency_minutes,dummy_latency_minutes)
from 
(	select top 1 [latency_minutes] = datediff(minute,collection_time_utc,getutcdate()) from dbo.vw_performance_counters
	where 1=1
	and collection_time_utc >= dateadd(minute,-120,getutcdate())
	--and [host_name] = CONVERT(varchar,SERVERPROPERTY('ComputerNamePhysicalNetBIOS')) 
	order by collection_time_utc desc
) od
full outer join (select [dummy_latency_minutes] = 10080) dmy -- 7 days
on 1=1";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';

			begin try
				insert @_result (col_int)
				exec (@_sql);

				select @_performance_counters__latency_minutes = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'performance_counters__latency_minutes', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [xevent_metrics__latency_minutes] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'xevent_metrics__latency_minutes') )
		begin
			delete from @_result;
			set @_sql = "
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
select [latency_minutes] = coalesce(xe.latency_minutes,dmy.dummy_latency_minutes)
from 
(	select top 1 latency_minutes = datediff(minute,xe.event_time,getdate()) from dbo.xevent_metrics xe
	where 1=1
	and xe.event_time >= dateadd(minute,-120,getdate())
	order by xe.event_time desc
) xe
full outer join (select [dummy_latency_minutes] = 10080) dmy 
on 1=1";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';

			begin try
				insert @_result (col_int)
				exec (@_sql);

				-- set @_ip
				select @_xevent_metrics__latency_minutes = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'xevent_metrics__latency_minutes', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [WhoIsActive__latency_minutes] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'WhoIsActive__latency_minutes') )
		begin
			delete from @_result;
			set @_sql = "
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
select [latency_minutes] = coalesce(w.latency_minutes,dmy.dummy_latency_minutes)
from 
(	select top 1 [latency_minutes] = datediff(minute,w.collection_time,getdate()) from dbo.WhoIsActive w
	where 1=1
	and w.collection_time >= dateadd(minute,-60,getdate())
	order by collection_time desc
) w
full outer join (select [dummy_latency_minutes] = 10080) dmy -- 7 days
on 1=1";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';

			begin try
				insert @_result (col_int)
				exec (@_sql);

				select @_WhoIsActive__latency_minutes = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'WhoIsActive__latency_minutes', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [os_task_list__latency_minutes] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'os_task_list__latency_minutes') )
		begin
			delete from @_result;
			set @_sql = "
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
select [latency_minutes] = coalesce(latency_minutes,dummy_latency_minutes)
from 
(	select top 1 [latency_minutes] = datediff(minute,collection_time_utc,getutcdate()) from dbo.vw_os_task_list
	where 1=1
	and collection_time_utc >= dateadd(minute,-120,getutcdate())
	--and [host_name] = CONVERT(varchar,SERVERPROPERTY('ComputerNamePhysicalNetBIOS')) 
	order by collection_time_utc desc
) od
full outer join (select [dummy_latency_minutes] = 10080) dmy -- 7 days
on 1=1";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';

			begin try
				insert @_result (col_int)
				exec (@_sql);

				-- set @_ip
				select @_os_task_list__latency_minutes = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'os_task_list__latency_minutes', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [disk_space__latency_minutes] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'disk_space__latency_minutes') )
		begin
			delete from @_result;
			set @_sql = "
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
select [latency_minutes] = coalesce(latency_minutes,dummy_latency_minutes)
from 
(	select top 1 [latency_minutes] = datediff(minute,collection_time_utc,getutcdate()) from dbo.vw_disk_space
	where 1=1
	and collection_time_utc >= dateadd(minute,-120,getutcdate())
	--and [host_name] = CONVERT(varchar,SERVERPROPERTY('ComputerNamePhysicalNetBIOS')) 
	order by collection_time_utc desc
) od
full outer join (select [dummy_latency_minutes] = 10080) dmy -- 7 days
on 1=1";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';

			begin try
				insert @_result (col_int)
				exec (@_sql);

				select @_disk_space__latency_minutes = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'disk_space__latency_minutes', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end

		-- [file_io_stats__latency_minutes] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'file_io_stats__latency_minutes') )
		begin
			delete from @_result;
			set @_sql = "
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
select [latency_minutes] = coalesce(latency_minutes,dummy_latency_minutes)
from 
(	select top 1 [latency_minutes] = datediff(minute,collection_time_utc,getutcdate()) from dbo.file_io_stats
	where 1=1
	and collection_time_utc >= dateadd(minute,-120,getutcdate())
	order by collection_time_utc desc
) od
full outer join (select [dummy_latency_minutes] = 10080) dmy -- 7 days
on 1=1";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';

			begin try
				insert @_result (col_int)
				exec (@_sql);

				select @_file_io_stats__latency_minutes = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'file_io_stats__latency_minutes', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end

		-- [sql_agent_job_stats__latency_minutes] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'sql_agent_job_stats__latency_minutes') )
		begin
			delete from @_result;
			set @_sql = "
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
select [latency_minutes] = coalesce(latency_minutes,dummy_latency_minutes)
from 
(	select [latency_minutes] = datediff(minute,max(UpdatedDateUTC),getutcdate()) from dbo.sql_agent_job_stats
	where 1=1
) od
full outer join (select [dummy_latency_minutes] = 10080) dmy -- 7 days
on 1=1";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';

			begin try
				insert @_result (col_int)
				exec (@_sql);

				select @_sql_agent_job_stats__latency_minutes = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'sql_agent_job_stats__latency_minutes', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end

		-- [memory_clerks__latency_minutes] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'memory_clerks__latency_minutes') )
		begin
			delete from @_result;
			set @_sql = "
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
select [latency_minutes] = coalesce(latency_minutes,dummy_latency_minutes)
from 
(	select top 1 [latency_minutes] = datediff(minute,collection_time_utc,getutcdate()) from [dbo].[memory_clerks]
	where 1=1
	and collection_time_utc >= dateadd(minute,-120,getutcdate())
	order by collection_time_utc desc
) od
full outer join (select [dummy_latency_minutes] = 10080) dmy -- 7 days
on 1=1";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';

			begin try
				insert @_result (col_int)
				exec (@_sql);

				select @_memory_clerks__latency_minutes = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'memory_clerks__latency_minutes', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end

		-- [wait_stats__latency_minutes] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'wait_stats__latency_minutes') )
		begin
			delete from @_result;
			set @_sql = "
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
select [latency_minutes] = coalesce(latency_minutes,dummy_latency_minutes)
from 
(	select top 1 [latency_minutes] = datediff(minute,collection_time_utc,getutcdate()) from dbo.wait_stats
	where 1=1
	and collection_time_utc >= dateadd(minute,-120,getutcdate())
	order by collection_time_utc desc
) od
full outer join (select [dummy_latency_minutes] = 10080) dmy -- 7 days
on 1=1";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';

			begin try
				insert @_result (col_int)
				exec (@_sql);

				select @_wait_stats__latency_minutes = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'wait_stats__latency_minutes', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [BlitzIndex__latency_days] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'BlitzIndex__latency_days') )
		begin
			delete from @_result;
			set @_sql = "
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
select [latency_days] = coalesce(latency_days,dummy_latency_days)
from 
(	select top 1 [latency_days] = datediff(day,run_datetime,getdate()) from dbo.BlitzIndex
	where 1=1
	and run_datetime >= dateadd(day,-3,getdate())
	order by run_datetime desc
) od
full outer join (select [dummy_latency_days] = 365) dmy 
on 1=1";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';

			begin try
				insert @_result (col_int)
				exec (@_sql);

				select @_BlitzIndex__latency_days = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'BlitzIndex__latency_days', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [BlitzIndex_Mode0__latency_days] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'BlitzIndex_Mode0__latency_days') )
		begin
			delete from @_result;
			set @_sql = "
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
select [latency_days] = coalesce(latency_days,dummy_latency_days)
from 
(	select top 1 [latency_days] = datediff(day,run_datetime,getdate()) from dbo.BlitzIndex_Mode0
	where 1=1
	and run_datetime >= dateadd(day,-15,getdate())
	order by run_datetime desc
) od
full outer join (select [dummy_latency_days] = 365) dmy 
on 1=1";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';

			begin try
				insert @_result (col_int)
				exec (@_sql);

				select @_BlitzIndex_Mode0__latency_days = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'BlitzIndex_Mode0__latency_days', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [BlitzIndex_Mode1__latency_days] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'BlitzIndex_Mode1__latency_days') )
		begin
			delete from @_result;
			set @_sql = "
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
select [latency_days] = coalesce(latency_days,dummy_latency_days)
from 
(	select top 1 [latency_days] = datediff(day,run_datetime,getdate()) from dbo.BlitzIndex_Mode1
	where 1=1
	and run_datetime >= dateadd(day,-15,getdate())
	order by run_datetime desc
) od
full outer join (select [dummy_latency_days] = 365) dmy 
on 1=1";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';

			begin try
				insert @_result (col_int)
				exec (@_sql);

				select @_BlitzIndex_Mode1__latency_days = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'BlitzIndex_Mode1__latency_days', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- [BlitzIndex_Mode4__latency_days] => Create SQL Statement to Execute
		if @_linked_server_failed = 0 and ( @output is null or exists (select * from @_tbl_output_columns where column_name = 'BlitzIndex_Mode4__latency_days') )
		begin
			delete from @_result;
			set @_sql = "
"+(case when @enable_lock_timeout = 1 then '' else '--' end)+"SET LOCK_TIMEOUT 60000;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
select [latency_days] = coalesce(latency_days,dummy_latency_days)
from 
(	select top 1 [latency_days] = datediff(day,run_datetime,getdate()) from dbo.BlitzIndex_Mode4
	where 1=1
	and run_datetime >= dateadd(day,-15,getdate())
	order by run_datetime desc
) od
full outer join (select [dummy_latency_days] = 365) dmy 
on 1=1";
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';

			begin try
				insert @_result (col_int)
				exec (@_sql);

				select @_BlitzIndex_Mode4__latency_days = col_int from @_result;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerInfo', 
						[function_call_arguments] = 'BlitzIndex_Mode4__latency_days', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- Populate all details for single server inside loop
		if @_linked_server_failed = 0
		begin
			insert #server_details 
			(	[srv_name], [at_server_name], [machine_name], [server_name], [ip], [domain], [host_name], [fqdn], [host_distribution], 
				[processor_name], [product_version], [edition], [sqlserver_start_time_utc], [os_cpu], [sql_cpu], 
				[pcnt_kernel_mode], [page_faults_kb], [blocked_counts], [blocked_duration_max_seconds], [total_physical_memory_kb], 
				[available_physical_memory_kb], [system_high_memory_signal_state], [physical_memory_in_use_kb], [memory_grants_pending], 
				[connection_count], [active_requests_count], [waits_per_core_per_minute], [avg_disk_wait_ms], [avg_disk_latency_ms], [os_start_time_utc],
				[cpu_count], [scheduler_count], [major_version_number], [minor_version_number], [max_server_memory_mb], [page_life_expectancy], [memory_consumers], 
				[target_server_memory_kb], [total_server_memory_kb], [performance_counters__latency_minutes],
				[xevent_metrics__latency_minutes], [WhoIsActive__latency_minutes], [os_task_list__latency_minutes], 
				[disk_space__latency_minutes], [file_io_stats__latency_minutes], [sql_agent_job_stats__latency_minutes], 
				[memory_clerks__latency_minutes], [wait_stats__latency_minutes], [BlitzIndex__latency_days],
				[BlitzIndex_Mode0__latency_days], [BlitzIndex_Mode1__latency_days], [BlitzIndex_Mode4__latency_days]
			)
			select	[srv_name] = @_srv_name
					,[@@servername] = @_at_server_name
					,[machine_name] = @_machine_name
					,[server_name] = @_server_name
					,[ip] = @_ip
					,[domain] = @_domain
					,[host_name] = @_host_name
					,[fqdn] = @_fqdn
					,[host_distribution] = @_host_distribution
					,[processor_name] = @_processor_name
					,[product_version] = @_product_version
					,[edition] = @_edition
					,[sqlserver_start_time_utc] = @_sqlserver_start_time_utc
					,[os_cpu] = @_os_cpu
					,[sql_cpu] = @_sql_cpu
					,[pcnt_kernel_mode] = @_pcnt_kernel_mode
					,[page_faults_kb] = @_page_faults_kb
					,[blocked_counts] = @_blocked_counts
					,[blocked_duration_max_seconds] = @_blocked_duration_max_seconds
					,[total_physical_memory_kb] = @_total_physical_memory_kb
					,[available_physical_memory_kb] = @_available_physical_memory_kb
					,[system_high_memory_signal_state] = @_system_high_memory_signal_state
					,[physical_memory_in_use_kb] = @_physical_memory_in_use_kb
					,[memory_grants_pending] = @_memory_grants_pending
					,[connection_count] = @_connection_count
					,[active_requests_count] = @_active_requests_count
					,[waits_per_core_per_minute] = @_waits_per_core_per_minute
					,[avg_disk_wait_ms] = @_avg_disk_wait_ms
					,[avg_disk_latency_ms] = @_avg_disk_latency_ms
					,[os_start_time_utc] = @_os_start_time_utc
					,[cpu_count] = @_cpu_count
					,[scheduler_count] = @_scheduler_count
					,[major_version_number] = @_major_version_number
					,[minor_version_number] = @_minor_version_number
					,[max_server_memory_mb] = @_max_server_memory_mb
					,[page_life_expectancy] = @_page_life_expectancy
					,[memory_consumers] = @_memory_consumers
					,[target_server_memory_kb] = @_target_server_memory_kb
					,[total_server_memory_kb] = @_total_server_memory_kb
					,[performance_counters__latency_minutes] = @_performance_counters__latency_minutes
					,[xevent_metrics__latency_minutes] = @_xevent_metrics__latency_minutes
					,[WhoIsActive__latency_minutes] = @_WhoIsActive__latency_minutes
					,[os_task_list__latency_minutes] = @_os_task_list__latency_minutes
					,[disk_space__latency_minutes] = @_disk_space__latency_minutes
					,[file_io_stats__latency_minutes] = @_file_io_stats__latency_minutes
					,[sql_agent_job_stats__latency_minutes] = @_sql_agent_job_stats__latency_minutes
					,[memory_clerks__latency_minutes] = @_memory_clerks__latency_minutes
					,[wait_stats__latency_minutes] = @_wait_stats__latency_minutes
					,[BlitzIndex__latency_days] = @_BlitzIndex__latency_days
					,[BlitzIndex_Mode0__latency_days] = @_BlitzIndex_Mode0__latency_days
					,[BlitzIndex_Mode1__latency_days] = @_BlitzIndex_Mode1__latency_days
					,[BlitzIndex_Mode4__latency_days] = @_BlitzIndex_Mode4__latency_days
		end

		FETCH NEXT FROM cur_servers INTO @_srv_name;
	END
	
	
	CLOSE cur_servers;  
	DEALLOCATE cur_servers;

	-- Return all server details
	if @result_to_table is null
	begin
		set @_sql = "select "+(case when @output is null then "*" else @output end)+" from #server_details;";
		print "@result_to_table not supplied. So returning resultset."
	end
	else
	begin
		declare @table_name nvarchar(125);
		set @result_to_table = ltrim(rtrim(@result_to_table));

		-- set appropriate table name
		if(left(@result_to_table,1) = '#') -- temp table
			set @table_name = 'tempdb..'+@result_to_table
		else
		begin -- physical table
			if CHARINDEX('.','dbo.xyz') > 0
				set @table_name = @result_to_table;
			else
				set @table_name = 'dbo.'+@result_to_table;
		end

		-- delete table data if not running in parallel sessions
		if object_id(@table_name) is not null and @paginate = 0
		begin
			set @_sql = "delete from "+@table_name;
			exec (@_sql);
		end

		if object_id(@table_name) is not null and @output is null
		begin
			set @_sql = "insert "+@result_to_table+" select * from #server_details;";
			print "@result_to_table '"+@result_to_table+"' exist, but no columns specified."
		end
		else if object_id(@table_name) is not null and @output is not null
		begin
			set @_sql = "insert "+@result_to_table+" ("+@output+") select "+@output+" from #server_details;";
			print "@result_to_table '"+@result_to_table+"' exist, and columns specified."
		end
		else
		begin
			set @_sql = "select "+(case when @output is null then "*" else @output end)+" into "+@result_to_table+" from #server_details;";
			print "@result_to_table '"+@result_to_table+"' does exist, so creating same."
			print @_sql;
		end
	end

	exec (@_sql);

	print 'Transaction Counts => '+convert(varchar,@@trancount);
END
set quoted_identifier on;
GO
