IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
SET ARITHABORT ON;
GO

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_collect_xevent_metrics')
    EXEC ('CREATE PROC dbo.usp_collect_xevent_metrics AS SELECT ''stub version, to be replaced''')
GO

ALTER PROCEDURE dbo.usp_collect_xevent_metrics
AS 
BEGIN
	/*
		Version:		2025-01-31
		Purpose:		Extract Extended Event [xevent_metrics] data from Ring Buffer into [dbo].[vw_xevent_metrics]
		Date:			2025-01-31 - Added support for Azure SQL Managed Instance

		EXEC dbo.usp_collect_xevent_metrics

		Additional Requirements
		1) Default Global Mail Profile
			-> SqlInstance -> Management -> Right click "Database Mail" -> Configure Database Mail -> Select option "Manage profile security" -> Check Public checkbox, and Select "Yes" for Default for profile that should be set a global default
		2) Make sure context database is set to correct dba database
	*/
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET LOCK_TIMEOUT 60000; -- 60 seconds
	
	declare @current_time datetime2 = sysutcdatetime();

	;with t_data_extracted as 
	(
		SELECT  [event_name] = xe.event_data.value('(@name)', 'VARCHAR(50)'),
				[event_time] = DATEADD(mi, DATEDIFF(mi, GETUTCDATE(), GETDATE()), xe.event_data.value('(@timestamp)', 'DATETIME2')),
				[cpu_time] = xe.event_data.value('(data[@name="cpu_time"]/value)[1]', 'BIGINT'),
				[duration_seconds] = (xe.event_data.value('(data[@name="duration"]/value)[1]', 'BIGINT'))/1000000,
				[physical_reads] = xe.event_data.value('(data[@name="physical_reads"]/value)[1]', 'BIGINT'),
				[logical_reads] = xe.event_data.value('(data[@name="logical_reads"]/value)[1]', 'BIGINT'),
				[writes] = xe.event_data.value('(data[@name="writes"]/value)[1]', 'BIGINT'),
				[spills] = xe.event_data.value('(data[@name="spills"]/value)[1]', 'BIGINT'),
				[row_count] = xe.event_data.value('(data[@name="row_count"]/value)[1]', 'BIGINT'),
				[result] = xe.event_data.value('(data[@name="result"]/text)[1]', 'VARCHAR(20)'),
				[username] = xe.event_data.value('(action[@name="username"]/value)[1]', 'NVARCHAR(255)'),
				[sql_text] = xe.event_data.value('(action[@name="sql_text"]/value)[1]', 'NVARCHAR(MAX)'),
				[database_name] = xe.event_data.value('(action[@name="database_name"]/value)[1]', 'NVARCHAR(255)'),
				[client_hostname] = xe.event_data.value('(action[@name="client_hostname"]/value)[1]', 'NVARCHAR(255)'),
				[client_app_name] = xe.event_data.value('(action[@name="client_app_name"]/value)[1]', 'NVARCHAR(255)'),
				[session_resource_pool_id] = xe.event_data.value('(action[@name="session_resource_pool_id"]/value)[1]', 'INT'),
				[session_resource_group_id] = xe.event_data.value('(action[@name="session_resource_group_id"]/value)[1]', 'INT'),
				[session_id] = xe.event_data.value('(action[@name="session_id"]/value)[1]', 'INT'),
				[request_id] = xe.event_data.value('(action[@name="request_id"]/value)[1]', 'INT'),
				[scheduler_id] = xe.event_data.value('(action[@name="scheduler_id"]/value)[1]', 'INT')
		FROM (  
			SELECT CAST(target_data AS XML) AS event_data  
			FROM sys.dm_xe_session_targets AS xt  
			JOIN sys.dm_xe_sessions AS xs  
			ON xs.address = xt.event_session_address  
			WHERE xs.name = 'xevent_metrics'  
			AND xt.target_name = 'ring_buffer'  
		) AS xevent_data
		CROSS APPLY event_data.nodes('/RingBufferTarget/event') AS xe(event_data)
	)
	insert [dbo].[vw_xevent_metrics]
	(	row_id, start_time, event_time, event_name, session_id, request_id, result, database_name, client_app_name, username, cpu_time_ms, duration_seconds, 
		logical_reads, physical_reads, row_count, writes, spills, sql_text, /* query_hash, query_plan_hash, */
		client_hostname, session_resource_pool_id, session_resource_group_id, scheduler_id --, context_info
	)
	select	[row_id] = ROW_NUMBER()over(order by event_time, duration_seconds desc, session_id, request_id),
			start_time = DATEADD(second,-(duration_seconds),event_time), event_time, event_name, 
			session_id, request_id, result, database_name,
			[client_app_name] = CASE	WHEN	[client_app_name] like 'SQLAgent - TSQL JobStep %'
				THEN	(	select	top 1 'SQL Job = '+j.name 
							from msdb.dbo.sysjobs (nolock) as j
							inner join msdb.dbo.sysjobsteps (nolock) AS js on j.job_id=js.job_id
							where right(cast(js.job_id as nvarchar(50)),10) = RIGHT(substring([client_app_name],30,34),10) 
						) + ' ( '+SUBSTRING(LTRIM(RTRIM([client_app_name])), CHARINDEX(': Step ',LTRIM(RTRIM([client_app_name])))+2,LEN(LTRIM(RTRIM([client_app_name])))-CHARINDEX(': Step ',LTRIM(RTRIM([client_app_name])))-2)+' )'
				ELSE	[client_app_name]
				END,
			username, 
			cpu_time_ms = case	when event_name = 'rpc_completed' and convert(int,SERVERPROPERTY('ProductMajorVersion')) >= 11 
								then cpu_time/1000
								when event_name = 'sql_batch_completed' and convert(int,SERVERPROPERTY('ProductMajorVersion')) >= 15
								then cpu_time/1000
								else cpu_time
								end, 
			duration_seconds, logical_reads, physical_reads, row_count, 
			writes, spills, sql_text, /* query_hash, query_plan_hash, */
			client_hostname, session_resource_pool_id, session_resource_group_id, scheduler_id--, context_info
	from t_data_extracted de
	where not exists (select 1 from [dbo].[xevent_metrics] t 
						where t.start_time = DATEADD(second,-(de.duration_seconds),de.event_time)
						and t.event_time = de.event_time
						and t.event_name = de.event_name  COLLATE SQL_Latin1_General_CP1_CI_AS
						and t.session_id = de.session_id
						and t.request_id = de.request_id);
END
GO
