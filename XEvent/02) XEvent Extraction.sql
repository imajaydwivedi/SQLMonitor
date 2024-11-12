use DBA
go

set nocount on;
declare @xe_directory nvarchar(2000);
declare @xe_file nvarchar(255);
declare @context varbinary(2000);
declare @current_time datetime2 = sysutcdatetime();

if OBJECT_ID('tempdb..#xe_files') is not null
	drop table #xe_files;
create table #xe_files (directory nvarchar(2000), subdirectory nvarchar(255), depth tinyint, is_file bit);

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

-- Set context info
EXEC [sys].[sp_set_session_context] @key = 'xe_directory', @value = @xe_directory, @read_only = 0;
EXEC [sys].[sp_set_session_context] @key = 'xe_file_current', @value = @xe_file, @read_only = 0;

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
--declare @xe_directory nvarchar(2000);

SELECT @xe_directory = CONVERT(varchar(2000),SESSION_CONTEXT(N'xe_directory'));
declare cur_files cursor local forward_only for
		select subdirectory
		from #xe_files f
		where f.subdirectory like ('xevent_metrics%')
		order by f.subdirectory asc;

open cur_files;
fetch next from cur_files into @c_file;

--drop table #event_data
--select xf.object_name as event_name, xf.file_name, xf.timestamp_utc, event_data = convert(xml,xf.event_data)
--into #event_data
--from sys.fn_xe_file_target_read_file('/study-zone/mssql/xevents/xevent_metrics_0_132719161685480000.xel',null,null,null) as xf
--where xf.object_name in ('sql_batch_completed','rpc_completed','sql_statement_completed')

while @@FETCH_STATUS = 0
begin
	set @c_file_path = @xe_directory+@c_file;
	print @c_file_path;

	if not exists (select * from dbo.xevent_metrics_Processed_XEL_Files f where f.file_path = @c_file_path and f.is_processed = 1)
	begin
		insert dbo.xevent_metrics_Processed_XEL_Files (file_path,collection_time_utc)
		select @c_file_path as file_path, @current_time as collection_time_utc;

		;with t_event_data as (
			select xf.object_name as event_name, xf.file_name, xf.timestamp_utc, event_data = convert(xml,xf.event_data)
			from sys.fn_xe_file_target_read_file(@c_file_path,null,null,null) as xf
			where xf.object_name in ('sql_batch_completed','rpc_completed','sql_statement_completed')
		)
		,t_data_extracted as (
			select  --event_data,
					[event_name]
					--,[start_time] = dateadd(MICROSECOND, -event_data.value('(/event/data[@name="duration"]/value)[1]','bigint'), event_data.value('(/event/@timestamp)[1]','datetime2'))
					,[event_time] = event_data.value('(/event/@timestamp)[1]','datetime2')
					--,[end_time] = event_data.value('(/event/@timestamp)[1]','datetime2')
					,[cpu_time] = event_data.value('(/event/data[@name="cpu_time"]/value)[1]','bigint')
					,[duration_seconds] = (event_data.value('(/event/data[@name="duration"]/value)[1]','bigint'))/1000000
					--,[page_server_reads] = event_data.value('(/event/data[@name="duration"]/value)[1]','bigint')
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
					--,[line_number] = event_data.value('(/event/data[@name="line_number"]/value)[1]','bigint')
					--,[offset] = event_data.value('(/event/data[@name="offset"]/value)[1]','bigint')
					--,[offset_end] = event_data.value('(/event/data[@name="offset_end"]/value)[1]','bigint')
					,[query_hash] = event_data.value('(/event/action[@name="query_hash"]/value)[1]','varbinary(255)')
					,[query_plan_hash] = event_data.value('(/event/action[@name="query_plan_hash"]/value)[1]','varbinary(255)')
					,[database_name] = event_data.value('(/event/action[@name="database_name"]/value)[1]','varchar(255)')
					--,[object_name] = event_data.value('(/event/data[@name="object_name"]/value)[1]','varchar(255)')
					,[client_hostname] = event_data.value('(/event/action[@name="client_hostname"]/value)[1]','varchar(255)')
					,[client_app_name] = event_data.value('(/event/action[@name="client_app_name"]/value)[1]','varchar(255)')
					,[session_resource_pool_id] = event_data.value('(/event/action[@name="session_resource_pool_id"]/value)[1]','int')
					,[session_resource_group_id] = event_data.value('(/event/action[@name="session_resource_group_id"]/value)[1]','int')
					,[session_id] = event_data.value('(/event/action[@name="session_id"]/value)[1]','int')
					,[request_id] = event_data.value('(/event/action[@name="request_id"]/value)[1]','int')
					,[scheduler_id] = event_data.value('(/event/action[@name="scheduler_id"]/value)[1]','int')
					--,[context_info] = event_data.value('(/event/action[@name="context_info"]/value)[1]','varchar(1000)')
			--from #event_data ed
			from t_event_data ed
		)
		insert [dbo].[xevent_metrics]
		(	start_time, event_time, event_name, session_id, request_id, result, database_name, client_app_name, username, cpu_time, duration_seconds, 
			logical_reads, physical_reads, row_count, writes, spills, sql_text, 
			--line_number, offset, offset_end, 
			query_hash, query_plan_hash, client_hostname, session_resource_pool_id, session_resource_group_id, scheduler_id --, context_info
		)
		select	start_time = DATEADD(second,-(duration_seconds),event_time), event_time, event_name, session_id, request_id, result, 
				database_name, client_app_name, username, cpu_time, duration_seconds, logical_reads, physical_reads, row_count, 
				writes, spills, sql_text, 
				--line_number, offset, offset_end, 
				query_hash, query_plan_hash, 
				client_hostname, session_resource_pool_id, session_resource_group_id, scheduler_id--, context_info
		--into DBA..xevent_metrics
		from t_data_extracted de
		where not exists (select 1 from [dbo].[xevent_metrics] t 
							where t.start_time = DATEADD(second,-(de.duration_seconds),de.event_time)
							and t.event_time = de.event_time
							and t.event_name = de.event_name
							and t.session_id = de.session_id
							and t.request_id = de.request_id)

		update f set is_processed = 1
		from dbo.xevent_metrics_Processed_XEL_Files f
		where f.file_path = @c_file_path and f.is_processed = 0 and f.collection_time_utc = @current_time;
	end

	fetch next from cur_files into @c_file;
