--	https://www.sqlskills.com/blogs/jonathan/identifying-external-memory-pressure-with-dm_os_ring_buffers-and-ring_buffer_resource_monitor/
USE master;

/*	Version:			v0.2
	Update Date:		25-Mar-2022
*/

SET NOCOUNT ON; 
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET LOCK_TIMEOUT 60000; -- 60 seconds  
DECLARE @pool_name sysname --= 'REST';
DECLARE @cpu_trend_minutes INT = 120;
DECLARE @top_x_program_rows SMALLINT = 10;
DECLARE @top_x_query_rows SMALLINT = 10;
DECLARE @long_running_query_threshold_minutes INT = 10;
DECLARE @get_blitz_analysis BIT = 0;
DECLARE @only_X_resultset smallint = -1;
DECLARE @show_plan TINYINT = 0; /* 0 = no plan, 1 = query plan, 2 = batch plan */
DECLARE @all_requests TINYINT = 1;
DECLARE @granted_memory_threshold_mb decimal(20,2) = 500.00;
DECLARE @show_io_latency BIT = 1;
DECLARE @io_snapshot_durations_seconds tinyint = 5;
DECLARE @sort_order_all_sessions varchar(500);
--SET @sort_order_all_sessions = '[elapsed_time_sec], [granted_query_memory_kb] desc';
--SET @sort_order_all_sessions = '[login_name][elapsed_time_sec] desc';
SET @sort_order_all_sessions = '[cpu] desc, [tasks] desc';

DECLARE @current_time_UTC datetime = sysutcdatetime();
-- Capture running sessions for Blocking
IF OBJECT_ID('tempdb..#SysProcesses') IS NOT NULL
	DROP TABLE #SysProcesses;
select  Concat
        (
            RIGHT('00'+CAST(ISNULL((datediff(second,er.start_time,GETDATE()) / 3600 / 24), 0) AS VARCHAR(2)),2)
            ,' '
            ,RIGHT('00'+CAST(ISNULL(datediff(second,er.start_time,GETDATE()) / 3600  % 24, 0) AS VARCHAR(2)),2)
            ,':'
            ,RIGHT('00'+CAST(ISNULL(datediff(second,er.start_time,GETDATE()) / 60 % 60, 0) AS VARCHAR(2)),2)
            ,':'
            ,RIGHT('00'+CAST(ISNULL(datediff(second,er.start_time,GETDATE()) % 3600 % 60, 0) AS VARCHAR(2)),2)
        ) as [dd hh:mm:ss]
		--,datediff(MILLISECOND,er.start_time,GETDATE()) as elapsed_time_ms
		,s.session_id as session_id
		,t.text as sql_command
		,SUBSTRING(t.text, (er.statement_start_offset/2)+1,   
        ((CASE er.statement_end_offset WHEN -1 THEN DATALENGTH(t.text)  
				ELSE er.statement_end_offset END - er.statement_start_offset)/2) + 1) AS sql_text
		--,s.cmd as command
		,er.command as command
		,tsk.tasks
		,s.login_name as login_name
		,db_name(s.database_id) as database_name
		,[program_name] = CASE	WHEN	s.program_name like 'SQLAgent - TSQL JobStep %'
				THEN	(	select	top 1 'SQL Job = '+j.name 
							from msdb.dbo.sysjobs (nolock) as j
							inner join msdb.dbo.sysjobsteps (nolock) AS js on j.job_id=js.job_id
							where right(cast(js.job_id as nvarchar(50)),10) = RIGHT(substring(s.program_name,30,34),10) 
						) + ' ( '+SUBSTRING(LTRIM(RTRIM(s.program_name)), CHARINDEX(': Step ',LTRIM(RTRIM(s.program_name)))+2,LEN(LTRIM(RTRIM(s.program_name)))-CHARINDEX(': Step ',LTRIM(RTRIM(s.program_name)))-2)+' )'
				ELSE	REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE (s.program_name, '0', '#'),'1', '#'),'2', '#'),'3', '#'),'4', '#'),'5', '#'),'6', '#'),'7', '#'),'8', '#'),'9', '#')
				END
		,(case when er.wait_time = 0 then null else er.last_wait_type end) as wait_type
		,er.wait_time as wait_time
		,(SELECT CASE
				WHEN pageid = 1 OR pageid % 8088 = 0 THEN 'PFS'
				WHEN pageid = 2 OR pageid % 511232 = 0 THEN 'GAM'
				WHEN pageid = 3 OR (pageid - 1) % 511232 = 0 THEN 'SGAM'
				WHEN pageid IS NULL THEN NULL
				ELSE 'Not PFS/GAM/SGAM' END
				FROM (SELECT CASE WHEN er.[wait_type] LIKE 'PAGE%LATCH%' AND er.[wait_resource] LIKE '%:%'
				THEN CAST(RIGHT(er.[wait_resource], LEN(er.[wait_resource]) - CHARINDEX(':', er.[wait_resource], LEN(er.[wait_resource])-CHARINDEX(':', REVERSE(er.[wait_resource])))) AS INT)
				ELSE NULL END AS pageid) AS latch_pageid
		) AS wait_resource_type
		,null as tempdb_allocations
		,null as tempdb_current
		,er.blocking_session_id
		,er.logical_reads as reads
		,er.writes as writes
		,s.is_user_process
		,[session_row_count] = s.row_count
		,[request_row_count] = er.row_count
		,physical_io = coalesce(er.reads, s.reads)
		,cpu = coalesce(er.cpu_time, s.cpu_time)
		,memusage = coalesce(er.granted_query_memory, s.memory_usage)
		,s.status 
		,open_tran = s.open_transaction_count
		,[granted_query_memory] = CASE WHEN ((er.granted_query_memory*8.0)/1024/1024) >= 1.0
										THEN CAST(CONVERT(NUMERIC(20,2),(er.granted_query_memory *8.0)/1024/1024) AS VARCHAR(23)) + ' GB'
										WHEN ((er.granted_query_memory *8.0)/1024) >= 1.0
										THEN CAST(CONVERT(NUMERIC(20,2),(er.granted_query_memory *8.0)/1024) AS VARCHAR(23)) + ' MB'
										ELSE CAST(CONVERT(NUMERIC(20,2),er.granted_query_memory *8.0) AS VARCHAR(23)) + ' KB'
										END
		,granted_query_memory_kb = er.granted_query_memory*8.0
		,[host_name] = s.host_name
		,er.start_time as start_time
		,s.login_time as login_time
		,rp.Pool
		,er.sql_handle
		,er.plan_handle
		,[request_cpu_time] = er.cpu_time
		,[request_start_time] = er.start_time
		,er.query_hash
		,er.query_plan_hash
		,[BatchQueryPlan] = case when @show_plan >= 2 then bqp.query_plan else 'set @show_plan = 2 to get plans' end
		,[SqlQueryPlan] = case when @show_plan >= 1 then convert(xml,sqp.query_plan) else 'set @show_plan = 1 to get plans' end
		,er.request_id
		,[elapsed_time_sec] = DATEDIFF(second,start_time,GETDATE())
		,GETDATE() as collection_time
