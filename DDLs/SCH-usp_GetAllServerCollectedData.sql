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

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_GetAllServerCollectedData')
    EXEC ('CREATE PROC dbo.usp_GetAllServerCollectedData AS SELECT ''stub version, to be replaced''')
GO

-- DROP PROCEDURE dbo.usp_GetAllServerCollectedData
go

ALTER PROCEDURE dbo.usp_GetAllServerCollectedData
(	@servers varchar(max) = null, /* comma separated list of servers to query */
	@result_to_table nvarchar(125), /* table that need to be populated */
	@verbose tinyint = 0, /* display debugging messages. 0 = No messages. 1 = Only print messages. 2 = Print & Table Results */
	@truncate_table bit = 1, /* when enabled, table would be truncated */
	@has_staging_table bit = 1 /* when enabled, assume there is no staging table */
)
	--WITH EXECUTE AS OWNER --,RECOMPILE
AS
BEGIN

	/*
		Version:		2024-08-20
		Date:			2024-08-20 - #10 Add error log entry
						2024-02-10 - #26 Track Status of SQLAgent Service
						2024-01-08 - Backup History on Dashboard
						2023-10-17 - Add Latency Dashboard for AG
						2023-07-27 - Add truncate table feature
						2023-08-13 - Add dbo.disk_space_all_servers

		exec dbo.usp_GetAllServerCollectedData 
					@servers = 'Workstation,SqlPractice,SqlMonitor', 
					@result_to_table = 'dbo.sql_agent_jobs_all_servers',
					@truncate_table = 1,
					@has_staging_table = 1,
					@verbose = 2;
		https://stackoverflow.com/questions/10191193/how-to-test-linkedservers-connectivity-in-tsql
	*/
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET LOCK_TIMEOUT 60000; -- 60 seconds

	IF @result_to_table NOT IN ('dbo.sql_agent_jobs_all_servers','dbo.disk_space_all_servers','dbo.log_space_consumers_all_servers',
								'dbo.tempdb_space_usage_all_servers','dbo.ag_health_state_all_servers','dbo.backups_all_servers',
								'dbo.services_all_servers')
		THROW 50001, '''result_to_table'' Parameter value is invalid.', 1;	
		
	declare @_start_time datetime2 = sysdatetime();
	declare @_crlf nchar(2) = char(10)+char(13);
	declare @_long_star_line varchar(500) = replicate('*',75);
	declare @_caller_program nvarchar(255);
	DECLARE	@_errorNumber int,
			@_errorSeverity int,
			@_errorState int,
			@_errorLine int,
			@_errorMessage nvarchar(4000);

	set @_caller_program = case when HOST_NAME() like '(dba) Get-AllServerCollectedData%'
								then HOST_NAME()
								else PROGRAM_NAME()
								end;

	DECLARE @_tbl_servers table (srv_name varchar(125));
	DECLARE @_linked_server_failed bit = 0;
	DECLARE @_sql NVARCHAR(max);
	DECLARE @_params NVARCHAR(max);
	DECLARE @_isLocalHost bit = 0;
	DECLARE @_int_variable int = 0;
	DECLARE @_counter int = 0;

	DECLARE @_srv_name	nvarchar (125);
	DECLARE @_at_server_name varchar (125);
	DECLARE @_staging_table nvarchar(125);

	SET @_staging_table = @result_to_table + (case when @has_staging_table = 1 then '__staging' else '' end);

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

	IF @verbose >= 2
	BEGIN
		select distinct [RunningQuery] = 'Cursor-Servers', [srvname] = sql_instance
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
			);
	END

	IF @truncate_table = 1
	BEGIN
		SET @_sql = 'truncate table '+@_staging_table+';';
		IF @verbose >= 1
			PRINT @_sql;
		EXEC (@_sql);
	END

	DECLARE cur_servers CURSOR LOCAL FORWARD_ONLY FOR
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
			);

	OPEN cur_servers;
	FETCH NEXT FROM cur_servers INTO @_srv_name;
	
	--set quoted_identifier off;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		if @verbose >= 1
			print char(10)+'***** Looping through '+quotename(@_srv_name)+' *******';
		set @_linked_server_failed = 0;
		set @_at_server_name = NULL;
		set @_counter += 1

		-- If not local server
		if ( (CONVERT(varchar,SERVERPROPERTY('MachineName')) = @_srv_name) 
			or (CONVERT(varchar,SERVERPROPERTY('ServerName')) = @_srv_name)
			)
			set @_isLocalHost = 1
		else
		begin
			set @_isLocalHost = 0
			begin try
				--set @_sql = "SELECT	@@servername as srv_name;";
				--set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
				exec sys.sp_testlinkedserver @_srv_name;
			end try
			begin catch
				set @_errorMessage = 'Linked Server '+quotename(@_srv_name)+' not connecting.';
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

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerCollectedData', 
						[function_call_arguments] = 'sys.sp_testlinkedserver '+@_srv_name, [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_linked_server_failed = 1;
				--fetch next from cur_servers into @_srv_name;
				--continue;
			end catch;
		end


		-- dbo.sql_agent_jobs_all_servers
		if @_linked_server_failed = 0 and @result_to_table = 'dbo.sql_agent_jobs_all_servers'
		begin
			set @_sql =  "
SET QUOTED_IDENTIFIER ON;
SET LOCK_TIMEOUT 60000; -- 60 seconds
select  [sql_instance] = '"+@_srv_name+"',
		jt.[JobName], jt.[JobCategory], jt.IsDisabled,
        [Last_RunTime] = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), js.[Last_RunTime] ),
		js.[Last_Run_Duration_Seconds],
        js.[Last_Run_Outcome], 
		[Expected_Max_Duration_Minutes] = jt.[Expected-Max-Duration(Min)],
		jt.Successfull_Execution_ClockTime_Threshold_Minutes,
        [Last_Successful_ExecutionTime] = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), js.[Last_Successful_ExecutionTime] ), 
        [Last_Successful_Execution_Hours] = datediff(hour,js.[Last_Successful_ExecutionTime],js.[Last_RunTime]),
        [Running_Since] = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), js.[Running_Since] ) , 
        js.[Running_StepName], js.[Running_Since_Min], js.[Session_Id], js.[Blocking_Session_Id], 
        [Next_RunTime] = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), js.[Next_RunTime] ), 
        js.[Total_Executions], js.[Total_Success_Count], js.[Total_Stopped_Count], js.[Total_Failed_Count], 
        [Success_Pcnt] = case when js.[Total_Executions] = 0 then 100 else (js.[Total_Success_Count]*100)/js.[Total_Executions] end,
        js.[Continous_Failures], js.[<10-Min], js.[10-Min], js.[30-Min], js.[1-Hrs], js.[2-Hrs], js.[3-Hrs], 
        js.[6-Hrs], js.[9-Hrs], js.[12-Hrs], js.[18-Hrs], js.[24-Hrs], js.[36-Hrs], js.[48-Hrs],
        [Is_Running] = case when Running_Since is not null then 1 else 0 end
		,[UpdatedDateUTC] = COALESCE(	MAX(js.UpdatedDateUTC) OVER (),
									MAX(js.CollectionTimeUTC) OVER (),
									MAX(jt.CollectionTimeUTC) OVER ()
								  )
from [dbo].[sql_agent_job_thresholds] jt
left join [dbo].[sql_agent_job_stats] js
	on jt.JobName = js.JobName
where 1=1
"
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
			if @verbose >= 2 or (@verbose >= 1 and @_counter = 1)
				print @_crlf+@_sql+@_crlf;
		
			begin try
				insert into [dbo].[sql_agent_jobs_all_servers__staging]
				(	[sql_instance], [JobName], [JobCategory], [IsDisabled], [Last_RunTime], [Last_Run_Duration_Seconds], [Last_Run_Outcome], 
					[Expected_Max_Duration_Minutes], [Successfull_Execution_ClockTime_Threshold_Minutes],
					[Last_Successful_ExecutionTime], [Last_Successful_Execution_Hours], [Running_Since], 
					[Running_StepName], [Running_Since_Min], [Session_Id], [Blocking_Session_Id], 
					[Next_RunTime], [Total_Executions], [Total_Success_Count], [Total_Stopped_Count], 
					[Total_Failed_Count], [Success_Pcnt], [Continous_Failures], [<10-Min], [10-Min], 
					[30-Min], [1-Hrs], [2-Hrs], [3-Hrs], [6-Hrs], [9-Hrs], [12-Hrs], [18-Hrs], 
					[24-Hrs], [36-Hrs], [48-Hrs], [Is_Running], [UpdatedDateUTC]
				)
				exec (@_sql);
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerCollectedData', 
						[function_call_arguments] = 'dbo.sql_agent_jobs_all_servers', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- dbo.disk_space_all_servers
		if @_linked_server_failed = 0 and @result_to_table = 'dbo.disk_space_all_servers'
		begin
			set @_sql =  "
SET QUOTED_IDENTIFIER ON;
SET LOCK_TIMEOUT 60000; -- 60 seconds
select  [sql_instance] = '"+@_srv_name+"',
		[host_name], [disk_volume], [label], [capacity_mb], [free_mb], [block_size], [filesystem], 
		[updated_date_utc] = [collection_time_utc]
from [dbo].[disk_space] ds
where 1=1
and ds.collection_time_utc = (select top 1 l.collection_time_utc from dbo.disk_space l order by l.collection_time_utc desc);
"
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
			if @verbose >= 2 or (@verbose >= 1 and @_counter = 1)
				print @_crlf+@_sql+@_crlf;
		
			begin try
				insert into [dbo].[disk_space_all_servers__staging]
				(	[sql_instance], [host_name], [disk_volume], [label], [capacity_mb], [free_mb], [block_size], [filesystem], [updated_date_utc] )
				exec (@_sql);
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerCollectedData', 
						[function_call_arguments] = 'dbo.disk_space_all_servers', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end


		-- dbo.log_space_consumers_all_servers
		if @_linked_server_failed = 0 and @result_to_table = 'dbo.log_space_consumers_all_servers'
		begin
			set @_sql =  "
SET QUOTED_IDENTIFIER ON;
SET LOCK_TIMEOUT 60000; -- 60 seconds
select  [sql_instance] = '"+@_srv_name+"',
		[database_name], [recovery_model], [log_reuse_wait_desc], [log_size_mb], [log_used_mb], [exists_valid_autogrowing_file],
		[log_used_pct], [log_used_pct_threshold], [log_used_gb_threshold], [spid], [transaction_start_time], [login_name], 
		[program_name], [host_name], [host_process_id], [command], [additional_info], [action_taken], [sql_text],
		[is_pct_threshold_valid], [is_gb_threshold_valid], [threshold_condition], [thresholds_validated],
		[updated_date_utc] = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), [collection_time])
from [dbo].[log_space_consumers] lsc
where lsc.collection_time = (select top 1 l.collection_time from dbo.log_space_consumers l order by l.collection_time desc);
"
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
			if @verbose >= 2 or (@verbose >= 1 and @_counter = 1)
				print @_crlf+@_sql+@_crlf;
		
			begin try
				insert into [dbo].[log_space_consumers_all_servers__staging]
				(	[sql_instance], [database_name], [recovery_model], [log_reuse_wait_desc], [log_size_mb], [log_used_mb], [exists_valid_autogrowing_file],
					[log_used_pct], [log_used_pct_threshold], [log_used_gb_threshold], [spid], [transaction_start_time], [login_name], [program_name], 
					[host_name], [host_process_id], [command], [additional_info], [action_taken], [sql_text], 
					[is_pct_threshold_valid], [is_gb_threshold_valid], [threshold_condition], [thresholds_validated], [updated_date_utc] 
				)
				exec (@_sql);
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerCollectedData', 
						[function_call_arguments] = 'dbo.log_space_consumers_all_servers', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end

		-- dbo.tempdb_space_usage_all_servers
		if @_linked_server_failed = 0 and @result_to_table = 'dbo.tempdb_space_usage_all_servers'
		begin
			set @_sql =  "
SET QUOTED_IDENTIFIER ON;
SET LOCK_TIMEOUT 60000; -- 60 seconds
select  [sql_instance] = '"+@_srv_name+"',
		[data_size_mb], [data_used_mb], [data_used_pct], [log_size_mb], [log_used_mb], [log_used_pct], [version_store_mb], [version_store_pct],
		[updated_date_utc] = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), [collection_time])
from dbo.tempdb_space_usage tsu
where tsu.collection_time = (select top 1 l.collection_time from dbo.tempdb_space_usage l order by l.collection_time desc);
"
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
			if @verbose >= 2 or (@verbose >= 1 and @_counter = 1)
				print @_crlf+@_sql+@_crlf;
		
			begin try
				insert into [dbo].[tempdb_space_usage_all_servers__staging]
				(	[sql_instance], [data_size_mb], [data_used_mb], [data_used_pct], [log_size_mb], [log_used_mb], 
					[log_used_pct], [version_store_mb], [version_store_pct], [updated_date_utc]
				)
				exec (@_sql);
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerCollectedData', 
						[function_call_arguments] = 'dbo.tempdb_space_usage_all_servers', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end

		-- dbo.ag_health_state_all_servers
		if @_linked_server_failed = 0 and @result_to_table = 'dbo.ag_health_state_all_servers'
		begin
			set @_sql =  "
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
SET LOCK_TIMEOUT 60000; -- 60 seconds
IF OBJECT_ID('dbo.ag_health_state') IS NOT NULL
BEGIN
	select  [sql_instance] = '"+@_srv_name+"',
			[replica_server_name], [is_primary_replica], [database_name], [ag_name], [ag_listener], 
			[is_local], [is_distributed], [synchronization_state_desc], [synchronization_health_desc], 
			[latency_seconds], [redo_queue_size], [log_send_queue_size], [last_redone_time], 
			[log_send_rate], [redo_rate], [estimated_redo_completion_time_min], [last_commit_time], 
			[is_suspended], [suspend_reason_desc],
			[updated_date_utc] = [collection_time_utc]
	from dbo.ag_health_state ahs
	where ahs.collection_time_utc = (select max(i.collection_time_utc) from dbo.ag_health_state i);
END
"
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
			if @verbose >= 2 or (@verbose >= 1 and @_counter = 1)
				print @_crlf+@_sql+@_crlf;
		
			begin try
				insert into [dbo].[ag_health_state_all_servers__staging]
				(	sql_instance, replica_server_name, is_primary_replica, [database_name], ag_name, ag_listener, 
					is_local, is_distributed, synchronization_state_desc, synchronization_health_desc, 
					latency_seconds, redo_queue_size, log_send_queue_size, last_redone_time, log_send_rate, 
					redo_rate, estimated_redo_completion_time_min, last_commit_time, is_suspended, 
					suspend_reason_desc, updated_date_utc
				)
				exec (@_sql);
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerCollectedData', 
						[function_call_arguments] = 'dbo.ag_health_state_all_servers', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end

		-- dbo.backups_all_servers
		if @_linked_server_failed = 0 and @result_to_table = 'dbo.backups_all_servers'
		begin
			set @_sql =  N'
SET NOCOUNT ON; 
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET LOCK_TIMEOUT 60000; -- 60 seconds  
-- https://www.mssqltips.com/sqlservertip/3209/understanding-sql-server-log-sequence-numbers-for-backups/
/*
1) Diff.DatabaseBackupLSN = Full.CheckpointLSN
2) Full.LastLSN <= TLog.FirstLSN
3) Diff.LastLSN <= TLog.FirstLSN
*/

;with t_combined_backups as (
	SELECT top 1 with ties bs.database_name,
			backup_type = CASE	WHEN bs.type = ''D'' AND bs.is_copy_only = 0 THEN ''Full Database Backup''
								WHEN bs.type = ''D'' AND bs.is_copy_only = 1 THEN ''Full Copy-Only Database Backup''
								WHEN bs.type = ''I'' THEN ''Differential database Backup''
								WHEN bs.type = ''L'' THEN ''Transaction Log Backup''
							END,
			backup_start_date_utc = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), bs.backup_start_date),
			backup_finish_date_utc = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), bs.backup_finish_date),
			latest_backup_location = bf.physical_device_name,
			backup_size_mb = CONVERT(decimal(20, 2), bs.backup_size/1024.0/1024.0),
			compressed_backup_size_mb = CONVERT(decimal(20, 2), bs.compressed_backup_size/1024.0/1024.0),
			bs.first_lsn, bs.last_lsn, bs.checkpoint_lsn,
			bs.database_backup_lsn, -- For tlog and differential backups, this is the checkpoint_lsn of the FULL backup it is based on.
			database_creation_date_utc = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), bs.database_creation_date),
			backup_software = bms.software_name, bs.recovery_model, bs.compatibility_level,
			device_type = CASE bf.device_type WHEN 2 THEN ''Disk'' WHEN 5 THEN ''Tape'' WHEN 7 THEN ''Virtual device'' WHEN 9 THEN ''Azure Storage'' WHEN 105 THEN ''A permanent backup device'' ELSE ''Other Device'' END,
			bs.description
	FROM msdb.dbo.backupset bs
	LEFT OUTER JOIN msdb.dbo.backupmediafamily bf ON bs.[media_set_id] = bf.[media_set_id]
	INNER JOIN msdb.dbo.backupmediaset bms ON bs.[media_set_id] = bms.[media_set_id]
	WHERE 1 = 1
	AND bs.is_copy_only = 0
	AND bs.type IN (''D'',''I'')
	AND bs.backup_start_date >= dateadd(month,-3,getdate())
	ORDER BY ROW_NUMBER()OVER(PARTITION BY bs.database_name, bs.type ORDER BY bs.backup_start_date DESC)
)
, t_full_backups as (
	select cb.* from t_combined_backups cb where cb.backup_type = ''Full Database Backup''
)
, t_diff_backups as (
	select cb.* from t_combined_backups cb join t_full_backups fb on fb.database_name = cb.database_name
	where cb.backup_type = ''Differential database Backup''
	and fb.checkpoint_lsn = cb.database_backup_lsn
)
,t_full_diff_backups as (
	select * from t_full_backups fb
	union all
	select * from t_diff_backups db
)
,t_latest_lsn as (
	SELECT fdb.database_name, last_lsn = max(fdb.last_lsn) 
	FROM t_full_diff_backups fdb 
	group by fdb.database_name
)
,t_log_backups as (
	SELECT	bs.database_name,
			backup_type = CASE	WHEN bs.type = ''D''
								AND bs.is_copy_only = 0 THEN ''Full Database Backup''
								WHEN bs.type = ''D''
								AND bs.is_copy_only = 1 THEN ''Full Copy-Only Database Backup''
								WHEN bs.type = ''I'' THEN ''Differential database Backup''
								WHEN bs.type = ''L'' THEN ''Transaction Log Backup''
								WHEN bs.type = ''F'' THEN ''File or filegroup Backup''
								WHEN bs.type = ''G'' THEN ''Differential file Backup''
								WHEN bs.type = ''P'' THEN ''Partial Backup''
								WHEN bs.type = ''Q'' THEN ''Differential partial Backup''
							END,
			backup_start_date_utc = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), bs.backup_start_date),
			backup_finish_date_utc = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), bs.backup_finish_date),
			latest_backup_location = bf.physical_device_name,
			backup_size_mb = CONVERT(decimal(20, 2), bs.backup_size/1024.0/1024.0),
			compressed_backup_size_mb = CONVERT(decimal(20, 2), bs.compressed_backup_size/1024.0/1024.0),
			bs.first_lsn,
			bs.last_lsn,
			bs.checkpoint_lsn,
			bs.database_backup_lsn, -- For tlog and differential backups, this is the checkpoint_lsn of the FULL backup it is based on.
			database_creation_date_utc = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), bs.database_creation_date),
			backup_software = bms.software_name,
			bs.recovery_model,
			bs.compatibility_level,
			device_type = CASE bf.device_type
								WHEN 2 THEN ''Disk''
								WHEN 5 THEN ''Tape''
								WHEN 7 THEN ''Virtual device''
								WHEN 9 THEN ''Azure Storage''
								WHEN 105 THEN ''A permanent backup device''
								ELSE ''Other Device''
						END,
			bs.description
	FROM msdb.dbo.backupset bs
	LEFT OUTER JOIN msdb.dbo.backupmediafamily bf ON bs.[media_set_id] = bf.[media_set_id]
	INNER JOIN msdb.dbo.backupmediaset bms ON bs.[media_set_id] = bms.[media_set_id]
	INNER JOIN t_latest_lsn fdb
		ON fdb.database_name = bs.database_name
		AND bs.first_lsn >= fdb.last_lsn
	WHERE 1 = 1
	AND bs.is_copy_only = 0
	AND bs.type = ''L''
	AND bs.backup_start_date >= dateadd(month,-3,getdate())
)
,t_all_latest_backups as (
	select	lb.database_name, lb.backup_type,
			lb.backup_start_date_utc, lb.backup_finish_date_utc,
			lb.latest_backup_location, lb.backup_size_mb, lb.compressed_backup_size_mb, 
			lb.first_lsn, lb.last_lsn, lb.checkpoint_lsn, lb.database_backup_lsn, 
			lb.database_creation_date_utc, lb.backup_software, lb.recovery_model, lb.compatibility_level,
			lb.device_type, lb.description
	from t_log_backups lb
	union all
	SELECT fdb.database_name, fdb.backup_type,
			fdb.backup_start_date_utc, fdb.backup_finish_date_utc,
			fdb.latest_backup_location, fdb.backup_size_mb, fdb.compressed_backup_size_mb, 
			fdb.first_lsn, fdb.last_lsn, fdb.checkpoint_lsn, fdb.database_backup_lsn, 
			fdb.database_creation_date_utc, fdb.backup_software, fdb.recovery_model, fdb.compatibility_level,
			fdb.device_type, fdb.description
	FROM t_full_diff_backups fdb
)
select	[sql_instance] = '''+@_srv_name+''',
		[database_name] = coalesce(b.database_name,d.name), b.backup_type, 
		[log_backups_count] = count(*) over (partition by b.database_name),
		b.backup_start_date_utc, b.backup_finish_date_utc,
		b.latest_backup_location, b.backup_size_mb, b.compressed_backup_size_mb, 
		b.first_lsn, b.last_lsn, b.checkpoint_lsn, b.database_backup_lsn, 
		b.database_creation_date_utc, b.backup_software, b.recovery_model, b.compatibility_level,
		b.device_type, b.description
from sys.databases d
full outer join
	t_all_latest_backups b
	on d.name = b.database_name
where d.name not in (''tempdb'')
and d.state_desc not in (''OFFLINE'',''RECOVERY_PENDING'', ''SUSPECT'', ''EMERGENCY'', ''RESTORING'')
and d.is_read_only = 0
order by [database_name], [backup_start_date_utc];';

			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
			if @verbose >= 2 or (@verbose >= 1 and @_counter = 1)
				print @_crlf+@_sql+@_crlf;
		
			begin try
				insert into [dbo].[backups_all_servers__staging]
				(	[sql_instance], [database_name], [backup_type], [log_backups_count], [backup_start_date_utc], [backup_finish_date_utc], [latest_backup_location], [backup_size_mb], [compressed_backup_size_mb], [first_lsn], [last_lsn], [checkpoint_lsn], [database_backup_lsn], [database_creation_date_utc], [backup_software], [recovery_model], [compatibility_level], [device_type], [description]
				)
				exec (@_sql);
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerCollectedData', 
						[function_call_arguments] = 'dbo.backups_all_servers', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end

		
		-- dbo.services_all_servers
		if @_linked_server_failed = 0 and @result_to_table = 'dbo.services_all_servers'
		begin
			set @_sql =  "
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON; 
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET LOCK_TIMEOUT 60000; -- 60 seconds  

declare @ports varchar(2000);
select @ports = coalesce(@ports+', '+convert(varchar,p.local_tcp_port),convert(varchar,p.local_tcp_port))
from (
		select distinct local_net_address, local_tcp_port 
		from sys.dm_exec_connections 
		where local_net_address is not null
	) p;

select	[sql_instance] = '"+@_srv_name+"', 
		[at_server_name] = @@servername,
		[service_type] = case when dm.servicename like 'SQL Server (%)' then 'Engine'
								when dm.servicename like 'SQL Server Agent (%)' then 'Agent'
							 else 'Unknown' 
							 end,
		dm.servicename, dm.startup_type_desc, dm.status_desc, dm.process_id, dm.service_account, 
		[sql_ports] = case when dm.servicename like 'SQL Server (%)' then @ports else null end,
		dm.last_startup_time, dm.instant_file_initialization_enabled
		--,[collection_time_utc] = GETUTCDATE()
from sys.dm_server_services dm
where 1=1
and (dm.servicename like 'SQL Server (%)' or dm.servicename like 'SQL Server Agent (%)');
"
			-- Decorate for remote query if LinkedServer
			if @_isLocalHost = 0
				set @_sql = 'select * from openquery(' + QUOTENAME(@_srv_name) + ', "'+ @_sql + '")';
			if @verbose >= 2 or (@verbose >= 1 and @_counter = 1)
				print @_crlf+@_sql+@_crlf;
		
			begin try
				insert into [dbo].[services_all_servers__staging]
				(	[sql_instance], [at_server_name], [service_type], [servicename], [startup_type_desc], [status_desc], [process_id], 
					[service_account], [sql_ports], [last_startup_time_utc], [instant_file_initialization_enabled] 
				)
				exec (@_sql);
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_GetAllServerCollectedData', 
						[function_call_arguments] = 'dbo.services_all_servers', [server] = @_srv_name, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error occurred while executing below query on ['+@_srv_name+'].'+@_crlf+@_errorMessage+@_crlf+'     '+@_sql+@_long_star_line+@_crlf;
			end catch
		end

		-- All the logic should be within the Cursor Loop block
		FETCH NEXT FROM cur_servers INTO @_srv_name;
	END
	
	
	CLOSE cur_servers;  
	DEALLOCATE cur_servers;

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
