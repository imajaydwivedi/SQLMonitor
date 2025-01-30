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

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_collect_performance_metrics')
    EXEC ('CREATE PROC dbo.usp_collect_performance_metrics AS SELECT ''stub version, to be replaced''')
GO

alter procedure [dbo].[usp_collect_performance_metrics]
	@metrics varchar(125) = 'all',
	@snapshot_delay_hhmmss char(8) = '00:00:10',
	@verbose tinyint = 1
as
begin
/*	Created By:		Ajay Dwivedi (https://ajaydwivedi.com/go/sqlmonitor)
	Version:		1.0
	Modification:	2025-Jan-26 - Integrate in SQLMonitor

	exec dbo.[usp_collect_performance_metrics] @metrics = 'dm_os_sys_memory';
	exec dbo.[usp_collect_performance_metrics] @metrics = 'dm_os_process_memory';
	exec dbo.[usp_collect_performance_metrics] @metrics = 'dm_os_performance_counters';
	exec dbo.[usp_collect_performance_metrics] @metrics = 'dm_os_performance_counters_sampling';
	exec dbo.[usp_collect_performance_metrics] @metrics = 'dm_os_ring_buffers';
	exec dbo.[usp_collect_performance_metrics] @metrics = 'dm_os_memory_clerks';
	exec dbo.[usp_collect_performance_metrics] @metrics = 'dm_os_performance_counters_deprecated_features';

	PERF_COUNTER_RAWCOUNT | Decimal | 65536
	-> Raw counter value that does not require calculations, and represents one sample.
	-> Could not find any records for this type in sys.dm_os_performance_counters

	PERF_COUNTER_LARGE_RAWCOUNT | Decimal | 65792
	-> Raw counter value that does not require calculations, and represents one sample.
	-> Same as PERF_COUNTER_RAWCOUNT, but a 64-bit representation for larger values.

	PERF_LARGE_RAW_FRACTION | Decimal | 537003264
	-> These counters show a ratio, i.e. fraction between two values ? the PERF_LARGE_RAW_FRACTION counter and its corresponding PERF_LARGE_RAW_BASE counter value
	-> For example, Buffer cache hit ratio

	PERF_LARGE_RAW_BASE | Decimal | 1073939712
	-> This counter value is used as the denominator for further calculation. The counters of this type are only used to calculate other counters available via the view
	-> All counters that belong to this counter type have the word base in their names, so it?s a clear indication that this is not a counter that provides useful info, it?s just a base value for further calculations
	-> For example, Buffer cache hit ratio base

	PERF_AVERAGE_BULK | Decimal | 1073874176
	-> The cntr_value column value is cumulative. To calculate the current value of the counter, you have to monitor the PERF_AVERAGE_BULK and its corresponding PERF_LARGE_RAW_BASE counter, take two samples of each at the same time, and use these values for the calculation

	PERF_COUNTER_COUNTER | Decimal | 272696320
	-> Average number of operations completed during each second of the sample interval. NOTE: For "per-second counters", this value is cumulative. The rate value must be calculated by sampling the value at discrete time intervals. The difference between any two successive sample values is equal to the rate for the time interval used. 
	-> For example, batch requests/sec is a per-second counter, it would show cumulative values.

	PERF_COUNTER_BULK_COUNT | Decimal | 272696576
	-> Average number of operations completed during each second of the sample interval. This counter type is the same as the PERF_COUNTER_COUNTER type, but it uses larger fields to accommodate larger values.

*/
	set nocount on;

	-- Declare variables
	declare @_current_time_utc datetime2; /* removing usage of this due to high Page Splits */
	declare @_tab nchar(2);
	declare @_object_name varchar(255);
	declare @_step_name varchar(50);
	declare @_host_name varchar(255);

	-- Initialize variables
	set @_current_time_utc = sysutcdatetime();
	set @_tab = '  ';
	set @_object_name = (case when @@SERVICENAME = 'MSSQLSERVER' then 'SQLServer' else 'MSSQL$'+@@SERVICENAME end);
	set @_host_name = convert(varchar(255),COALESCE(SERVERPROPERTY('ComputerNamePhysicalNetBIOS'),SERVERPROPERTY('ServerName')));

	if @verbose > 0
		print '@_object_name => '+@_object_name;

	-- Get Total RAM & Available Memory
	set @_step_name = 'dm_os_sys_memory';
	if (@metrics = 'all' or @metrics = @_step_name)
	begin
		if @verbose > 0
			print 'Working on @_step_name => '+@_step_name;

		;with cte_unpvt as 
		(	select *
			from (
				select	[total_physical_memory_kb],
						[available_physical_memory_kb]
				from sys.dm_os_sys_memory as osm
			) osm
			unpivot (
				value for counter in ([total_physical_memory_kb], [available_physical_memory_kb])
			) as unpvt
		)
		insert dbo.performance_counters
		(collection_time_utc, host_name, object, counter, value, instance)
		select	[collection_time_utc] = SYSUTCDATETIME(),	[host_name] = @_host_name,
				[object] = case when unpvt.counter in ('available_physical_memory_kb', 'total_physical_memory_kb')
								then 'memory'
								when unpvt.counter in ('available_physical_memory_kb', 'total_physical_memory_kb')
								then 'memory'
								else null
								end,
				[counter] = case when unpvt.counter = 'available_physical_memory_kb'
								then 'available mbytes'
								when unpvt.counter = 'total_physical_memory_kb'
								then 'physical memory (mb)'
								else unpvt.counter
								end,
				[value] = case	when unpvt.counter = 'available_physical_memory_kb'
								then convert(numeric(20,2),unpvt.value*1.0/1024)
								when unpvt.counter = 'total_physical_memory_kb'
								then convert(numeric(20,2),unpvt.value*1.0/1024)
								else unpvt.value
								end,
				[instance] = null
		from cte_unpvt unpvt;
	end


	-- Get SqlServer Process Memory
	set @_step_name = 'dm_os_process_memory';
	if (@metrics = 'all' or @metrics = @_step_name)
	begin
		if @verbose > 0
			print 'Working on @_step_name => '+@_step_name;

		;with cte_unpvt as 
		(	select *
			from (
				select	physical_memory_in_use_kb = convert(numeric(20,2),physical_memory_in_use_kb),
						page_fault_count = convert(numeric(20,2),page_fault_count),
						memory_utilization_percentage = convert(numeric(20,2),memory_utilization_percentage),
						locked_page_allocations_kb = convert(numeric(20,2),locked_page_allocations_kb),
						large_page_allocations_kb = convert(numeric(20,2),large_page_allocations_kb)
				from sys.dm_os_process_memory opm
			) opm
			unpivot (
				value for counter in (physical_memory_in_use_kb, locked_page_allocations_kb, page_fault_count, 
										memory_utilization_percentage, large_page_allocations_kb
									)
			) as unpvt
		)
		insert dbo.performance_counters
		(collection_time_utc, host_name, object, counter, value, instance)
		select	[collection_time_utc] = SYSUTCDATETIME(),	[host_name] = @_host_name,
				[object] =	@_object_name+':'+
							case when unpvt.counter in ('physical_memory_in_use_kb', 'locked_page_allocations_kb','page_fault_count',
														'memory_utilization_percentage','large_page_allocations_kb')
								then 'memory'
								else null
								end,
				[counter] = case when unpvt.counter = 'physical_memory_in_use_kb'
								then 'physical memory in use (mb)'
								when unpvt.counter = 'locked_page_allocations_kb'
								then 'locked page allocations (mb)'
								when unpvt.counter = 'large_page_allocations_kb'
								then 'large page allocations (mb)'
								when unpvt.counter = 'page_fault_count'
								then 'page fault count'
								when unpvt.counter = 'memory_utilization_percentage'
								then 'memory utilization %'
								else unpvt.counter
								end,
				[value] = case	when unpvt.counter in ('physical_memory_in_use_kb','locked_page_allocations_kb','large_page_allocations_kb')
								then convert(numeric(20,2),unpvt.value*1.0/1024)
								when unpvt.counter in ('page_fault_count','memory_utilization_percentage')
								then convert(numeric(20,2),unpvt.value)
								else unpvt.value
								end,
				[instance] = null
		from cte_unpvt unpvt;
	end


	-- Get CPU utilization
	set @_step_name = 'dm_os_ring_buffers'
	if (@metrics = 'all' or @metrics = @_step_name)
	begin
		if @verbose > 0
			print 'Working on @_step_name => '+@_step_name;

		;with cte_unpvt as 
		(	select	*
			from (
				SELECT	top 1
						[collection_time_utc] = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), collection_time),  
						[system_cpu_utilization] = CASE WHEN system_cpu_utilization_post_sp2 IS NOT NULL THEN system_cpu_utilization_post_sp2 ELSE system_cpu_utilization_pre_sp2 END,  
						[sql_cpu_utilization] = CASE WHEN sql_cpu_utilization_post_sp2 IS NOT NULL THEN sql_cpu_utilization_post_sp2 ELSE sql_cpu_utilization_pre_sp2 END 
				FROM  (	SELECT	record.value('(Record/@id)[1]', 'int') AS record_id,
								DATEADD (ms, -1 * (ts_now - [timestamp]), SYSDATETIME()) AS collection_time,
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
				ORDER BY [collection_time_utc] desc
			) AS cpu
			unpivot (
				value for counter in ([system_cpu_utilization], [sql_cpu_utilization])
			) as unpvt
		)
		,cte_pc as (
			select	[collection_time_utc], [host_name] = @_host_name,
					[object] =	case when unpvt.counter = 'system_cpu_utilization'
									then 'processor'
									when unpvt.counter = 'sql_cpu_utilization'
									then 'process'
									else null
									end,
					[counter] = '% processor time',
					[value] = convert(numeric(20,2),unpvt.value),
					[instance] = case when unpvt.counter = 'system_cpu_utilization'
									then '_total'
									when unpvt.counter = 'sql_cpu_utilization'
									then 'sqlservr$'+convert(varchar(125),@@SERVICENAME)
									else null
									end
			from cte_unpvt unpvt
		)
		insert dbo.performance_counters
		(collection_time_utc, host_name, object, counter, value, instance)
		select collection_time_utc, host_name, object, counter, value, instance
		from cte_pc cpc
		where not exists (select * from dbo.performance_counters epc where epc.collection_time_utc = cpc.collection_time_utc 
							and epc.object = cpc.object and epc.host_name = cpc.host_name)
	end


	-- Get dm_os_performance_counters
	set @_step_name = 'dm_os_performance_counters';
	if (@metrics = 'all' or @metrics = @_step_name)
	begin
		if @verbose > 0
			print 'Working on @_step_name => '+@_step_name;

		-- https://www.sqlshack.com/troubleshooting-sql-server-issues-sys-dm_os_performance_counters/
		insert dbo.performance_counters
		([collection_time_utc], [host_name], [object], [counter], [value], [instance])
		select	/* -- all performance counters that do not require additional calculation */
				[collection_time_utc] = SYSUTCDATETIME(), 
				[host_name] = @_host_name,
				[object] = lower(rtrim(object_name)), 
				[counter] = lower(rtrim(counter_name)), 
				[value] = cntr_value,
				[instance] = lower(rtrim(instance_name))		
				--,cntr_type
				--,id = row_number()over(order by sysdatetime())
		from sys.dm_os_performance_counters as pc
		where cntr_type in ( 65792 /* PERF_COUNTER_LARGE_RAWCOUNT */	)
		  and
		  (	( [object_name] LIKE (@_object_name+':Buffer Manager%') AND counter_name like 'Page life expectancy%' )
		    or
			( [object_name] like (@_object_name+':Buffer Manager%') and [counter_name] like 'Database pages%' )
			or
			( [object_name] like (@_object_name+':Buffer Manager%') and [counter_name] like 'Target pages%' )
			or
			( [object_name] LIKE (@_object_name+':Memory Manager%') AND counter_name like 'Memory Grants Pending%' )
			or
			( [object_name] LIKE (@_object_name+':Memory Manager%') AND counter_name like 'Granted Workspace Memory (KB)%' )
			or
			( [object_name] LIKE (@_object_name+':Memory Manager%') AND counter_name like 'Maximum Workspace Memory (KB)%' )
			or
			( [object_name] LIKE (@_object_name+':Memory Manager%') AND counter_name like 'Memory Grants Outstanding%' )
			or
			( [object_name] LIKE (@_object_name+':Memory Manager%') AND counter_name like 'Stolen Server Memory (KB)%' )
			or
			( [object_name] LIKE (@_object_name+':Memory Manager%') AND counter_name = 'Total Server Memory (KB)' )
			or
			( [object_name] LIKE (@_object_name+':Memory Manager%') AND counter_name = 'Target Server Memory (KB)' )
			or
			( [object_name] LIKE (@_object_name+':Memory Manager%') AND counter_name = 'SQL Cache Memory (KB)' )
			or
			( [object_name] LIKE (@_object_name+':Memory Manager%') AND counter_name = 'Free Memory (KB)' )
			or
			( [object_name] like (@_object_name+':Databases%') and [counter_name] like 'Data File(s) Size (KB)%' )
			or
			( [object_name] like (@_object_name+':Databases%') and [counter_name] like 'Log File(s) Size (KB)%' )
			or
			( [object_name] like (@_object_name+':Databases%') and [counter_name] like 'Log File(s) Used Size (KB)%' )
			or
			( [object_name] like (@_object_name+':Databases%') and [counter_name] like 'Log Growths%' )
			or
			( [object_name] like (@_object_name+':Databases%') and [counter_name] like 'Log Shrinks%' )
			or
			( [object_name] like (@_object_name+':Databases%') and [counter_name] like 'Log Truncations%' )
			or
			( [object_name] like (@_object_name+':Databases%') and [counter_name] like 'Percent Log Used%' )
			or
			( [object_name] like (@_object_name+':Cursor Manager by Type%') and [counter_name] like 'Active cursors%' )
			or
			( [object_name] like (@_object_name+':General Statistics%') and [counter_name] like 'User Connections%' )
			or
			( [object_name] like (@_object_name+':Wait Statistics%') )
			or
			( [object_name] like (@_object_name+':Transactions%') and [counter_name] like 'Free Space in tempdb (KB)%' )
			or
			( [object_name] like (@_object_name+':Transactions%') and [counter_name] like 'Longest Transaction Running Time%' )
			or
			( [object_name] like (@_object_name+':Transactions%') and [counter_name] like 'Transactions%' )
			or
			( [object_name] like (@_object_name+':Transactions%') and [counter_name] like 'Version Store Size (KB)%' )
		);
	end
		
	-- Get dm_os_performance_counters__FractionBase
	set @_step_name = 'dm_os_performance_counters__FractionBase';
	if (@metrics = 'all' or @metrics = @_step_name)
	begin
		if @verbose > 0
			print 'Working on @_step_name => '+@_step_name;

		-- https://www.sqlshack.com/troubleshooting-sql-server-issues-sys-dm_os_performance_counters/
		insert dbo.performance_counters
		([collection_time_utc], [host_name], [object], [counter], [value], [instance])
		SELECT	/* counter that require Fraction & Base */
				[collection_time_utc] = SYSUTCDATETIME(),
				[host_name] = @_host_name, 
				[object] = lower(rtrim(fr.object_name)),
				[counter] = lower(rtrim(fr.counter_name)),
				[value] = case when bs.cntr_value <> 0 then (100*(fr.cntr_value/bs.cntr_value)) else fr.cntr_value end,
				[instance] = lower(rtrim(fr.instance_name))
				--,fr.cntr_type
				--,id = ROW_NUMBER()OVER(ORDER BY SYSDATETIME())
		FROM sys.dm_os_performance_counters as fr
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
		WHERE fr.cntr_type = 537003264 /* PERF_LARGE_RAW_FRACTION */
		  and
		  ( ( fr.[object_name] like (@_object_name+':Buffer Manager%') and fr.counter_name like 'Buffer cache hit ratio%' )
			or
			( fr.[object_name] like (@_object_name+':Access Methods%') and fr.counter_name like 'Worktables From Cache Ratio%' )
			or
			( fr.[object_name] like (@_object_name+':Resource Pool Stats%') and fr.counter_name like 'CPU usage %' )
			or
			( fr.[object_name] like (@_object_name+':Workload Group Stats%') and fr.counter_name like 'CPU usage %' )
		  );
	end

	-- Get dm_os_performance_counters__deprecated_features
	set @_step_name = 'dm_os_performance_counters__deprecated_features';
	if (@metrics = 'all' or @metrics = @_step_name)
	begin
		if @verbose > 0
			print 'Working on @_step_name => '+@_step_name;

		insert dbo.performance_counters
		([collection_time_utc], [host_name], [object], [counter], [value], [instance])
		SELECT	/* -- all performance counters that do not require additional calculation */
				[collection_time_utc] = sysutcdatetime(), 
				[host_name] = @_host_name,
				[object] = lower(rtrim(object_name)),
				[counter] = lower(rtrim(counter_name)),
				[value] = cntr_value,
				[instance] = lower(rtrim(instance_name))
				--,cntr_type
				--,id = ROW_NUMBER()OVER(ORDER BY SYSDATETIME())
		FROM sys.dm_os_performance_counters as pc
		WHERE [object_name] like (@_object_name+':Deprecated Features%')
		AND cntr_value > 0;
	end


	-- Get dm_os_performance_counters__sampling
	set @_step_name = 'dm_os_performance_counters__sampling';
	if (@metrics = 'all' or @metrics = @_step_name)
	begin
		-- https://www.sqlshack.com/troubleshooting-sql-server-issues-sys-dm_os_performance_counters/

		if @verbose > 0
			print 'Working on @_step_name => '+@_step_name;

		if @verbose > 0
			print @_tab+'Create table #dm_os_performance_counters_PERF_AVERAGE_BULK_t1..';

		IF OBJECT_ID('tempdb..#dm_os_performance_counters_PERF_AVERAGE_BULK_t1') IS NOT NULL
			DROP TABLE #dm_os_performance_counters_PERF_AVERAGE_BULK_t1;
		SELECT SYSDATETIME() as collection_time, * 
		INTO #dm_os_performance_counters_PERF_AVERAGE_BULK_t1
		FROM sys.dm_os_performance_counters as pc
		WHERE cntr_type in (1073874176 /* PERF_AVERAGE_BULK */
							,1073939712 /* PERF_LARGE_RAW_BASE */
							) --  
		  and
		  ( ( [object_name] like (@_object_name+':Locks%') and counter_name like 'Average Wait Time%' )
			or
			( [object_name] like (@_object_name+':Latches%') and counter_name like 'Average Latch Wait Time%' )
			or
			( [object_name] like (@_object_name+':Resource Pool Stats%') and counter_name like 'Avg Disk Read IO%' )
			or
			( [object_name] like (@_object_name+':Resource Pool Stats%') and counter_name like 'Avg Disk Write IO%' )
		  );

		
		if @verbose > 0
			print @_tab+'Create table #dm_os_performance_counters_PERF_COUNTER_BULK_COUNT_t1..';

		IF OBJECT_ID('tempdb..#dm_os_performance_counters_PERF_COUNTER_BULK_COUNT_t1') IS NOT NULL
			DROP TABLE #dm_os_performance_counters_PERF_COUNTER_BULK_COUNT_t1;
		SELECT SYSDATETIME() as collection_time, * 
		INTO #dm_os_performance_counters_PERF_COUNTER_BULK_COUNT_t1
		FROM sys.dm_os_performance_counters as pc
		WHERE cntr_type = 272696576 /* PERF_COUNTER_BULK_COUNT */
		  and
		  ( ( [object_name] like (@_object_name+':SQL Statistics%') and counter_name like 'Batch Requests/sec%' )
			or
			( [object_name] like (@_object_name+':SQL Statistics%') and counter_name like 'SQL Attention rate%' )
			or
			( [object_name] like (@_object_name+':SQL Statistics%') and counter_name like 'SQL Compilations/sec%' )
			or
			( [object_name] like (@_object_name+':SQL Statistics%') and counter_name like 'SQL Re-Compilations/sec%' )
			or
			( [object_name] like (@_object_name+':SQL Statistics%') and [counter_name] like 'Auto-Param Attempts/sec%' )
			or
			( [object_name] like (@_object_name+':SQL Statistics%') and [counter_name] like 'Failed Auto-Params/sec%' )
			or
			( [object_name] like (@_object_name+':SQL Statistics%') and [counter_name] like 'Safe Auto-Params/sec%' )
			or
			( [object_name] like (@_object_name+':SQL Statistics%') and [counter_name] like 'Unsafe Auto-Params/sec%' )
			or
			( [object_name] like (@_object_name+':Buffer Manager%') and counter_name like 'Page lookups/sec%')
			or
			( [object_name] like (@_object_name+':Buffer Manager%') and counter_name like 'Lazy writes/sec%')
			or
			( [object_name] like (@_object_name+':Buffer Manager%') and counter_name like 'Page reads/sec%')
			or
			( [object_name] like (@_object_name+':Buffer Manager%') and counter_name like 'Page writes/sec%')
			or
			( [object_name] like (@_object_name+':Buffer Manager%') and counter_name like 'Logins/sec%')
			or
			( [object_name] like (@_object_name+':Buffer Manager%') and counter_name like 'Free list stalls/sec%')
			or
			( [object_name] like (@_object_name+':Buffer Manager%') and counter_name like 'Checkpoint pages/sec%')
			or
			( [object_name] like (@_object_name+':Buffer Manager%') and counter_name like 'Readahead pages/sec%')
			or
			( [object_name] like (@_object_name+':Locks%') and counter_name like 'Number of Deadlocks/sec%' )
			or
			( [object_name] like (@_object_name+':Locks%') and counter_name like 'Lock Wait Time (ms)%')
			or
			( [object_name] like (@_object_name+':Locks%') and counter_name like 'Lock Waits/sec%')
			or
			( [object_name] like (@_object_name+':Latches%') and [counter_name] like 'Latch Waits/sec%' )
			or
			( [object_name] like (@_object_name+':Latches%') and [counter_name] like 'Total Latch Wait Time (ms)%' )
			or
			( [object_name] like (@_object_name+':Access Methods%') and counter_name like 'Full Scans/sec%')
			or
			( [object_name] like (@_object_name+':Access Methods%') and counter_name like 'Forwarded Records/sec%')
			or
			( [object_name] like (@_object_name+':Access Methods%') and counter_name like 'Index Searches/sec%')
			or
			( [object_name] like (@_object_name+':Access Methods%') and counter_name like 'Page Splits/sec%')
			or
			( [object_name] like (@_object_name+':Access Methods%') and counter_name like 'Workfiles Created/sec%')
			or
			( [object_name] like (@_object_name+':Access Methods%') and counter_name like 'Worktables Created/sec%')
			or
			( [object_name] like (@_object_name+':Access Methods%') and counter_name like 'Table Lock Escalations/sec%')
			or
			( [object_name] like (@_object_name+':Databases%') and counter_name like 'Log Bytes Flushed/sec%')
			or
			( [object_name] like (@_object_name+':Databases%') and counter_name like 'Log Flush Wait Time%')
			or
			( [object_name] like (@_object_name+':Databases%') and counter_name like 'Log Flush Waits/sec%')
			or
			( [object_name] like (@_object_name+':Databases%') and counter_name like 'Log Flushes/sec%')
			or
			( [object_name] like (@_object_name+':SQL Errors%') and counter_name like 'Errors/sec%')
			or
			( [object_name] like (@_object_name+':General Statistics%') and [counter_name] like 'Logins/sec%' )
			or
			( [object_name] like (@_object_name+':General Statistics%') and [counter_name] like 'Logouts/sec%' )
		  );

		if @verbose > 0
			print @_tab+'Collect Disk Latency - Snapshot 01..';

		-- Collect Disk Latency - Snapshot 01
		if object_id('tempdb..#virtual_file_stats_s1') is not null
			drop table #virtual_file_stats_s1;
		select	collection_time_utc = sysutcdatetime(),
				ovs.volume_mount_point, [num_of_reads] = sum(num_of_reads), [num_of_bytes_read] = sum(num_of_bytes_read), 
				[io_stall_read_ms] = sum(io_stall_read_ms), [num_of_writes] = sum(num_of_writes), 
				[num_of_bytes_written] = sum(num_of_bytes_written), [io_stall_write_ms] = sum(io_stall_write_ms), 
				[io_stall] = sum(io_stall),	[size_on_disk_bytes] = sum(size_on_disk_bytes)
		into #virtual_file_stats_s1
		from sys.dm_io_virtual_file_stats(null,null) vfs
		outer apply sys.dm_os_volume_stats(vfs.database_id, vfs.file_id) ovs
		group by ovs.volume_mount_point;

		--
		if @verbose > 0
			print @_tab+'WAITFOR DELAY '+@snapshot_delay_hhmmss+'..';

		WAITFOR DELAY @snapshot_delay_hhmmss;
		--

		if @verbose > 0
			print @_tab+'Create table #dm_os_performance_counters_PERF_AVERAGE_BULK_t2..';

		IF OBJECT_ID('tempdb..#dm_os_performance_counters_PERF_AVERAGE_BULK_t2') IS NOT NULL
			DROP TABLE #dm_os_performance_counters_PERF_AVERAGE_BULK_t2;
		SELECT SYSDATETIME() as collection_time, * 
		INTO #dm_os_performance_counters_PERF_AVERAGE_BULK_t2
		FROM sys.dm_os_performance_counters as pc
		WHERE cntr_type in (1073874176 /* PERF_AVERAGE_BULK */
							,1073939712 /* PERF_LARGE_RAW_BASE */
							) --  
		  and
		  ( ( [object_name] like (@_object_name+':Locks%') and counter_name like 'Average Wait Time%' )
			or
			( [object_name] like (@_object_name+':Latches%') and counter_name like 'Average Latch Wait Time%' )
			or
			( [object_name] like (@_object_name+':Resource Pool Stats%') and counter_name like 'Avg Disk Read IO%' )
			or
			( [object_name] like (@_object_name+':Resource Pool Stats%') and counter_name like 'Avg Disk Write IO%' )
		  );

		-- Counts
		if @verbose > 0
			print @_tab+'Create table #dm_os_performance_counters_PERF_COUNTER_BULK_COUNT_t2..';

		IF OBJECT_ID('tempdb..#dm_os_performance_counters_PERF_COUNTER_BULK_COUNT_t2') IS NOT NULL
			DROP TABLE #dm_os_performance_counters_PERF_COUNTER_BULK_COUNT_t2;
		SELECT SYSDATETIME() as collection_time, * 
		INTO #dm_os_performance_counters_PERF_COUNTER_BULK_COUNT_t2
		FROM sys.dm_os_performance_counters as pc
		WHERE cntr_type = 272696576 /* PERF_COUNTER_BULK_COUNT */
		  and
		  ( ( [object_name] like (@_object_name+':SQL Statistics%') and counter_name like '%Batch Requests/sec%' )
			or
			( [object_name] like (@_object_name+':SQL Statistics%') and counter_name like 'SQL Attention rate%' )
			or
			( [object_name] like (@_object_name+':SQL Statistics%') and counter_name like 'SQL Compilations/sec%' )
			or
			( [object_name] like (@_object_name+':SQL Statistics%') and counter_name like 'SQL Re-Compilations/sec%' )
			or
			( [object_name] like (@_object_name+':SQL Statistics%') and [counter_name] like 'Auto-Param Attempts/sec%' )
			or
			( [object_name] like (@_object_name+':SQL Statistics%') and [counter_name] like 'Failed Auto-Params/sec%' )
			or
			( [object_name] like (@_object_name+':SQL Statistics%') and [counter_name] like 'Safe Auto-Params/sec%' )
			or
			( [object_name] like (@_object_name+':SQL Statistics%') and [counter_name] like 'Unsafe Auto-Params/sec%' )
			or
			( [object_name] like (@_object_name+':Buffer Manager%') and counter_name like 'Page lookups/sec%')
			or
			( [object_name] like (@_object_name+':Buffer Manager%') and counter_name like 'Lazy writes/sec%')
			or
			( [object_name] like (@_object_name+':Buffer Manager%') and counter_name like 'Page reads/sec%')
			or
			( [object_name] like (@_object_name+':Buffer Manager%') and counter_name like 'Page writes/sec%')
			or
			( [object_name] like (@_object_name+':Buffer Manager%') and counter_name like 'Logins/sec%')
			or
			( [object_name] like (@_object_name+':Buffer Manager%') and counter_name like 'Free list stalls/sec%')
			or
			( [object_name] like (@_object_name+':Buffer Manager%') and counter_name like 'Checkpoint pages/sec%')
			or
			( [object_name] like (@_object_name+':Buffer Manager%') and counter_name like 'Readahead pages/sec%')
			or
			( [object_name] like (@_object_name+':Locks%') and counter_name like 'Number of Deadlocks/sec%' )
			or
			( [object_name] like (@_object_name+':Locks%') and counter_name like 'Lock Wait Time (ms)%')
			or
			( [object_name] like (@_object_name+':Locks%') and counter_name like 'Lock Waits/sec%')
			or
			( [object_name] like (@_object_name+':Latches%') and [counter_name] like 'Latch Waits/sec%' )
			or
			( [object_name] like (@_object_name+':Latches%') and [counter_name] like 'Total Latch Wait Time (ms)%' )
			or
			( [object_name] like (@_object_name+':Access Methods%') and counter_name like 'Full Scans/sec%')
			or
			( [object_name] like (@_object_name+':Access Methods%') and counter_name like 'Forwarded Records/sec%')
			or
			( [object_name] like (@_object_name+':Access Methods%') and counter_name like 'Index Searches/sec%')
			or
			( [object_name] like (@_object_name+':Access Methods%') and counter_name like 'Page Splits/sec%')
			or
			( [object_name] like (@_object_name+':Access Methods%') and counter_name like 'Workfiles Created/sec%')
			or
			( [object_name] like (@_object_name+':Access Methods%') and counter_name like 'Worktables Created/sec%')
			or
			( [object_name] like (@_object_name+':Access Methods%') and counter_name like 'Table Lock Escalations/sec%')
			or
			( [object_name] like (@_object_name+':Databases%') and counter_name like 'Log Bytes Flushed/sec%')
			or
			( [object_name] like (@_object_name+':Databases%') and counter_name like 'Log Flush Wait Time%')
			or
			( [object_name] like (@_object_name+':Databases%') and counter_name like 'Log Flush Waits/sec%')
			or
			( [object_name] like (@_object_name+':Databases%') and counter_name like 'Log Flushes/sec%')
			or
			( [object_name] like (@_object_name+':SQL Errors%') and counter_name like 'Errors/sec%')
			or
			( [object_name] like (@_object_name+':General Statistics%') and [counter_name] like 'Logins/sec%' )
			or
			( [object_name] like (@_object_name+':General Statistics%') and [counter_name] like 'Logouts/sec%' )
		  );

		if @verbose > 0
			print @_tab+'Collect Disk Latency - Snapshot 02..';

		-- Collect Disk Latency - Snapshot 02
		if object_id('tempdb..#virtual_file_stats_s2') is not null
			drop table #virtual_file_stats_s2;
		select	collection_time_utc = sysutcdatetime(),
				ovs.volume_mount_point, [num_of_reads] = sum(num_of_reads), [num_of_bytes_read] = sum(num_of_bytes_read), 
				[io_stall_read_ms] = sum(io_stall_read_ms), [num_of_writes] = sum(num_of_writes), 
				[num_of_bytes_written] = sum(num_of_bytes_written), [io_stall_write_ms] = sum(io_stall_write_ms), 
				[io_stall] = sum(io_stall),	[size_on_disk_bytes] = sum(size_on_disk_bytes)
		into #virtual_file_stats_s2
		from sys.dm_io_virtual_file_stats(null,null) vfs
		outer apply sys.dm_os_volume_stats(vfs.database_id, vfs.file_id) ovs
		group by ovs.volume_mount_point;

		if @verbose > 0
			print @_tab+'Populate dbo.performance_counters for [PERF_AVERAGE_BULK]..';
		;WITH Time_Samples AS (
			SELECT t1.collection_time as time1, t2.collection_time as time2,
					t1.object_name, t1.counter_name, t1.instance_name,
					t1.cntr_type as cntr_type_t1, t1.cntr_value as cntr_value_t1,
					t2.cntr_type as cntr_type_t2, t2.cntr_value as cntr_value_t2
			FROM #dm_os_performance_counters_PERF_AVERAGE_BULK_t1 as t1
			join #dm_os_performance_counters_PERF_AVERAGE_BULK_t2 as t2
			  on t1.collection_time < t2.collection_time 
				and t2.object_name = t1.object_name and t2.counter_name = t1.counter_name 
				and ISNULL(t2.instance_name,'') = ISNULL(t1.instance_name,'')
				and t1.cntr_type = t2.cntr_type
		)
		insert dbo.performance_counters
		([collection_time_utc], [host_name], [object], [counter], [value], [instance])
		SELECT	[collection_time_utc] = SYSUTCDATETIME(),
				[host_name] = @_host_name,
				[object] = lower(rtrim(fr.object_name)), 
				[counter] = lower(rtrim(fr.counter_name)), 
				[value] = case when (bs.cntr_value_t2-bs.cntr_value_t1) <> 0 then (fr.cntr_value_t2-fr.cntr_value_t1)/(bs.cntr_value_t2-bs.cntr_value_t1) 
								else (fr.cntr_value_t2-fr.cntr_value_t1) end,
				instance_name = lower(rtrim(fr.instance_name))
				--,cntr_type = fr.cntr_type_t2
				--,id = ROW_NUMBER()OVER(ORDER BY SYSDATETIME())
		FROM Time_Samples as fr join Time_Samples as bs 
		on fr.cntr_type_t2 = '1073874176' and bs.cntr_type_t2 = '1073939712'
			and fr.object_name = bs.object_name
			and (	replace(rtrim(fr.counter_name),' (ms)','') = replace(rtrim(bs.counter_name),' Base','')
					or
					replace(lower(rtrim(bs.counter_name)),' base','') = lower(rtrim(fr.counter_name))
				)
			and ISNULL(fr.instance_name,'') = ISNULL(bs.instance_name,'');

		if @verbose > 0
			print @_tab+'Populate dbo.performance_counters for [PERF_COUNTER_BULK_COUNT]..';
		;WITH Time_Samples AS (
			SELECT t1.collection_time as time1, t2.collection_time as time2,
					t1.object_name, t1.counter_name, t1.instance_name,
					t1.cntr_type as cntr_type_t1, t1.cntr_value as cntr_value_t1,
					t2.cntr_type as cntr_type_t2, t2.cntr_value as cntr_value_t2
			FROM #dm_os_performance_counters_PERF_COUNTER_BULK_COUNT_t1 as t1
			join #dm_os_performance_counters_PERF_COUNTER_BULK_COUNT_t2 as t2
			  on t1.collection_time < t2.collection_time and 
				 t2.object_name = t1.object_name and t2.counter_name = t1.counter_name and ISNULL(t2.instance_name,'') = ISNULL(t1.instance_name,'')
		)
		insert dbo.performance_counters
		([collection_time_utc], [host_name], [object], [counter], [value], [instance])
		SELECT	[collection_time_utc] = SYSUTCDATETIME(),
				[host_name] = @_host_name,
				[object] = lower(rtrim(object_name)),
				[counter] = lower(rtrim(counter_name)),
				[value] = (cntr_value_t2-cntr_value_t1)/(DATEDIFF(SECOND,time1,time2)),
				[instance] = lower(rtrim(instance_name))
				--,cntr_type = cntr_type_t2
				--,id = ROW_NUMBER()OVER(ORDER BY SYSDATETIME())
		FROM Time_Samples;

		if @verbose > 0
			print @_tab+'Compute #volume_stats..';
		if object_id('tempdb..#volume_stats') is not null
			drop table #volume_stats;
		;with stats as (
			select	[time_sample_ms] = DATEDIFF(MILLISECOND,s1.collection_time_utc,s2.collection_time_utc),
					[time_sample_sec] = DATEDIFF(SECOND,s1.collection_time_utc,s2.collection_time_utc),
					[disk_volume] = s2.volume_mount_point,
					[num_of_reads] = s2.num_of_reads-isnull(s1.num_of_reads,0),
					[num_of_bytes_read] = s2.num_of_bytes_read-isnull(s1.num_of_bytes_read,0),
					[io_stall_read_ms] = s2.io_stall_read_ms-isnull(s1.io_stall_read_ms,0),
					[num_of_writes] = s2.num_of_writes-isnull(s1.num_of_writes,0),
					[num_of_bytes_written] = s2.num_of_bytes_written-isnull(s1.num_of_bytes_written,0),
					[io_stall_write_ms] = s2.io_stall_write_ms-isnull(s1.io_stall_write_ms,0),
					[io_stall] = s2.io_stall-isnull(s1.io_stall,0)
			from #virtual_file_stats_s2 s2
			left join #virtual_file_stats_s1 s1
				on s1.volume_mount_point = s2.volume_mount_point
		)
		select	[collection_time_utc] = SYSUTCDATETIME(), 
				[disk_volume] = left(s.disk_volume, len(s.disk_volume)-1),
				[read_latency_ms] = case when [num_of_reads] = 0 then 0
										else [io_stall_read_ms]/[num_of_reads]
										end,
				[write_latency_ms] = case when [num_of_writes] = 0 then 0
										else [io_stall_write_ms]/[num_of_writes]
										end,
				[read_bytes_per_second] = [num_of_bytes_read]/[time_sample_sec],
				[written_bytes_per_second] = [num_of_bytes_written]/[time_sample_sec]
		into #volume_stats
		from stats s;

		if @verbose > 0
			print @_tab+'Populate dbo.performance_counters with Disk Metrics..';
		;with cte_unpvt as 
		(
			select *
			from (
				select	[disk_volume], 
						[read_latency_sec] = convert(numeric(20,6),read_latency_ms/1000.0),
						[write_latency_sec] = convert(numeric(20,6),write_latency_ms/1000.0), 
						[read_bytes_per_sec] = convert(numeric(20,6),read_bytes_per_second),
						[written_bytes_per_sec] = convert(numeric(20,6),written_bytes_per_second)
				from #volume_stats
			) vs
			unpivot (
				value for counter in ([read_latency_sec], [write_latency_sec], [read_bytes_per_sec], [written_bytes_per_sec])
			) as unpvt
		)
		insert dbo.performance_counters
		(collection_time_utc, host_name, object, counter, value, instance)
		select	[collection_time_utc] = SYSUTCDATETIME(),	[host_name] = @_host_name,
				[object] = 'logicaldisk',
				[counter] = case when unpvt.counter = 'read_latency_sec' then 'avg. disk sec/read'
								when unpvt.counter = 'write_latency_sec' then 'avg. disk sec/write'
								when unpvt.counter = 'read_bytes_per_sec' then 'disk read bytes/sec'
								when unpvt.counter = 'written_bytes_per_sec' then 'disk write bytes/sec'
								else unpvt.counter
								end,
				[value] = unpvt.value,
				[instance] = [disk_volume]
		from cte_unpvt unpvt;

	end

end
GO
