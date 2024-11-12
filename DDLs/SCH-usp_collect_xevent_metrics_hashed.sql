USE [DBA]
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_collect_xevent_metrics_hashed]
AS 
BEGIN
	/*
		Version:		1.0.1
		Date:			2022-09-12 - Adding code to get QueryHash based TSQLTextNormalizer

		EXEC dbo.usp_collect_xevent_metrics

		Additional Requirements
		1) Default Global Mail Profile
			-> SqlInstance -> Management -> Right click "Database Mail" -> Configure Database Mail -> Select option "Manage profile security" -> Check Public checkbox, and Select "Yes" for Default for profile that should be set a global default
		2) Make sure context database is set to correct dba database
		3) Ensure functions dbo.normalized_sql_text() & dbo.fn_get_hash_for_string() are created.
	*/
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET LOCK_TIMEOUT 60000; -- 60 seconds
	
	declare @xe_directory nvarchar(2000);
	declare @xe_file nvarchar(255);
	declare @context varbinary(2000);
	declare @current_time datetime2 = sysutcdatetime();

	if OBJECT_ID('tempdb..#xe_files') is not null
		drop table #xe_files;
	create table #xe_files (directory nvarchar(2000), subdirectory nvarchar(255), depth tinyint, is_file bit);

	if OBJECT_ID('tempdb..#t_data_extracted') is not null
		drop table #t_data_extracted;
	create table #t_data_extracted
	(
		[start_time] as ( DATEADD(second,-(duration_seconds),event_time) ) persisted,
		[event_name] [nvarchar](60) NOT NULL,
		[event_time] [datetime2](7) NULL,
		[cpu_time] [bigint] NULL,
		[duration_seconds] [bigint] NULL,
		[physical_reads] [bigint] NULL,
		[logical_reads] [bigint] NULL,
		[writes] [bigint] NULL,
		[spills] [bigint] NULL,
		[row_count] [bigint] NULL,
		[result] [varchar](7) NOT NULL,
		[username] [varchar](255) NULL,
		[sql_text] [varchar](max) NULL,
		[query_hash] [varbinary](255) NULL,
		[query_plan_hash] [varbinary](255) NULL,
		[database_name] [varchar](255) NULL,
		[client_hostname] [varchar](255) NULL,
		[client_app_name] [varchar](255) NULL,
		[session_resource_pool_id] [int] NULL,
		[session_resource_group_id] [int] NULL,
		[session_id] [int] NULL,
		[request_id] [int] NULL,
		[scheduler_id] [int] NULL,

		index [ci_#t_data_extracted] clustered (event_time, start_time)
	)

	-- Get XEvent files directory
	;with targets_xml as (
		select	target_data_xml = CONVERT(XML, target_data)
		from sys.dm_xe_sessions xs
		join sys.dm_xe_session_targets xt on xt.event_session_address = xs.address
		where xs.name = 'xevent_metrics'
		and xt.target_name = 'event_file'
	)
	,targets_current as (
		select file_path = t.target_data_xml.value('(/EventFileTarget/File/@name)[1]','varchar(2000)')
		from targets_xml t
	)
	select @xe_directory = (case when CHARINDEX('\',reverse(t.file_path)) <> 0 then SUBSTRING(t.file_path,1,LEN(t.file_path)-CHARINDEX('\',reverse(t.file_path))+1)
							 when CHARINDEX('/',reverse(t.file_path)) <> 0 then SUBSTRING(t.file_path,1,LEN(t.file_path)-CHARINDEX('/',reverse(t.file_path))+1)
							 end)
			,@xe_file = t.file_path
	from targets_current t;

	--select [@xe_directory] = @xe_directory, [@xe_file] = @xe_file;

	-- Fetch files from XEvent directory
	insert #xe_files
	(subdirectory, depth, is_file)
	exec xp_dirtree @xe_directory,1,1;
	update #xe_files set directory = @xe_directory;

	--select * from #xe_files f where f.subdirectory like ('xevent_metrics%') order by f.subdirectory asc;

	-- Stop
	ALTER EVENT SESSION [xevent_metrics] ON SERVER STATE=STOP;
	-- Start
	ALTER EVENT SESSION [xevent_metrics] ON SERVER STATE=START;

	-- Extract XEvent Info from File
	declare @c_file nvarchar(255);
	declare @c_file_path nvarchar(2000);

	declare cur_files cursor local forward_only for
			select subdirectory
			from #xe_files f
			where f.subdirectory like ('xevent_metrics%')
			and not exists (select * from dbo.xevent_metrics_Processed_XEL_Files f where f.file_path = (@xe_directory+subdirectory) and f.is_processed = 1)
			order by f.subdirectory asc;

	open cur_files;
	fetch next from cur_files into @c_file;

	while @@FETCH_STATUS = 0
	begin
		set @c_file_path = @xe_directory+@c_file;
		print @c_file_path;

		if not exists (select * from dbo.xevent_metrics_Processed_XEL_Files f where f.file_path = @c_file_path and f.is_processed = 1)
		begin
			insert dbo.xevent_metrics_Processed_XEL_Files (file_path,collection_time_utc)
			select @c_file_path as file_path, @current_time as collection_time_utc;

			truncate table #t_data_extracted;

			--select [** wip **] = 'Processing file '+@c_file_path;
			print 'Processing file '+@c_file_path;

			;with t_event_data as (
				select xf.object_name as event_name, xf.file_name, event_data = convert(xml,xf.event_data) --,xf.timestamp_utc, 
				from sys.fn_xe_file_target_read_file(@c_file_path,null,null,null) as xf
				where xf.object_name in ('sql_batch_completed','rpc_completed','sql_statement_completed')
			)
			,t_data_extracted as (
				select  [event_name]
						,[event_time] = DATEADD(mi, DATEDIFF(mi, sysutcdatetime(), sysdatetime()), (event_data.value('(/event/@timestamp)[1]','datetime2')))
						--,[event_time] = event_data.value('(/event/@timestamp)[1]','datetime2')
						,[cpu_time] = event_data.value('(/event/data[@name="cpu_time"]/value)[1]','bigint')
						,[duration_seconds] = (event_data.value('(/event/data[@name="duration"]/value)[1]','bigint'))/1000000
						,[physical_reads] = event_data.value('(/event/data[@name="physical_reads"]/value)[1]','bigint')
						,[logical_reads] = event_data.value('(/event/data[@name="logical_reads"]/value)[1]','bigint')
						,[writes] = event_data.value('(/event/data[@name="writes"]/value)[1]','bigint')
						,[spills] = event_data.value('(/event/data[@name="spills"]/value)[1]','bigint')
						,[row_count] = event_data.value('(/event/data[@name="row_count"]/value)[1]','bigint')
						,[result] = case event_data.value('(/event/data[@name="result"]/value)[1]','int')
											when 0 then 'OK'
											when 1 then 'Error'
											when 2 then 'Abort'
											else 'Unknown'
											end
						,[username] = event_data.value('(/event/action[@name="username"]/value)[1]','varchar(255)')
						,[sql_text] = case when event_name = 'rpc_completed' and event_data.value('(/event/action[@name="sql_text"]/value)[1]','varchar(max)') is null
											then ltrim(rtrim(event_data.value('(/event/data[@name="statement"]/value)[1]','varchar(max)')))
											else ltrim(rtrim(event_data.value('(/event/action[@name="sql_text"]/value)[1]','varchar(max)')))
										end
						,[query_hash] = event_data.value('(/event/action[@name="query_hash"]/value)[1]','varbinary(255)')
						,[query_plan_hash] = event_data.value('(/event/action[@name="query_plan_hash"]/value)[1]','varbinary(255)')
						,[database_name] = event_data.value('(/event/action[@name="database_name"]/value)[1]','varchar(255)')
						,[client_hostname] = event_data.value('(/event/action[@name="client_hostname"]/value)[1]','varchar(255)')
						,[client_app_name] = event_data.value('(/event/action[@name="client_app_name"]/value)[1]','varchar(255)')
						,[session_resource_pool_id] = event_data.value('(/event/action[@name="session_resource_pool_id"]/value)[1]','int')
						,[session_resource_group_id] = event_data.value('(/event/action[@name="session_resource_group_id"]/value)[1]','int')
						,[session_id] = event_data.value('(/event/action[@name="session_id"]/value)[1]','int')
						,[request_id] = event_data.value('(/event/action[@name="request_id"]/value)[1]','int')
						,[scheduler_id] = event_data.value('(/event/action[@name="scheduler_id"]/value)[1]','int')
				from t_event_data ed
			)
			insert #t_data_extracted
			(event_name, event_time, cpu_time, duration_seconds, physical_reads, logical_reads, writes, spills, row_count, result, username, sql_text, query_hash, query_plan_hash, database_name, client_hostname, client_app_name, session_resource_pool_id, session_resource_group_id, session_id, request_id, scheduler_id)
			select event_name, event_time, cpu_time, duration_seconds, physical_reads, logical_reads, writes, spills, row_count, result, username, sql_text, query_hash, query_plan_hash, database_name, client_hostname, client_app_name, session_resource_pool_id, session_resource_group_id, session_id, request_id, scheduler_id
			from t_data_extracted de
			where not exists (select 1 from [dbo].[xevent_metrics] t 
								where 1=1
								and t.duration_seconds = de.duration_seconds
								and t.event_time = de.event_time
								and t.event_name = de.event_name
								and t.session_id = de.session_id
								and t.request_id = de.request_id);

			insert [dbo].[xevent_metrics]
			(	start_time, event_time, event_name, session_id, request_id, result, database_name, client_app_name, username, cpu_time, duration_seconds, 
				logical_reads, physical_reads, row_count, writes, spills, sql_text, 
				query_hash, query_plan_hash, client_hostname, session_resource_pool_id, session_resource_group_id, scheduler_id --, context_info
			)
			select	--start_time = DATEADD(second,-(duration_seconds),event_time), 
					start_time, event_time, event_name, session_id, request_id, result, 
					database_name,
					[client_app_name] = CASE	WHEN	[client_app_name] like 'SQLAgent - TSQL JobStep %'
												THEN	(	select	top 1 'SQL Job = '+j.name 
															from msdb.dbo.sysjobs (nolock) as j
															inner join msdb.dbo.sysjobsteps (nolock) AS js on j.job_id=js.job_id
															where right(cast(js.job_id as nvarchar(50)),10) = RIGHT(substring([client_app_name],30,34),10) 
														) + ' ( '+SUBSTRING(LTRIM(RTRIM([client_app_name])), CHARINDEX(': Step ',LTRIM(RTRIM([client_app_name])))+2,LEN(LTRIM(RTRIM([client_app_name])))-CHARINDEX(': Step ',LTRIM(RTRIM([client_app_name])))-2)+' )'
												ELSE	[client_app_name]
												END,
					username, cpu_time, duration_seconds, logical_reads, physical_reads, row_count, 
					writes, spills, sql_text, 
					query_hash = hs.sqlsig, 
					query_plan_hash, 
					client_hostname, session_resource_pool_id, session_resource_group_id, scheduler_id--, context_info
			from #t_data_extracted de
			outer apply (select [sqlsig] = (case when de.result IN ('OK','Abort') then (select sqlsig = hs.varbinary_value
						from dbo.fn_get_hash_for_string(dbo.normalized_sql_text(de.sql_text,150,0)) hs) else null end)
						) hs
			where 1=1
			option (maxrecursion 0);

			update f set is_processed = 1
			from dbo.xevent_metrics_Processed_XEL_Files f
			where f.file_path = @c_file_path and f.is_processed = 0 and f.collection_time_utc = @current_time;
		end

		fetch next from cur_files into @c_file;
	end

	close cur_files;
	deallocate cur_files;
END
GO


