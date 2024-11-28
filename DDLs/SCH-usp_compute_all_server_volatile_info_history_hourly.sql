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

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_compute_all_server_volatile_info_history_hourly')
    EXEC ('CREATE PROC dbo.usp_compute_all_server_volatile_info_history_hourly AS SELECT ''stub version, to be replaced''')
GO 

alter procedure dbo.usp_compute_all_server_volatile_info_history_hourly
		@days_per_processing_batch int = 1,
		@verbose tinyint = 2
AS
BEGIN
/*	Purpose: Optimize table dbo.all_server_volatile_info_history
			Aggregate data from dbo.all_server_volatile_info_history, and save it into hourly trend in table dbo.all_server_volatile_info_history_hourly
	
	Modifications: 2024-Nov-28 - Ajay - Initial Draft

	exec dbo.usp_compute_all_server_volatile_info_history_hourly @days_per_processing_batch = 2, @verbose = 1;

	Related:
	exec sp_BlitzIndex @TableName = 'all_server_volatile_info_history_hourly' ,@ShowColumnstoreOnly = 1;
	select * from dbo.all_server_volatile_info_history_hourly

*/
	set nocount on;
	set xact_abort on;

	if @verbose > 0
		print 'Inside procedure dbo.usp_compute_all_server_volatile_info_history_hourly.';

	-- declare variables
	declare @_sql nvarchar(max);
	declare @_params nvarchar(max);
	declare @_start_time datetime2 = sysdatetime();
	declare @_tab nchar(1) = '  ';
	declare @_crlf nchar(2) = nchar(10);

	declare @_start_date_of_current_month datetime2;
	set @_start_date_of_current_month = datefromparts(year(getdate()),MONTH(getdate()),'01');

	declare @_collection_time_latest datetime2;
	declare @_new_records_start_time datetime2;
	declare @_new_records_start_date datetime2;	
	declare @_new_records_end_time datetime2;
	declare @_looper_start_time datetime2;
	declare @_looper_end_time datetime2;	

	-- When was last data collection?
	select @_collection_time_latest = coalesce(max(collection_time),'1989-08-17')
	from dbo.all_server_volatile_info_history_hourly hh;

	-- New data since last data collection?
	select	@_new_records_start_time = min(collection_time),
			@_new_records_start_date = cast(min(collection_time) as date),
			@_new_records_end_time = max(collection_time)
	from dbo.all_server_volatile_info_history vih
	where vih.collection_time > @_collection_time_latest
	and vih.collection_time < @_start_date_of_current_month;

	-- Check if new records are there to process
	if cast(@_collection_time_latest as date) >= cast(@_new_records_end_time as date)
		print 'No new records found to process.';
	else
	BEGIN
		print 'New entries found to process.';

		-- Initialize loop filter variables
		set @_looper_start_time = @_new_records_start_date;
		set @_looper_end_time = dateadd(day,@days_per_processing_batch,@_looper_start_time);

		if @verbose > 0
		begin
			select	[@_collection_time_latest] = @_collection_time_latest, 
					[@_new_records_start_time] = @_new_records_start_time, 
					[@_new_records_end_time] = @_new_records_end_time,
					[@_looper_start_time] = @_looper_start_time,
					[@_looper_end_time] = @_looper_end_time
					;
		end

		if object_id('tempdb..#all_server_volatile_info_history_hourly') is not null
			drop table #all_server_volatile_info_history_hourly;
		select * into #all_server_volatile_info_history_hourly 
		from dbo.all_server_volatile_info_history_hourly 
		where 1=1;

		if @verbose > 0
			print 'Start processing data from dbo.all_server_volatile_info_history in batch of '+convert(varchar,@days_per_processing_batch)+' days..';
		while @_looper_start_time < @_start_date_of_current_month
		BEGIN

			if @verbose >= 2
			begin
				select	[@_looper_start_time] = @_looper_start_time, 
						[@_looper_end_time] = case when @_looper_end_time > @_start_date_of_current_month then @_start_date_of_current_month else @_looper_end_time end,
						[filter] = '(vih.collection_time >= @_looper_start_time) and (vih.collection_time < @_looper_end_time)';
			end

			if @verbose > 0
				print 'Working on @_looper_start_time = '+convert(varchar,@_looper_start_time,120)+'..';
			insert into #all_server_volatile_info_history_hourly
			(	collection_time, srv_name, 
				os_cpu__p50, os_cpu__p95, os_cpu__p98, os_cpu__p99, os_cpu__p993, 
				sql_cpu__p50, sql_cpu__p95, sql_cpu__p98, sql_cpu__p99, sql_cpu__p993, 
				available_physical_memory_kb__p50, available_physical_memory_kb__p95, available_physical_memory_kb__p98, available_physical_memory_kb__p99, available_physical_memory_kb__p993, 
				physical_memory_in_use_kb__p50, physical_memory_in_use_kb__p95, physical_memory_in_use_kb__p98, physical_memory_in_use_kb__p99, physical_memory_in_use_kb__p993, memory_grants_pending__p50, 
				memory_grants_pending__p95, memory_grants_pending__p98, memory_grants_pending__p99, memory_grants_pending__p993, 
				connection_count__p50, connection_count__p95, connection_count__p98, connection_count__p99, connection_count__p993, 
				active_requests_count__p50, active_requests_count__p95, active_requests_count__p98, active_requests_count__p99, active_requests_count__p993, 
				waits_per_core_per_minute__p50, waits_per_core_per_minute__p95, waits_per_core_per_minute__p98, waits_per_core_per_minute__p99, waits_per_core_per_minute__p993, 
				avg_disk_latency_ms__p50, avg_disk_latency_ms__p95, avg_disk_latency_ms__p98, avg_disk_latency_ms__p99, avg_disk_latency_ms__p993, 
				page_life_expectancy__p50, page_life_expectancy__p95, page_life_expectancy__p99, page_life_expectancy__p98, page_life_expectancy__p993
			)
			select	DISTINCT
					collection_time =  DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0),
					srv_name, 
					os_cpu__p50 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(50*0.01) WITHIN GROUP (ORDER BY os_cpu) 
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					os_cpu__p95 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(95*0.01) WITHIN GROUP (ORDER BY os_cpu) 
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					os_cpu__p98 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(98*0.01) WITHIN GROUP (ORDER BY os_cpu) 
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					os_cpu__p99 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(99*0.01) WITHIN GROUP (ORDER BY os_cpu) 
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					os_cpu__p993 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(99.3*0.01) WITHIN GROUP (ORDER BY os_cpu) 
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					sql_cpu__p50 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(50*0.01) WITHIN GROUP (ORDER BY sql_cpu) 
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					sql_cpu__p95 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(95*0.01) WITHIN GROUP (ORDER BY sql_cpu) 
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					sql_cpu__p98 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(98*0.01) WITHIN GROUP (ORDER BY sql_cpu) 
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					sql_cpu__p99 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(99*0.01) WITHIN GROUP (ORDER BY sql_cpu) 
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					sql_cpu__p993 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(99.3*0.01) WITHIN GROUP (ORDER BY sql_cpu)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					available_physical_memory_kb__p50 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(50*0.01) WITHIN GROUP (ORDER BY available_physical_memory_kb desc)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					available_physical_memory_kb__p95 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(95*0.01) WITHIN GROUP (ORDER BY available_physical_memory_kb desc)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					available_physical_memory_kb__p98 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(98*0.01) WITHIN GROUP (ORDER BY available_physical_memory_kb desc)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					available_physical_memory_kb__p99 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(99*0.01) WITHIN GROUP (ORDER BY available_physical_memory_kb desc)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					available_physical_memory_kb__p993 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(99.3*0.01) WITHIN GROUP (ORDER BY available_physical_memory_kb desc)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					physical_memory_in_use_kb__p50 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(50*0.01) WITHIN GROUP (ORDER BY physical_memory_in_use_kb)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					physical_memory_in_use_kb__p95 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(95*0.01) WITHIN GROUP (ORDER BY physical_memory_in_use_kb)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					physical_memory_in_use_kb__p98 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(98*0.01) WITHIN GROUP (ORDER BY physical_memory_in_use_kb)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					physical_memory_in_use_kb__p99 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(99*0.01) WITHIN GROUP (ORDER BY physical_memory_in_use_kb)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					physical_memory_in_use_kb__p993 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(99.3*0.01) WITHIN GROUP (ORDER BY physical_memory_in_use_kb)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					memory_grants_pending__p50 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(50*0.01) WITHIN GROUP (ORDER BY memory_grants_pending)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					memory_grants_pending__p95 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(95*0.01) WITHIN GROUP (ORDER BY memory_grants_pending)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					memory_grants_pending__p98 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(98*0.01) WITHIN GROUP (ORDER BY memory_grants_pending)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					memory_grants_pending__p99 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(99*0.01) WITHIN GROUP (ORDER BY memory_grants_pending)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					memory_grants_pending__p993 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(99.3*0.01) WITHIN GROUP (ORDER BY memory_grants_pending)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					connection_count__p50 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(50*0.01) WITHIN GROUP (ORDER BY connection_count)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					connection_count__p95 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(95*0.01) WITHIN GROUP (ORDER BY connection_count)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					connection_count__p98 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(98*0.01) WITHIN GROUP (ORDER BY connection_count)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					connection_count__p99 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(99*0.01) WITHIN GROUP (ORDER BY connection_count)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					connection_count__p993 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(99.3*0.01) WITHIN GROUP (ORDER BY connection_count)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					active_requests_count__p50 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(50*0.01) WITHIN GROUP (ORDER BY active_requests_count)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					active_requests_count__p95 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(95*0.01) WITHIN GROUP (ORDER BY active_requests_count)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					active_requests_count__p98 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(98*0.01) WITHIN GROUP (ORDER BY active_requests_count)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					active_requests_count__p99 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(99*0.01) WITHIN GROUP (ORDER BY active_requests_count)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					active_requests_count__p993 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(99.3*0.01) WITHIN GROUP (ORDER BY active_requests_count)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					waits_per_core_per_minute__p50 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(50*0.01) WITHIN GROUP (ORDER BY waits_per_core_per_minute)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					waits_per_core_per_minute__p95 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(95*0.01) WITHIN GROUP (ORDER BY waits_per_core_per_minute)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					waits_per_core_per_minute__p98 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(98*0.01) WITHIN GROUP (ORDER BY waits_per_core_per_minute)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					waits_per_core_per_minute__p99 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(99*0.01) WITHIN GROUP (ORDER BY waits_per_core_per_minute)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					waits_per_core_per_minute__p993 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(99.3*0.01) WITHIN GROUP (ORDER BY waits_per_core_per_minute)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					avg_disk_latency_ms__p50 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(50*0.01) WITHIN GROUP (ORDER BY avg_disk_latency_ms)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					avg_disk_latency_ms__p95 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(95*0.01) WITHIN GROUP (ORDER BY avg_disk_latency_ms)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					avg_disk_latency_ms__p98 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(98*0.01) WITHIN GROUP (ORDER BY avg_disk_latency_ms)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					avg_disk_latency_ms__p99 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(99*0.01) WITHIN GROUP (ORDER BY avg_disk_latency_ms)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					avg_disk_latency_ms__p993 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(99.3*0.01) WITHIN GROUP (ORDER BY avg_disk_latency_ms)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					page_life_expectancy__p50 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(50*0.01) WITHIN GROUP (ORDER BY page_life_expectancy)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					page_life_expectancy__p95 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(95*0.01) WITHIN GROUP (ORDER BY page_life_expectancy)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					page_life_expectancy__p98 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(98*0.01) WITHIN GROUP (ORDER BY page_life_expectancy)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					page_life_expectancy__p99 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(99*0.01) WITHIN GROUP (ORDER BY page_life_expectancy)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name)),
					page_life_expectancy__p993 = CONVERT(NUMERIC(20,2),PERCENTILE_CONT(99.3*0.01) WITHIN GROUP (ORDER BY page_life_expectancy)  
											OVER (PARTITION BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), srv_name))
			from dbo.all_server_volatile_info_history vih
			where 1=1
			and vih.collection_time < @_start_date_of_current_month -- condition to avoid any issues
			and (	vih.collection_time >= @_looper_start_time
				and vih.collection_time < @_looper_end_time
				);

			-- Increment loop filter variables
			set	@_looper_start_time = @_looper_end_time;
			set @_looper_end_time = dateadd(day,@days_per_processing_batch,@_looper_start_time);
		END

		-- create clustered index on table to ORDER the data
		if @verbose > 0
			print 'create clustered index on temp table #all_server_volatile_info_history_hourly to ORDER the data..';
		create clustered index CCI_temp_all_server_volatile_info_history_hourly 
			on #all_server_volatile_info_history_hourly (collection_time, srv_name);

		if @verbose > 0
			print 'transfer data into main table dbo.all_server_volatile_info_history_hourly from temp table..';
		insert dbo.all_server_volatile_info_history_hourly
		(	collection_time, srv_name, 
			os_cpu__p50, os_cpu__p95, os_cpu__p98, os_cpu__p99, os_cpu__p993, 
			sql_cpu__p50, sql_cpu__p95, sql_cpu__p98, sql_cpu__p99, sql_cpu__p993, 
			available_physical_memory_kb__p50, available_physical_memory_kb__p95, available_physical_memory_kb__p98, available_physical_memory_kb__p99, available_physical_memory_kb__p993, 
			physical_memory_in_use_kb__p50, physical_memory_in_use_kb__p95, physical_memory_in_use_kb__p98, physical_memory_in_use_kb__p99, physical_memory_in_use_kb__p993, memory_grants_pending__p50, 
			memory_grants_pending__p95, memory_grants_pending__p98, memory_grants_pending__p99, memory_grants_pending__p993, 
			connection_count__p50, connection_count__p95, connection_count__p98, connection_count__p99, connection_count__p993, 
			active_requests_count__p50, active_requests_count__p95, active_requests_count__p98, active_requests_count__p99, active_requests_count__p993, 
			waits_per_core_per_minute__p50, waits_per_core_per_minute__p95, waits_per_core_per_minute__p98, waits_per_core_per_minute__p99, waits_per_core_per_minute__p993, 
			avg_disk_latency_ms__p50, avg_disk_latency_ms__p95, avg_disk_latency_ms__p98, avg_disk_latency_ms__p99, avg_disk_latency_ms__p993, 
			page_life_expectancy__p50, page_life_expectancy__p95, page_life_expectancy__p99, page_life_expectancy__p98, page_life_expectancy__p993
		)
		select	collection_time, srv_name, 
				os_cpu__p50, os_cpu__p95, os_cpu__p98, os_cpu__p99, os_cpu__p993, 
				sql_cpu__p50, sql_cpu__p95, sql_cpu__p98, sql_cpu__p99, sql_cpu__p993, 
				available_physical_memory_kb__p50, available_physical_memory_kb__p95, available_physical_memory_kb__p98, available_physical_memory_kb__p99, available_physical_memory_kb__p993, 
				physical_memory_in_use_kb__p50, physical_memory_in_use_kb__p95, physical_memory_in_use_kb__p98, physical_memory_in_use_kb__p99, physical_memory_in_use_kb__p993, memory_grants_pending__p50, 
				memory_grants_pending__p95, memory_grants_pending__p98, memory_grants_pending__p99, memory_grants_pending__p993, 
				connection_count__p50, connection_count__p95, connection_count__p98, connection_count__p99, connection_count__p993, 
				active_requests_count__p50, active_requests_count__p95, active_requests_count__p98, active_requests_count__p99, active_requests_count__p993, 
				waits_per_core_per_minute__p50, waits_per_core_per_minute__p95, waits_per_core_per_minute__p98, waits_per_core_per_minute__p99, waits_per_core_per_minute__p993, 
				avg_disk_latency_ms__p50, avg_disk_latency_ms__p95, avg_disk_latency_ms__p98, avg_disk_latency_ms__p99, avg_disk_latency_ms__p993, 
				page_life_expectancy__p50, page_life_expectancy__p95, page_life_expectancy__p99, page_life_expectancy__p98, page_life_expectancy__p993
		from #all_server_volatile_info_history_hourly;	
	END
END
GO