INTO #SysProcesses
FROM	sys.dm_exec_sessions AS s
LEFT JOIN sys.dm_exec_requests AS er ON er.session_id = s.session_id
OUTER APPLY (select top 1 dec.most_recent_sql_handle as [sql_handle] from sys.dm_exec_connections dec where dec.most_recent_session_id = s.session_id and dec.most_recent_sql_handle is not null) AS dec
OUTER APPLY sys.dm_exec_sql_text(COALESCE(er.sql_handle,dec.sql_handle)) AS t
OUTER APPLY sys.dm_exec_query_plan(er.plan_handle) AS bqp
OUTER APPLY sys.dm_exec_text_query_plan(er.plan_handle,er.statement_start_offset, er.statement_end_offset) as sqp
LEFT JOIN (	select t.session_id, count(*) AS tasks from sys.dm_os_tasks t group by t.session_id) tsk on s.session_id = tsk.session_id
OUTER APPLY ( select rgrp.name as [Pool] from sys.resource_governor_workload_groups rgwg 
			join sys.resource_governor_resource_pools rgrp ON rgwg.pool_id = rgrp.pool_id where rgwg.group_id = er.group_id ) rp
WHERE	s.session_id != @@SPID
	AND (	(CASE	WHEN	s.session_id IN (select ri.blocking_session_id from sys.dm_exec_requests as ri)
					--	Get sessions involved in blocking (including system sessions)
					THEN	1
					WHEN	er.blocking_session_id IS NOT NULL AND er.blocking_session_id <> 0
					THEN	1
					ELSE	0
			END) = 1
			OR
			(CASE	WHEN	s.session_id > 50
							AND er.session_id IS NOT NULL -- either some part of session has active request
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
		);


/* Get Metrics related to Memory/Blockings */
declare @object_name varchar(255);
set @object_name = (case when @@SERVICENAME = 'MSSQLSERVER' then 'SQLServer' else 'MSSQL$'+@@SERVICENAME end);

;with t_PerfMon as
(
	--Total amount of RAM consumed by database data (Buffer Pool). This should be the highest usage of Memory on the server.
	Select SQLBufferPoolUsedMemoryMB = (Select SUM(pages_kb)/1024 AS [SPA Mem, Mb] FROM sys.dm_os_memory_clerks WITH (NOLOCK) Where type = 'MEMORYCLERK_SQLBUFFERPOOL')
		   --Total amount of RAM used by SQL Server memory clerks (includes Buffer Pool)
		   , SQLAllMemoryClerksUsedMemoryMB = (Select SUM(pages_kb)/1024 AS [SPA Mem, Mb] FROM sys.dm_os_memory_clerks WITH (NOLOCK))
		   --How long in seconds since data was removed from the Buffer Pool, to be replaced with data from disk. (Key indicator of memory pressure when below 300 consistently)
		   ,[PageLifeExpectancy] = (SELECT cntr_value FROM sys.dm_os_performance_counters WITH (NOLOCK) WHERE [object_name] like (@object_name+':Buffer Manager%') AND counter_name = N'Page life expectancy' )
		   --How many memory operations are Pending (should always be 0, anything above 0 for extended periods of time is a very high sign of memory pressure)
		   ,[MemoryGrantsPending] = (SELECT cntr_value FROM sys.dm_os_performance_counters WITH (NOLOCK) WHERE [object_name] LIKE (@object_name+':%Memory Manager%') AND counter_name = N'Memory Grants Pending' )
		   --How many memory operations are Outstanding (should always be 0, anything above 0 for extended periods of time is a very high sign of memory pressure)
		   ,[MemoryGrantsOutstanding] = (SELECT cntr_value FROM sys.dm_os_performance_counters WITH (NOLOCK) WHERE [object_name] LIKE (@object_name+':Memory Manager%') AND counter_name = N'Memory Grants Outstanding' )
)
select  'Memory-Status' as RunningQuery, [Domain] = DEFAULT_DOMAIN(), [ServerName] = @@servername, [IP] = CONNECTIONPROPERTY('local_net_address'),
--		[IsClustered/IsHadrEnabled] = (select CONVERT(varchar,SERVERPROPERTY('IsClustered'))+' / '+CONVERT(varchar,SERVERPROPERTY('IsHadrEnabled'))
--from sys.dm_os_host_info),
		@current_time_UTC as [Current-Time-UTC], [MemoryGrantsPending] as [**M/r-Grants-Pending**],
		[M/r-Consumers] = convert(varchar,(select count(*) from #SysProcesses sp where (sp.granted_query_memory_kb/1024.0) >= @granted_memory_threshold_mb))+' Sessions (>='+convert(varchar,@granted_memory_threshold_mb)+'MB)',
		[**Blocking-Count**] = (select count(*) from sys.dm_exec_requests r where r.blocking_session_id > 0),
		[PageLifeExpectancy],
		[CPU Count] = (select count(*) from sys.dm_os_schedulers as dos where dos.status IN ('VISIBLE ONLINE')),
		cast(sm.total_physical_memory_kb * 1.0 / 1024 / 1024 as numeric(20,0)) as total_box_memory_gb, 
		cast(sm.available_physical_memory_kb * 1.0 / 1024 / 1024 as numeric(20,2)) as available_physical_memory_gb, 
		convert(numeric(20,2),(sm.total_physical_memory_kb-sm.available_physical_memory_kb)*100/sm.total_physical_memory_kb) as [% Memory Used],
		cast((sm.total_page_file_kb - sm.available_page_file_kb) * 1.0 / 1024 / 1024 as numeric(20,0)) as used_page_file_gb,
		cast(sm.system_cache_kb * 1.0 / 1024 /1024 as numeric(20,2)) as system_cache_gb, 
		cast((sm.available_physical_memory_kb - sm.system_cache_kb) * 1.0 / 1024 as numeric(20,2)) as free_memory_mb,
		cast(page_fault_count*8.0/1024/1024 as decimal(20,2)) as page_fault_gb,
		[MemoryGrantsOutstanding], SQLBufferPoolUsedMemoryMB, SQLAllMemoryClerksUsedMemoryMB
from sys.dm_os_sys_memory as sm
full outer join sys.dm_os_process_memory as pm on 1 = 1
full outer join t_PerfMon as pfm on 1 = 1;

/* Get CPU Usage Trend at OS & SQL Server Level */
DECLARE @system_cpu_utilization VARCHAR(2000);
DECLARE @sql_cpu_utilization VARCHAR(2000);
;WITH T_Cpu_Ring_Buffer AS
(
	SELECT	EventTime,
			CASE WHEN system_cpu_utilization_post_sp2 IS NOT NULL THEN system_cpu_utilization_post_sp2 ELSE system_cpu_utilization_pre_sp2 END AS system_cpu_utilization,  
			CASE WHEN sql_cpu_utilization_post_sp2 IS NOT NULL THEN sql_cpu_utilization_post_sp2 ELSE sql_cpu_utilization_pre_sp2 END AS sql_cpu_utilization 
			,ROW_NUMBER()OVER(PARTITION BY CAST(EventTime as smalldatetime) ORDER BY EventTime ASC) as cpu_minute_id
	FROM  (	SELECT	record.value('(Record/@id)[1]', 'int') AS record_id,
					DATEADD (ms, -1 * (ts_now - [timestamp]), GETDATE()) AS EventTime,
					100-record.value('(Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS system_cpu_utilization_post_sp2, 
					record.value('(Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS sql_cpu_utilization_post_sp2,
					100-record.value('(Record/SchedluerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS system_cpu_utilization_pre_sp2,
					record.value('(Record/SchedluerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS sql_cpu_utilization_pre_sp2
			FROM (	SELECT	timestamp, CONVERT (xml, record) AS record, cpu_ticks / (cpu_ticks/ms_ticks) as ts_now
					FROM sys.dm_os_ring_buffers cross apply sys.dm_os_sys_info
					WHERE ring_buffer_type = 'RING_BUFFER_SCHEDULER_MONITOR'
					AND record LIKE '%<SystemHealth>%'
				 ) AS t 
		  ) AS t
	WHERE EventTime >= DATEADD(minute,-@cpu_trend_minutes,getdate())
)
SELECT @system_cpu_utilization = COALESCE(@system_cpu_utilization+' <- '+STR(system_cpu_utilization,3,0), STR(system_cpu_utilization,3,0)),
		@sql_cpu_utilization = COALESCE(@sql_cpu_utilization+' <- '+STR(sql_cpu_utilization,3,0), STR(sql_cpu_utilization,3,0))
FROM T_Cpu_Ring_Buffer
WHERE cpu_minute_id = 1
ORDER BY EventTime desc;

SELECT [*********************************************** Ring Buffer CPU Utilization Trend **********************************************] = 'Local Time -> ' + CONVERT(varchar, getdate(), 21) + '                      ' + 'UTC Time -> ' + CONVERT(varchar, cast(SYSUTCDATETIME() as datetime), 21) + '                      Allocated Schedulers -> ' + (select cast(count(IIF(dos.status = 'VISIBLE ONLINE','sql',NULL)) as varchar)+' / '+cast(count(IIF(dos.status IN ('VISIBLE ONLINE','VISIBLE OFFLINE'),'all',NULL)) as varchar) from sys.dm_os_schedulers dos)
UNION ALL
SELECT [Info] = LEFT('OS CPU'+REPLICATE('_',20),10 ) + ' = ' + @system_cpu_utilization
UNION ALL
SELECT [Info] = LEFT('SQL CPU'+REPLICATE('_',20),10 ) + ' = ' + @sql_cpu_utilization;

if (convert(int,left(@system_cpu_utilization, charindex('<',@system_cpu_utilization)-2)) > 50)
begin
	select [RunningQuery] = 'Schedulers', parent_node_id, count(*) as scheduler_count, sum(convert(int,is_idle)) as idle_scheduler_count, sum(current_tasks_count) as current_tasks_count,
			sum(runnable_tasks_count) as runnable_tasks_count, sum(current_workers_count) as workers_count, sum(active_workers_count) as active_workers_count, 
			sum(pending_disk_io_count) as pending_disk_io_count		
	from sys.dm_os_schedulers
	where status = 'VISIBLE ONLINE' and is_online = 1
	group by parent_node_id
end

/* Begin Code to find Resource Pool Scheduler Affinity */
set nocount on;
if OBJECT_ID('tempdb..#resource_pool') is not null	drop table #resource_pool;
if OBJECT_ID('tempdb..#temp') is not null	drop table #temp;

create table #resource_pool (rpoolname sysname, scheduler_id int, cpu_id int);
create table #temp (name sysname, pool_id int, scheduler_mask bigint);

insert into #temp
select rp.name,rp.pool_id,pa.scheduler_mask 
from sys.dm_resource_governor_resource_pools rp 
left join sys.resource_governor_resource_pool_affinity pa on rp.pool_id=pa.pool_id
where rp.pool_id>2;

if not exists (select * from #temp where scheduler_mask is not null)
	print 'WARNING: No Scheduler Affinity Defined';
else
begin
	while((select count(1) from #temp) > 0)
	Begin
	declare @intvalue numeric,@rpoolname sysname
	declare @vsresult varchar(64)
	declare @inti numeric
	DECLARE @counter int=0
	select @inti = 64, @vsresult = ''
	select top 1 @intvalue = scheduler_mask,@rpoolname = name from #temp
	while @inti>0
	  begin
	  if(@intvalue %2 =1)
	  BEGIN
		insert into #resource_pool(rpoolname,scheduler_id) values(@rpoolname,@counter)
	  END
		select @intvalue = convert(bigint, (@intvalue / 2)), @inti=@inti-1
		set @counter = @counter+1
	  end
	  delete from #temp where name= @rpoolname
	End

	update rpl
	set rpl.cpu_id = dos.cpu_id
	from sys.dm_os_schedulers dos inner join #resource_pool rpl
	on dos.scheduler_id=rpl.scheduler_id
end

-- Insert schedulers NOT assigned to Any Pool, and still utilized by SQL Server
insert into #resource_pool
select 'REST' as rpoolname, dos.scheduler_id,dos.cpu_id 
from sys.dm_os_schedulers dos
left join #resource_pool rpl on dos.scheduler_id = rpl.scheduler_id 
where rpl.scheduler_id is NULL and dos.status = 'VISIBLE ONLINE';
--select * from #resource_pool

/* End Code to find Resource Pool Scheduler Affinity */


IF EXISTS (select * from sys.resource_governor_configuration where is_enabled = 1)
BEGIN
	;WITH T_Pools AS (
		SELECT /* counter that require Fraction & Base */
				'Resource Pool CPU %' as RunningQuery,
				rtrim(fr.instance_name) as [Pool], 
				[% CPU @Server-Level] = case when bs.cntr_value <> 0 then (100.0*((fr.cntr_value*1.0)/(bs.cntr_value*1.0))) else fr.cntr_value*1.0 end,
				[% CPU @SqlInstance-Level] = case when bs.cntr_value <> 0 then (100.0*((fr.cntr_value*1.0)/(bs.cntr_value*1.0*((1.0*dos.cpu_sql_counts)/(dos.cpu_total_counts*1.0))))) else fr.cntr_value*1.0 end,
				[% Schedulers@Total] = case when rp.Scheduler_Count <> 0 then (((rp.Scheduler_Count*1.0)/dos.cpu_total_counts)*100.0) else NULL end,	
				[% Schedulers@Sql] = case when rp.Scheduler_Count <> 0 then (((rp.Scheduler_Count*1.0)/dos.cpu_sql_counts)*100.0) else NULL end,	
				[Assigned Schedulers] = case when rp.Scheduler_Count <> 0 then rp.Scheduler_Count else null end
				,dos.cpu_sql_counts ,dos.cpu_total_counts
		FROM sys.dm_os_performance_counters as fr
		JOIN (select count(1) as cpu_total_counts, sum(case when dos.status = 'VISIBLE ONLINE' then 1 else 0 end) as cpu_sql_counts
				from sys.dm_os_schedulers as dos where dos.status IN ('VISIBLE ONLINE','VISIBLE OFFLINE')
			) AS dos ON 1 = 1
		OUTER APPLY
			(	SELECT * FROM sys.dm_os_performance_counters as bs 
				WHERE bs.cntr_type = 1073939712 /* PERF_LARGE_RAW_BASE  */ 
				AND bs.[object_name] = fr.[object_name] 
				AND (	REPLACE(LOWER(RTRIM(bs.counter_name)),' base','') = REPLACE(LOWER(RTRIM(fr.counter_name)),' ratio','')
					OR
					REPLACE(LOWER(RTRIM(bs.counter_name)),' base','') = LOWER(RTRIM(fr.counter_name))
					)
				AND bs.instance_name = fr.instance_name
			) as bs
		OUTER APPLY (	SELECT COUNT(*) as Scheduler_Count FROM #resource_pool AS rp WHERE rp.rpoolname = rtrim(fr.instance_name)	) as rp
		WHERE fr.cntr_type = 537003264 /* PERF_LARGE_RAW_FRACTION */
			--and fr.cntr_value > 0.0
			and
			(
				( fr.[object_name] like (@object_name+':Resource Pool Stats%') and fr.counter_name like 'CPU usage %' )
			)
	)
	SELECT TOP 7 RunningQuery, @current_time_UTC as [Current-Time-UTC], [Pool], 
			[% CPU @Pool-Level] = CONVERT(NUMERIC(20,2),
								CASE	WHEN [Assigned Schedulers] IS NULL THEN NULL 
										WHEN [% Schedulers@Sql] <> 0 THEN (([% CPU @SqlInstance-Level]*100.0)/([% Schedulers@Sql]*1.0)) 
										ELSE [% CPU @SqlInstance-Level] END
								),
			[% CPU @SqlInstance-Level] = CONVERT(numeric(20,2),[% CPU @SqlInstance-Level]),
			CONVERT(NUMERIC(20,2),[% CPU @Server-Level]) AS [% CPU @Server-Level],
			[Assigned Schedulers], p.cpu_sql_counts as [Sql Schedulers], p.cpu_total_counts as [Total Schedulers]
			,(
					SELECT STUFF((SELECT ', ' + CAST(rp.scheduler_id as VARCHAR(3)) [text()]
					FROM #resource_pool as rp
					WHERE rp.rpoolname = [Pool]
					FOR XML PATH(''), TYPE)
					.value('.','NVARCHAR(MAX)'),1,2,' '
				)) as [Schedulers]
	FROM T_Pools as p
				--,STUFF((SELECT ', ' + CAST(Value AS VARCHAR(10)) [text()]
    --     FROM @Table1 
    --     WHERE ID = t.ID
    --     FOR XML PATH(''), TYPE)
    --    .value('.','NVARCHAR(MAX)'),1,2,' ') List_Output
	WHERE NOT ([Assigned Schedulers] IS NULL AND [% CPU @Server-Level] = 0)
	ORDER BY [% CPU @SqlInstance-Level] desc, [% CPU @Server-Level] desc;
END

--SELECT scheduler_id,count(*) FROM #resource_pool AS rp group by scheduler_id

IF (SELECT count(distinct rpoolname) FROM #resource_pool) < 2
	SET @pool_name = NULL;
;WITH T_Requests AS 
(
	SELECT [Pool], s.login_name, [program_name] = ltrim(rtrim(s.program_name)),
				--REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE (ltrim(rtrim(s.program_name)), '0', '#'),'1', '#'),'2', '#'),'3', '#'),'4', '#'),'5', '#'),'6', '#'),'7', '#'),'8', '#'),'9', '#') as program_name, 
				r.session_id, r.request_id
	FROM  sys.dm_exec_requests r
	JOIN	sys.dm_exec_sessions s ON s.session_id = r.session_id
	OUTER APPLY
		(	select rgrp.name as [Pool]
			from sys.resource_governor_workload_groups rgwg 
			join sys.resource_governor_resource_pools rgrp ON rgwg.pool_id = rgrp.pool_id
			where rgwg.group_id = s.group_id
		) rp
	WHERE s.is_user_process = 1	
		--AND login_name NOT LIKE '%sqlservices%'
		AND (@pool_name is null or [Pool] = @pool_name )
)
,T_Programs_Tasks_Total AS
(
	SELECT	[Pool], login_name, [program_name] = ltrim(rtrim(r.program_name)),
			[active_request_counts] = COUNT(*),
			[num_tasks] = SUM(t.tasks)
	FROM  T_Requests as r
	OUTER APPLY (	select count(*) AS tasks, count(distinct t.scheduler_id) as schedulers 
								from sys.dm_os_tasks t where r.session_id = t.session_id --and r.request_id = t.request_id
							) t
	GROUP  BY [Pool], login_name, ltrim(rtrim(r.program_name))
)
,T_Programs_Schedulers AS
(
	SELECT [Pool], login_name, [program_name] = ltrim(rtrim(r.program_name)), [num_schedulers] = COUNT(distinct t.scheduler_id)
	FROM T_Requests as r
	JOIN sys.dm_os_tasks t
		ON t.session_id = r.session_id AND t.request_id = r.request_id
	GROUP BY [Pool], login_name, ltrim(rtrim(r.program_name))
)
SELECT RunningQuery = (COALESCE(@pool_name,'ALL')+'-POOL/')+'Requests',
		@current_time_UTC as [Current-Time-UTC],
		ptt.[Pool], ptt.login_name, ptt.program_name, ptt.active_request_counts, ptt.num_tasks, ps.num_schedulers, 
		[scheduler_percent] = case when @pool_name is not null then Floor(ps.num_schedulers * 100.0 / rp.Scheduler_Count)
									else Floor(ps.num_schedulers * 100.0 / (select count(*) from sys.dm_os_schedulers as os where os.status = 'VISIBLE ONLINE'))
									end
FROM	T_Programs_Tasks_Total as ptt
JOIN	T_Programs_Schedulers as ps
	ON ps.Pool = ptt.Pool AND ps.program_name = ptt.program_name and ps.login_name = ptt.login_name
OUTER APPLY (	SELECT COUNT(*) as Scheduler_Count FROM #resource_pool AS rp WHERE rp.rpoolname = ptt.[Pool]	) as rp
ORDER  BY [Pool], [num_tasks] desc, active_request_counts desc, [scheduler_percent] desc
OFFSET 0 ROWS FETCH NEXT @top_x_program_rows ROWS ONLY; 


--	Query to find what's running on server (Similar to sp_WhoIsActive)
SELECT RunningQuery = 'Concurrent-Session-Queries',
		[Pool], [dd hh:mm:ss], [program_name], [login_name], [database_name], [command], [host_name], 
		[query_count] = COUNT(*) OVER(PARTITION BY LEFT([sql_text],100)), 
		[tasks_count] = SUM(tasks) OVER(PARTITION BY LEFT([sql_text],100)), 
		--[tasks_count] = SUM(tasks) OVER(PARTITION BY Pool, LEFT(program_name,15), [DBName], LEFT(statement_text,100)), 
		[session_id], request_id, [tasks], [status], [wait_type], [blocked by] = blocking_session_id, [open_tran], [granted_query_memory], 
		[sql_text], [sql_command], [wait_time], [elapsed_time(S)] = DATEDIFF(SECOND,start_time,collection_time), [login_time], 
		granted_query_memory, granted_query_memory_kb, [memusage], 
		[writes], [reads], [is_user_process], [session_row_count], [request_row_count], 
		[sql_handle], [plan_handle], [request_cpu_time], [request_start_time], [query_hash], [query_plan_hash]
		,[BatchQueryPlan] = CASE WHEN @show_plan = 2 THEN [BatchQueryPlan] ELSE NULL END
		,[SqlQueryPlan] = CASE WHEN @show_plan >= 1 THEN [SqlQueryPlan] ELSE NULL END
		,collection_time_utc = @current_time_UTC
FROM #SysProcesses ar
WHERE @pool_name IS NULL -- No pool filter applied
	-- All sessions of Pool, or blockers of Pool session
	OR (ar.Pool = @pool_name OR ar.session_id IN (SELECT bl.[blocking_session_id] FROM #SysProcesses bl WHERE bl.Pool = @pool_name and ISNULL(bl.[blocking_session_id],0) <> 0)
			)
ORDER BY [tasks_count] desc, query_count desc, LEFT([sql_text],100), [request_start_time]
OFFSET 0 ROWS FETCH NEXT @top_x_query_rows ROWS ONLY;


IF (	(	(SELECT cntr_value FROM sys.dm_os_performance_counters WITH (NOLOCK) 
			WHERE [object_name] LIKE (@object_name+':%Memory Manager%') AND counter_name = N'Memory Grants Pending' ) > 0
		)
		OR
		(EXISTS (select count(*) from #SysProcesses sp where (sp.granted_query_memory_kb/1024.0) >= @granted_memory_threshold_mb))
	)
BEGIN
	--	Query to find what's running on server (Similar to sp_WhoIsActive)
	SELECT RunningQuery = 'Memory-Consumers (>='+convert(varchar,@granted_memory_threshold_mb)+'MB)',
			[Pool], [dd hh:mm:ss], [session_id], request_id, [command], granted_query_memory, 
			[program_name], [login_name], [database_name], [host_name], 
			[query_count] = COUNT(*) OVER(PARTITION BY LEFT([sql_text],100)), 
			[tasks_count] = SUM(tasks) OVER(PARTITION BY LEFT([sql_text],100)), 
			--[tasks_count] = SUM(tasks) OVER(PARTITION BY Pool, LEFT(program_name,15), [DBName], LEFT(statement_text,100)), 
			[tasks], [status], [wait_type], [blocked by] = blocking_session_id, [open_tran], [granted_query_memory], 
			[sql_text], [sql_command], [wait_time], [elapsed_time(S)] = DATEDIFF(SECOND,start_time,collection_time), [login_time], 
			granted_query_memory_kb, [memusage], 
			[writes], [reads], [is_user_process], [session_row_count], [request_row_count], 
			[sql_handle], [plan_handle], [request_cpu_time], [request_start_time], [query_hash], [query_plan_hash]
			,[BatchQueryPlan] = CASE WHEN @show_plan = 2 THEN [BatchQueryPlan] ELSE NULL END
			,[SqlQueryPlan] = CASE WHEN @show_plan >= 1 THEN [SqlQueryPlan] ELSE NULL END
			,collection_time_utc = @current_time_UTC
	FROM #SysProcesses ar
	WHERE	(	@pool_name IS NULL -- No pool filter applied
				-- All sessions of Pool, or blockers of Pool session
				OR ( ar.Pool = @pool_name OR ar.session_id IN (SELECT bl.[blocking_session_id] FROM #SysProcesses bl WHERE bl.Pool = @pool_name and ISNULL(bl.[blocking_session_id],0) <> 0) )
			)
			AND
			(	(ar.granted_query_memory_kb/1024.0) >= @granted_memory_threshold_mb )
		
	ORDER BY [granted_query_memory_kb] desc, [tasks_count] desc, query_count desc, LEFT([sql_text],100), [request_start_time]
	OFFSET 0 ROWS FETCH NEXT @top_x_query_rows ROWS ONLY;
END

-- Get Blocking Tree
if exists (select * from #SysProcesses where blocking_session_id <> 0 and session_id <> blocking_session_id)
begin

	;WITH T_BLOCKERS AS
	(
		-- Find block Leaders
		SELECT	[dd hh:mm:ss], [collection_time], [session_id], 
				[sql_text] = REPLACE(REPLACE(REPLACE(REPLACE(CAST(COALESCE([sql_command],[sql_text]) AS VARCHAR(MAX)),char(13),''),CHAR(10),''),'<?query --',''),'--?>',''), 
				command, [login_name], wait_type, r.wait_time, r.wait_resource_type, [blocking_session_id], null as [blocked_session_count],
				[status], open_tran, [host_name], [database_name], [program_name], Pool, tasks,
				r.cpu, r.[tempdb_allocations], r.[tempdb_current], r.[reads], r.[writes], r.[physical_io],
				[LEVEL] = CAST (REPLICATE ('0', 4-LEN (CAST (r.session_id AS VARCHAR))) + CAST (r.session_id AS VARCHAR) AS VARCHAR (1000))
				,[head_blocker] = session_id
		FROM	#SysProcesses AS r
		WHERE	(ISNULL(r.blocking_session_id,0) = 0 OR ISNULL(r.blocking_session_id,0) = r.session_id)
			AND EXISTS (SELECT * FROM #SysProcesses AS R2 WHERE R2.collection_time = r.collection_time AND ISNULL(R2.blocking_session_id,0) = r.session_id AND ISNULL(R2.blocking_session_id,0) <> R2.session_id)
		--	
		UNION ALL
		--
		SELECT	r.[dd hh:mm:ss], r.[collection_time], r.[session_id], 
				[sql_text] = REPLACE(REPLACE(REPLACE(REPLACE(CAST(COALESCE(r.[sql_command],r.[sql_text]) AS VARCHAR(MAX)),char(13),''),CHAR(10),''),'<?query --',''),'--?>',''), 
				r.command, r.[login_name], r.wait_type, r.wait_time, r.wait_resource_type, r.[blocking_session_id], null as [blocked_session_count],
				r.[status], r.open_tran, r.[host_name], r.[database_name], r.[program_name], r.Pool, r.tasks,
				r.cpu, r.[tempdb_allocations], r.[tempdb_current], r.[reads], r.[writes], r.[physical_io],
				CAST (B.LEVEL + RIGHT (CAST ((1000 + r.session_id) AS VARCHAR (100)), 4) AS VARCHAR (1000)) AS LEVEL
				,[head_blocker] = case when B.[head_blocker] is null then B.session_id else B.[head_blocker] end
		FROM	#SysProcesses AS r
		INNER JOIN 
				T_BLOCKERS AS B
			ON	r.collection_time = B.collection_time
			AND	r.blocking_session_id = B.session_id
		WHERE	r.blocking_session_id <> r.session_id
	)
	,T_BlockingTree AS
	(
		SELECT	[dd hh:mm:ss], 
				[BLOCKING_TREE] = N'    ' + REPLICATE (N'|         ', LEN (LEVEL)/4 - 1) 
								+	CASE	WHEN (LEN(LEVEL)/4 - 1) = 0
											THEN 'HEAD -  '
											ELSE '|------  ' 
									END
								+	CAST (r.session_id AS NVARCHAR (10)) + N' ' + ISNULL((CASE WHEN LEFT(ISNULL(r.[sql_text],''),1) = '(' THEN SUBSTRING(ISNULL(r.[sql_text],''),CHARINDEX('exec',ISNULL(r.[sql_text],'')),LEN(ISNULL(r.[sql_text],'')))  ELSE ISNULL(r.[sql_text],'') END),''),
				[session_id], [blocking_session_id], 
				--w.lock_text,
				[head_blocker],		
				[blocked_session_count] = COUNT(*) OVER (PARTITION BY [head_blocker]),
				tasks,
				[sql_commad] = CONVERT(XML, '<?query -- '+char(13)
								+ (CASE WHEN LEFT([sql_text],1) = '(' THEN SUBSTRING([sql_text],CHARINDEX('exec',[sql_text]),LEN([sql_text]))  ELSE [sql_text] END)
								+ char(13)+'--?>')
				,command, [login_name], [program_name], [database_name], wait_type, wait_time, wait_resource_type, status, 
				r.open_tran, r.cpu, r.[reads], r.[writes], r.[physical_io]
				,[host_name] ,Pool
				,LEVEL
		FROM	T_BLOCKERS AS r
	)
	SELECT Pool, [dd hh:mm:ss], [BLOCKING_TREE], [blocked_count] = case when session_id = [head_blocker] then [blocked_session_count] else null end, [sql_commad], [command], [login_name], [program_name], [database_name], [wait_type], 
			--[wait_time], 
			Concat
				(
						RIGHT('00'+CAST(ISNULL(([wait_time] / 1000 / 3600 / 24), 0) AS VARCHAR(2)),2)
						,' '
						,RIGHT('00'+CAST(ISNULL([wait_time] / 1000 / 3600  % 24, 0) AS VARCHAR(2)),2)
						,':'
						,RIGHT('00'+CAST(ISNULL([wait_time] / 1000 / 60 % 60, 0) AS VARCHAR(2)),2)
						,':'
						,RIGHT('00'+CAST(ISNULL([wait_time] / 1000 % 3600 % 60, 0) AS VARCHAR(2)),2)
						,'.'
						,RIGHT('00'+CAST(ISNULL([wait_time] / 1000 % 3600 % 60 % 1000, 0) AS VARCHAR(3)),3)
				) as [wait_time],
			[wait_resource_type], [status], [open_tran], [cpu], [reads], [writes], [physical_io], [host_name]
	FROM T_BlockingTree t
	ORDER BY t.LEVEL;
end

-- Display Log Running Queries
if exists (select * from #SysProcesses s where datediff(minute,s.start_time,s.collection_time) >= @long_running_query_threshold_minutes and (@pool_name is null or s.Pool = @pool_name) and s.session_id > 50 )
begin
	select RunningQuery = ISNULL(@pool_name+'-','')+'Running over '+cast(@long_running_query_threshold_minutes as varchar)+' minutes',
			@current_time_UTC as [Current-Time-UTC],
			Pool,
			*
	from #SysProcesses s
	where datediff(minute,s.start_time,s.collection_time) >= @long_running_query_threshold_minutes
	and (@pool_name is null or s.Pool = @pool_name) and s.session_id > 50
	and s.program_name not in (N'Microsoft® Windows® Operating System')
	--and (	s.blocking_session_id <> 0 
	--	or	exists (select * from #SysProcesses i where i.blocking_session_id = s.session_id)
	--	or	(s.login_name <> 'sa' )
	--	)
	order by start_time asc
	OFFSET 0 ROWS FETCH NEXT @top_x_query_rows ROWS ONLY; 
end

if @get_blitz_analysis = 1
begin
	if object_id('dbo.sp_BlitzFirst') is not null
		exec sp_BlitzFirst --@Seconds = 10, @ExpertMode = 1
	if object_id('dbo.sp_BlitzWho') is not null
		exec sp_BlitzWho
end

IF @all_requests = 1
begin
	if @sort_order_all_sessions is null or len(ltrim(rtrim(@sort_order_all_sessions))) = 0
		set @sort_order_all_sessions = '[elapsed_time_sec] desc, [granted_query_memory_kb] desc';

	--select @sort_order_all_sessions, replace(replace(ltrim(rtrim(replace(replace(left(@sort_order_all_sessions,charindex(',',@sort_order_all_sessions)-1),' desc',''),' asc',''))),'[',''),']','')
	
	declare @sql nvarchar(max);	
	set @sql = 'select RunningQuery = ''All-Sessions-SortedBy-'+(replace(replace(ltrim(rtrim(replace(replace(left(@sort_order_all_sessions,charindex(',',@sort_order_all_sessions)-1),' desc',''),' asc',''))),'[',''),']',''))+''', * from #SysProcesses'
	set @sql = @sql + char(10) + ' order by '+@sort_order_all_sessions;
	exec (@sql);
end

if @show_io_latency = 1 /* Delta IO Latency */
begin	
	declare @wait_for_delay varchar(20);
	set @wait_for_delay = convert(varchar,dateadd(second,@io_snapshot_durations_seconds,'1900-01-01'),108);

	if OBJECT_ID('tempdb..#Snapshot') IS NOT NULL
		drop table #Snapshot;

	CREATE TABLE #Snapshot
	(
		database_id SMALLINT NOT NULL,
		file_id SMALLINT NOT NULL,
		num_of_reads BIGINT NOT NULL,
		num_of_bytes_read BIGINT NOT NULL,
		io_stall_read_ms BIGINT NOT NULL,
		num_of_writes BIGINT NOT NULL,
		num_of_bytes_written BIGINT NOT NULL,
		io_stall_write_ms BIGINT NOT NULL
	);

	INSERT INTO #Snapshot(database_id,file_id,num_of_reads,num_of_bytes_read
		,io_stall_read_ms,num_of_writes,num_of_bytes_written,io_stall_write_ms)
		SELECT database_id,file_id,num_of_reads,num_of_bytes_read
			,io_stall_read_ms,num_of_writes,num_of_bytes_written,io_stall_write_ms
		FROM sys.dm_io_virtual_file_stats(NULL,NULL)
	OPTION (RECOMPILE);

	-- Set test interval (1 minute). 
	WAITFOR DELAY @wait_for_delay;

	;WITH Stats(db_id, file_id, Reads, ReadBytes, Writes
		,WrittenBytes, ReadStall, WriteStall)
	as
	(
		SELECT
			s.database_id, s.file_id
			,fs.num_of_reads - s.num_of_reads
			,fs.num_of_bytes_read - s.num_of_bytes_read
			,fs.num_of_writes - s.num_of_writes
			,fs.num_of_bytes_written - s.num_of_bytes_written
			,fs.io_stall_read_ms - s.io_stall_read_ms
			,fs.io_stall_write_ms - s.io_stall_write_ms
		FROM
			#Snapshot s JOIN sys.dm_io_virtual_file_stats(NULL, NULL) fs ON
				s.database_id = fs.database_id and s.file_id = fs.file_id
	)
	, StatsFormatted AS (
		SELECT RunningQuery = convert(varchar,@io_snapshot_durations_seconds)+'-Seconds-IO-Stats',
			s.db_id AS [DB ID], d.name AS [Database]
			,mf.name AS [File Name], mf.physical_name AS [File Path]
			,mf.type_desc AS [Type], s.Reads 
			,CONVERT(DECIMAL(12,3), s.ReadBytes / 1048576.) AS [Read MB]
			,CONVERT(DECIMAL(12,3), s.WrittenBytes / 1048576.) AS [Written MB]
			,s.Writes, s.Reads + s.Writes AS [IO Count]
			,CONVERT(DECIMAL(5,2),100.0 * s.ReadBytes / 
					(s.ReadBytes + s.WrittenBytes)) AS [Read %]
			,CONVERT(DECIMAL(5,2),100.0 * s.WrittenBytes / 
					(s.ReadBytes + s.WrittenBytes)) AS [Write %]
			,s.ReadStall AS [Read Stall]
			,s.WriteStall AS [Write Stall]
			,CASE WHEN s.Reads = 0 
				THEN 0.000
				ELSE CONVERT(DECIMAL(12,3),1.0 * s.ReadStall / s.Reads) 
			END AS [Avg Read Stall] 
			,CASE WHEN s.Writes = 0 
				THEN 0.000
				ELSE CONVERT(DECIMAL(12,3),1.0 * s.WriteStall / s.Writes) 
			END AS [Avg Write Stall] 
		FROM
			Stats s JOIN sys.master_files mf WITH (NOLOCK) ON
				s.db_id = mf.database_id and
				s.file_id = mf.file_id
			JOIN sys.databases d WITH (NOLOCK) ON 
				s.db_id = d.database_id  
		WHERE -- Only display files with more than 20MB throughput
			(s.ReadBytes + s.WrittenBytes) > 20 * 1048576
	)
	SELECT	*
	FROM	StatsFormatted
	ORDER BY ([Avg Read Stall]+[Avg Write Stall]) desc
	OPTION (RECOMPILE);
END
go