end

close cur_files;
deallocate cur_files;
go

/*
select *
from dbo.xevent_metrics_Processed_XEL_Files f
where f.is_removed_from_disk = 0 and is_processed = 1
order by collection_time_utc desc;
*/

-- select * from [dbo].[xevent_metrics]


/*
USE [DBA]
GO

IF OBJECT_ID('[dbo].[xevent_metrics]') IS NOT NULL
	DROP TABLE [dbo].[xevent_metrics]
GO

CREATE TABLE [dbo].[xevent_metrics]
(
	[row_id] [bigint] identity(1,1) NOT NULL,
	[start_time] [datetime2](7) NOT NULL,
	[event_time] [datetime2](7) NOT NULL,
	[event_name] [nvarchar](60) NOT NULL,
	[session_id] [int] NOT NULL,
	[request_id] [int] NOT NULL,
	[result] [varchar](50) NULL,
	[database_name] [varchar](255) NULL,
	[client_app_name] [varchar](255) NULL,
	[username] [varchar](255) NULL,
	[cpu_time] [bigint] NULL,
	[duration_seconds] [bigint] NULL,
	--[page_server_reads] [bigint] NULL,
	[logical_reads] [bigint] NULL,
	[physical_reads] [bigint] NULL,
	[row_count] [bigint] NULL,
	[writes] [bigint] NULL,
	[spills] [bigint] NULL,
	[sql_text] [varchar](max) NULL,
	--[line_number] [bigint] NULL,
	--[offset] [bigint] NULL,
	--[offset_end] [bigint] NULL,
	[query_hash] [varbinary](255) NULL,
	[query_plan_hash] [varbinary](255) NULL,
	--[object_name] [varchar](255) NULL,
	[client_hostname] [varchar](255) NULL,
	[session_resource_pool_id] [int] NULL,
	[session_resource_group_id] [int] NULL,
	[scheduler_id] [int] NULL
	--,[context_info] [varchar](1000) NULL
	--,[event_data] [xml] NULL
	,constraint pk_xevent_metrics primary key clustered (event_time,start_time,[row_id])
) on ps_dba_datetime2_hourly (start_time)
GO

create unique index uq_xevent_metrics on [dbo].[xevent_metrics]  ([start_time], [event_time], [row_id])
GO

--select	[start_time], event_time, event_name, session_id, result, 
--		database_name, client_app_name, username, cpu_time, duration, logical_reads, physical_reads, row_count, 
--		writes, spills, sql_text, line_number, offset, offset_end, query_hash, query_plan_hash, object_name, 
--		client_hostname, session_resource_pool_id, session_resource_group_id, scheduler_id, context_info
--from [dbo].[xevent_metrics] 

-- drop table dbo.xevent_metrics_Processed_XEL_Files
create table dbo.xevent_metrics_Processed_XEL_Files
( file_path varchar(2000) not null, collection_time_utc datetime2 not null default SYSUTCDATETIME(), is_processed bit default 0 not null, is_removed_from_disk bit default 0 not null );
alter table dbo.xevent_metrics_Processed_XEL_Files add constraint pk_xevent_metrics_Processed_XEL_Files primary key clustered (file_path,  collection_time_utc);
GO
--select *
--from dbo.xevent_metrics_Processed_XEL_Files
*/