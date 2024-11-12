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

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'sp_WhatIsRunning')
    EXEC ('CREATE PROC dbo.sp_WhatIsRunning AS SELECT ''stub version, to be replaced''')
GO

ALTER PROCEDURE dbo.sp_WhatIsRunning
(	@program_name nvarchar(1000) = NULL, 
	@login_name nvarchar(255) = NULL, 
	@database_name varchar(255) = NULL, 
	@session_id int = NULL, 
	@session_host_name nvarchar(255) = NULL, 
	@query_pattern nvarchar(200) = NULL, 
	@get_plans bit = 0
)
WITH RECOMPILE --,EXECUTE AS OWNER 
AS 
BEGIN

	/*
		Version:		1.0.0
		Date:			2022-05-03

		exec sp_WhatIsRunning @query_pattern = 'usp_SomeThingOther'
	*/
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET LOCK_TIMEOUT 60000; -- 60 seconds

	--	Query to find what's is running on server
	;WITH T_Requests AS 
	(
		select  [elapsed_time_s] = datediff(SECOND,COALESCE(r.start_time, s.last_request_start_time),GETDATE())
				,[elapsed_time_ms] = datediff(MILLISECOND,COALESCE(r.start_time, s.last_request_start_time),GETDATE())
				,s.session_id
				,st.text as sql_command
				,r.command as command
				,s.login_name as login_name
				,db_name(COALESCE(r.database_id,s.database_id)) as database_name
				,[program_name] = CASE	WHEN	s.program_name like 'SQLAgent - TSQL JobStep %'
						THEN	(	select	top 1 'SQL Job = '+j.name 
									from msdb.dbo.sysjobs (nolock) as j
									inner join msdb.dbo.sysjobsteps (nolock) AS js on j.job_id=js.job_id
									where right(cast(js.job_id as nvarchar(50)),10) = RIGHT(substring(s.program_name,30,34),10) 
								) + ' ( '+SUBSTRING(LTRIM(RTRIM(s.program_name)), CHARINDEX(': Step ',LTRIM(RTRIM(s.program_name)))+2,LEN(LTRIM(RTRIM(s.program_name)))-CHARINDEX(': Step ',LTRIM(RTRIM(s.program_name)))-2)+' )'  COLLATE SQL_Latin1_General_CP1_CI_AS
						ELSE	s.program_name
						END
				,(case when r.wait_time = 0 then null else r.wait_type end) as wait_type
				,r.wait_time as wait_time
				,(SELECT CASE
						WHEN pageid = 1 OR pageid % 8088 = 0 THEN 'PFS'
						WHEN pageid = 2 OR pageid % 511232 = 0 THEN 'GAM'
						WHEN pageid = 3 OR (pageid - 1) % 511232 = 0 THEN 'SGAM'
						WHEN pageid IS NULL THEN NULL
						ELSE 'Not PFS/GAM/SGAM' END
						FROM (SELECT CASE WHEN r.[wait_type] LIKE 'PAGE%LATCH%' AND r.[wait_resource] LIKE '%:%'
						THEN CAST(RIGHT(r.[wait_resource], LEN(r.[wait_resource]) - CHARINDEX(':', r.[wait_resource], LEN(r.[wait_resource])-CHARINDEX(':', REVERSE(r.[wait_resource])))) AS INT)
						ELSE NULL END AS pageid) AS latch_pageid
				) AS wait_resource_type
				,null as tempdb_allocations
				,null as tempdb_current
				,r.blocking_session_id
				,r.logical_reads as reads
				,r.writes as writes
				,r.cpu_time
				,granted_query_memory = CASE WHEN ((CAST(r.granted_query_memory AS numeric(20,2))*8)/1024/1024) >= 1.0
												THEN CAST(CONVERT(numeric(38,2),(CAST(r.granted_query_memory AS numeric(20,2))*8)/1024/1024) AS VARCHAR(23)) + ' GB'
												WHEN ((CAST(r.granted_query_memory AS numeric(20,2))*8)/1024) >= 1.0
												THEN CAST(CONVERT(numeric(38,2),(CAST(r.granted_query_memory AS numeric(20,2))*8)/1024) AS VARCHAR(23)) + ' MB'
												ELSE CAST((CAST(r.granted_query_memory AS numeric(20,2))*8) AS VARCHAR(23)) + ' KB'
												END
				,COALESCE(r.status, s.status) as status
				,open_transaction_count = s.open_transaction_count
				,s.host_name as host_name
				,COALESCE(r.start_time, s.last_request_start_time) as start_time
				,s.login_time as login_time
				,r.statement_start_offset ,r.statement_end_offset
				,[SqlQueryPlan] = case when @get_plans = 1 then CAST(sqp.query_plan AS xml) else null end
				,GETUTCDATE() as collection_time
				,granted_query_memory as granted_query_memory_raw
				,r.plan_handle ,r.sql_handle
		FROM	sys.dm_exec_sessions AS s
		LEFT JOIN sys.dm_exec_requests AS r ON r.session_id = s.session_id
		OUTER APPLY (select top 1 dec.most_recent_sql_handle as [sql_handle] from sys.dm_exec_connections dec where dec.most_recent_session_id = s.session_id and dec.most_recent_sql_handle is not null) AS dec
		OUTER APPLY sys.dm_exec_sql_text(COALESCE(r.sql_handle,dec.sql_handle)) AS st
		OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) AS bqp
		OUTER APPLY sys.dm_exec_text_query_plan(r.plan_handle,r.statement_start_offset, r.statement_end_offset) as sqp
		WHERE	s.session_id != @@SPID
			AND (	(CASE	WHEN	s.session_id IN (select ri.blocking_session_id from sys.dm_exec_requests as ri)
							--	Get sessions involved in blocking (including system sessions)
							THEN	1
							WHEN	r.blocking_session_id IS NOT NULL AND r.blocking_session_id <> 0
							THEN	1
							ELSE	0
					END) = 1
					OR
					(CASE	WHEN	s.session_id > 50
									AND r.session_id IS NOT NULL -- either some part of session has active request
									--AND ISNULL(open_resultset_count,0) > 0 -- some result is open
									AND s.status <> 'sleeping'
							THEN	1
							ELSE	0
					END) = 1
					OR
					(CASE	WHEN	s.session_id > 50 AND s.open_transaction_count <> 0
							THEN	1
							ELSE	0
					END) = 1
				)		
	)
	SELECT	[collection_time] = getutcdate(),
			[dd hh:mm:ss.mss] = right('   0'+convert(varchar, elapsed_time_s/86400),4)+ ' '+convert(varchar,dateadd(MILLISECOND,elapsed_time_ms,'1900-01-01 00:00:00'),114),
			[session_id], [blocking_session_id], [command], 
			[wait_type], 
			[wait_time] = right('   0'+convert(varchar, [wait_time]/86400000),4)+ ' '+convert(varchar,dateadd(MILLISECOND,[wait_time],'1900-01-01 00:00:00'),114),
			[granted_query_memory], [program_name], [login_name], [database_name], [sql_command], 
			[plan_handle] ,[sql_handle], 
			--[wait_time], 
			[wait_resource_type], [tempdb_allocations], [tempdb_current], 
			[reads], [writes], [cpu_time], [status], [open_transaction_count], [host_name], [start_time], [login_time], 
			[statement_start_offset], [statement_end_offset]
	FROM T_Requests AS r
	WHERE 1 = 1
	AND	(( @query_pattern is null or len(@query_pattern) = 0 )
			or (	r.sql_command like ('%'+@query_pattern+'%')
				 )
		 ) 
	and ( @program_name is null or [program_name] like ('%'+@program_name+'%') COLLATE SQL_Latin1_General_CP1_CI_AS)
	and ( @login_name is null or [login_name] like ('%'+@login_name+'%') COLLATE SQL_Latin1_General_CP1_CI_AS)
	and ( @database_name is null or [database_name] like ('%'+@database_name+'%') COLLATE SQL_Latin1_General_CP1_CI_AS)
	and ( @session_id is null or [session_id] = @session_id )
	and ( @session_host_name is null or [host_name]like ('%'+@session_host_name+'%') COLLATE SQL_Latin1_General_CP1_CI_AS)
	and ( @query_pattern is null or sql_command like ('%'+@query_pattern+'%') COLLATE SQL_Latin1_General_CP1_CI_AS)
	ORDER BY start_time asc, granted_query_memory_raw desc
END
GO