USE DBA
GO

CREATE OR ALTER procedure dbo.usp_compute_LAMA_targets
		@days_for_analysis int = 30,
		@os_cpu_pntile_threshold decimal(18,4) = 99.3,
		@sql_cpu_pntile_threshold decimal(18,4) = 99.3,
		@available_memory_pntile_threshold decimal(18,4) = 99.3,
		@disk_latency_pntile_threshold decimal(18,4) = 99.3,
		@os_cpu_pcnt_threshold decimal(18,2) = 65.00,
		@sql_cpu_pcnt_threshold decimal(18,2) = 50.00,
		@available_memory_pcnt_threshold decimal(20,2) = 40.00,
		@sql_memory_pcnt_threshold decimal(20,2) = 50.00,
		@drop_create_staging_tables bit = 0,
		@filter_server varchar(125) = null,
		@verbose tinyint = 2
AS
BEGIN
/*	Purpose: Analyze the past core metrics history and determine the server that need Memory/CPU re-evaulation
	Modifications: 2024-Nov-12 - Ajay - Initial Draft

	exec dbo.usp_compute_LAMA_targets
			@verbose = 2, 
			@days_for_analysis = 15,
			--@filter_server = 'SqlPractice',
			@drop_create_staging_tables = 0;

*/
	set nocount on;
	set xact_abort on;

	if @verbose > 0
		print 'Inside procedure dbo.usp_compute_LAMA_targets.';

	-- declare variables
	declare @_sql nvarchar(max);
	declare @_params nvarchar(max);
	declare @_start_time datetime2 = sysdatetime();
	declare @_tab nchar(1) = '  ';
	declare @_crlf nchar(2) = nchar(10);

	-- declare cursor variables
	declare @l_data_points bigint;
	declare @l_collection_time	datetime2;
	declare @l_days_total int;
	declare @c_srv_name	varchar(255);
	declare @l_os_cpu_pntile decimal(18,2);
	declare @l_sql_cpu_pntile decimal(18,2);
	declare @l_available_ram_pntile decimal(18,2);
	declare @l_sql_ram_pntile decimal(18,2);
	declare @l_os_cpu	decimal(18,2);
	declare @l_sql_cpu	decimal(18,2);
	declare @l_cpu_count int;
	declare @l_max_server_memory_mb int;
	declare @l_box_ram_gb decimal(18,2);
	declare @l_available_ram_gb numeric(18,2);
	declare @l_sql_ram_gb numeric(18,2);
	declare @l_sql_ram_usage_pcnt numeric(18,2);
	declare @l_available_ram_pcnt numeric(18,2);
	declare @l_memory_consumers	int;
	declare @l_memory_grants_pending	int;
	declare @l_total_server_memory_gb	numeric(18,2);
	declare @l_target_server_memory_gb	numeric(18,2);
	declare @l_page_life_expectancy	int;
	declare @l_avg_disk_latency_ms	decimal(18,2);
	declare @l_avg_disk_latency_ms_pntile decimal(18,2);

	-- declare derived variables
	declare @d_memory_action_needed varchar(10);
	declare @d_memory_action varchar(125);
	declare @d_memory_comment nvarchar(2000);
	declare @d_additional_ram_gb int;
	declare @d_new_total_ram_gb int;
	declare @d_additional_sql_ram_gb int;
	declare @d_cpu_action_needed varchar(10);
	declare @d_cpu_action varchar(125);
	declare @d_additional_cpu_cores int;
	declare @d_new_total_cpu_cores int;
	declare @d_used_cpu_cores int;

	-- if drop_create is true, then drop objects
	if @drop_create_staging_tables = 1
	begin
		print '@drop_create_staging_tables is enabled.'

		if OBJECT_ID('dbo.lama_computed_metrics') is not null
		begin
			set @_sql = N'drop table dbo.lama_computed_metrics;';
			print @_sql;
			exec (@_sql);
		end
	end

	-- check if tables exists
	if OBJECT_ID('tempdb..#compute_LAMA_targets_RAW') is not null
		drop table #compute_LAMA_targets_RAW;
	create table #compute_LAMA_targets_RAW
	(
		[collection_time]	datetime2,
		[srv_name]	varchar(255),
		[os_cpu]	decimal(18,2),
		[sql_cpu]	decimal(18,2),
		[cpu_count] int,
		[max_server_memory_mb] int,
		[box_ram_gb] decimal(18,2),
		[available_ram_gb] numeric(18,2),
		[sql_ram_gb] numeric(18,2),
		[sql_ram_usage_pcnt] numeric(18,2),
		[available_ram_pcnt] numeric(18,2),
		[memory_consumers]	int,
		[memory_grants_pending]	int,
		[total_server_memory_gb]	numeric(18,2),
		[target_server_memory_gb]	numeric(18,2),
		[page_life_expectancy]	int,
		[avg_disk_latency_ms]	int,

		index ci_compute_LAMA_targets_RAW clustered ([srv_name], [collection_time])
	);

	-- check if tables exists
	if OBJECT_ID('dbo.lama_computed_metrics') is null
	begin
		print 'create table dbo.lama_computed_metrics.';
		-- drop table dbo.lama_computed_metrics
		CREATE TABLE [dbo].[lama_computed_metrics]
		(
			[data_points] [bigint] NULL,
			[collection_time] [datetime2](7) NULL,
			[days_total] [int] NULL,
			[srv_name] [varchar](255) NULL,
			[memory_action_needed] [varchar](10) NULL,
			[memory_action] [varchar](125) NULL,
			[cpu_action_needed] [varchar](10) NULL,
			[cpu_action] [varchar](125) NULL,
			[additional_ram_gb] [int] NULL,
			[new_total_ram_gb] [int] NULL,
			[additional_sql_ram_gb] [int] NULL,
			[box_ram_gb] [decimal](18, 2) NULL,
			[available_ram_gb] [numeric](18, 2) NULL,
			[sql_ram_gb] [numeric](18, 2) NULL,
			[available_memory_pcnt_threshold] [decimal](20, 2) NULL,
			[available_ram_pntile_pcnt] [decimal](18, 2) NULL,
			[available_ram_pcnt] [numeric](18, 2) NULL,
			[sql_memory_pcnt_threshold] [decimal](20, 2) NULL,
			[sql_ram_pntile] [decimal](18, 2) NULL,
			[sql_ram_usage_pcnt] [numeric](18, 2) NULL,
			[max_server_memory_mb] int null,
			[memory_consumers] [int] NULL,
			[memory_grants_pending] [int] NULL,
			[total_server_memory_gb] [numeric](18, 2) NULL,
			[target_server_memory_gb] [numeric](18, 2) NULL,
			[page_life_expectancy] [int] NULL,
			[avg_disk_latency_ms] [decimal](18, 2) NULL,
			[avg_disk_latency_ms_pntile] [decimal](18, 2) NULL,
			[additional_cpu_cores] [int] NULL,
			[new_total_cpu_cores] [int] NULL,
			[cpu_count] [int] NULL,
			[os_cpu_pntile] [decimal](18, 2) NULL,
			[os_cpu] [decimal](18, 2) NULL,
			[sql_cpu_pntile] [decimal](18, 2) NULL,
			[sql_cpu] [decimal](18, 2) NULL,
			[days_for_analysis] [int] NULL,
			[os_cpu_pntile_threshold] [decimal](18, 4) NULL,
			[sql_cpu_pntile_threshold] [decimal](18, 4) NULL,
			[available_memory_pntile_threshold] [decimal](18, 4) NULL,
			[disk_latency_pntile_threshold] [decimal](18, 4) NULL,
			[os_cpu_pcnt_threshold] [decimal](18, 2) NULL,
			[sql_cpu_pcnt_threshold] [decimal](18, 2) NULL,

			index ci_lama_computed_metrics clustered ([srv_name])
		);
	end

	-- trucate table if exists
	if exists (select * from dbo.lama_computed_metrics) and @filter_server is null
	begin
		if @verbose > 0
			print 'truncate table dbo.lama_computed_metrics.'
		truncate table dbo.lama_computed_metrics;
	end

	-- populate table with all servers
	insert #compute_LAMA_targets_RAW
	(collection_time, srv_name, os_cpu, sql_cpu, cpu_count, max_server_memory_mb, [available_ram_gb], [box_ram_gb], [sql_ram_gb], [sql_ram_usage_pcnt], 
		[available_ram_pcnt], memory_consumers, memory_grants_pending, total_server_memory_gb, target_server_memory_gb, 
		page_life_expectancy, avg_disk_latency_ms)
	select vih.collection_time, vih.srv_name, vih.os_cpu, vih.sql_cpu, asi.cpu_count, asi.max_server_memory_mb, 
			[available_ram_gb] = convert(numeric(20,2),vih.available_physical_memory_kb/(1024.0*1024.0)), 
			[box_ram_gb] = ceiling(asi.total_physical_memory_kb/(1024.0*1024.0)),
			[sql_ram_gb] = ceiling(vih.physical_memory_in_use_kb/(1024.0*1024.0)),
			[sql_ram_usage_pcnt] = convert(numeric(20,2),(vih.physical_memory_in_use_kb*100.0/asi.total_physical_memory_kb)),
			[available_ram_pcnt] = convert(numeric(20,2),(vih.available_physical_memory_kb*100.0/asi.total_physical_memory_kb)),
			vih.memory_consumers, vih.memory_grants_pending,
			[total_server_memory_gb] = ceiling(vih.total_server_memory_kb/(1024.0*1024.0)),
			[target_server_memory_gb] = ceiling(vih.target_server_memory_kb/(1024.0*1024.0)),
			vih.page_life_expectancy, vih.avg_disk_latency_ms
	from dbo.all_server_volatile_info_history vih
	join dbo.vw_all_server_info asi on asi.srv_name = vih.srv_name
	where 1=1
	and vih.collection_time >= dateadd(day,-@days_for_analysis,getdate())
	and (@filter_server is null or vih.srv_name = @filter_server);

	-- get list of servers to process
	if OBJECT_ID('tempdb..#servers') is not null
		drop table #servers;
	select srv_name into #servers 
	from #compute_LAMA_targets_RAW
	where 1=1
	and (@filter_server is null or srv_name = @filter_server)
	group by srv_name;

	declare cur_servers cursor local forward_only for
			select srv_name from #servers;

	open cur_servers;
	fetch next from cur_servers into @c_srv_name;

	while @@FETCH_STATUS = 0
	begin
		print 'Working on '+quotename(@c_srv_name)+'..';

		set @l_data_points = NULL;
		set @l_collection_time = NULL;
		set @l_days_total = NULL;
		set @l_os_cpu_pntile = NULL;
		set @l_sql_cpu_pntile = NULL;
		set @l_available_ram_pntile = NULL;
		set @l_sql_ram_pntile = NULL;
		set @l_os_cpu = NULL;
		set @l_sql_cpu = NULL;
		set @l_cpu_count = NULL;
		set @l_max_server_memory_mb = NULL;
		set @l_box_ram_gb = NULL;
		set @l_available_ram_gb = NULL;
		set @l_sql_ram_gb = NULL;
		set @l_sql_ram_usage_pcnt = NULL;
		set @l_available_ram_pcnt = NULL;
		set @l_memory_consumers = NULL;
		set @l_memory_grants_pending = NULL;
		set @l_total_server_memory_gb = NULL;
		set @l_target_server_memory_gb = NULL;
		set @l_page_life_expectancy = NULL;
		set @l_avg_disk_latency_ms = NULL;
		set @l_avg_disk_latency_ms_pntile = NULL;
		set @d_memory_action_needed = NULL;
		set @d_memory_action = NULL;
		set @d_memory_comment = NULL;
		set @d_additional_ram_gb = NULL;
		set @d_new_total_ram_gb = NULL;
		set @d_additional_sql_ram_gb = NULL;
		set @d_cpu_action_needed = NULL;
		set @d_cpu_action = NULL;
		set @d_additional_cpu_cores = NULL;
		set @d_used_cpu_cores = NULL;

		-- get compute direct data
		;with cte_compute_LAMA_targets_pntiles as (
			select	top 1
					i.srv_name,
					[os_cpu_pntile] = PERCENTILE_CONT(@os_cpu_pntile_threshold*0.01) WITHIN GROUP (ORDER BY os_cpu) OVER (),
					[sql_cpu_pntile] = PERCENTILE_CONT(@sql_cpu_pntile_threshold*0.01) WITHIN GROUP (ORDER BY sql_cpu) OVER (),
					[available_ram_pntile] = PERCENTILE_CONT(@available_memory_pntile_threshold*0.01) WITHIN GROUP (ORDER BY available_ram_pcnt desc) OVER (),
					[sql_ram_pntile] = PERCENTILE_CONT(@available_memory_pntile_threshold*0.01) WITHIN GROUP (ORDER BY sql_ram_usage_pcnt) OVER (),
					[disk_latency_pntile] = PERCENTILE_CONT(@disk_latency_pntile_threshold*0.01) WITHIN GROUP (ORDER BY avg_disk_latency_ms) OVER ()
			from #compute_LAMA_targets_RAW i
			where i.srv_name = @c_srv_name
		)
		select	@l_data_points = count(*), 
				@l_collection_time = max(collection_time),
				@l_days_total = datediff(day, min(collection_time), max(collection_time)),
				@l_os_cpu = max(os_cpu),
				@l_os_cpu_pntile = max( [os_cpu_pntile] ),
				@l_sql_cpu = max(sql_cpu),
				@l_sql_cpu_pntile = max( [sql_cpu_pntile] ),
				@l_available_ram_pntile = min([available_ram_pntile]),
				@l_sql_ram_pntile = max([sql_ram_pntile]),
				@l_cpu_count = max(cpu_count),
				@l_max_server_memory_mb = max(max_server_memory_mb),
				@l_box_ram_gb = max(box_ram_gb),
				@l_available_ram_gb = min(available_ram_gb),
				@l_available_ram_pcnt = min(available_ram_pcnt),
				@l_sql_ram_gb = max(sql_ram_gb), 
				@l_sql_ram_usage_pcnt = max(sql_ram_usage_pcnt),
				@l_memory_consumers = max(memory_consumers), 
				@l_memory_grants_pending = max(memory_grants_pending),
				@l_total_server_memory_gb = max(total_server_memory_gb), 
				@l_target_server_memory_gb = max(target_server_memory_gb), 
				@l_page_life_expectancy = min(page_life_expectancy), 
				@l_avg_disk_latency_ms = max(avg_disk_latency_ms),
				@l_avg_disk_latency_ms_pntile = max([disk_latency_pntile])
				--p_days_for_analysis = @days_for_analysis,
				--p_os_cpu_pntile_threshold = @os_cpu_pntile_threshold,
				--p_sql_cpu_pntile_threshold = @sql_cpu_pntile_threshold,
				--p_os_cpu_pcnt_threshold = @os_cpu_pcnt_threshold,
				--p_sql_cpu_pcnt_threshold = @sql_cpu_pcnt_threshold,
				--p_available_memory_pcnt_threshold = @available_memory_pcnt_threshold
		from #compute_LAMA_targets_RAW r
		left join cte_compute_LAMA_targets_pntiles t_pntile on t_pntile.srv_name = r.srv_name
		where r.srv_name = @c_srv_name;

		-- compute derived data for Memory
		if 'Compute Memory' = 'Compute Memory'
		begin
			set @d_memory_action_needed = case	when @l_available_ram_pntile < @available_memory_pcnt_threshold
												then 'yes'
												when @l_available_ram_pcnt < @available_memory_pcnt_threshold
												then 'debug'
												else 'no'
												end;

			set @d_memory_action = case when @d_memory_action_needed = 'no' then 'no action'
										when @l_memory_grants_pending > 0 then 'add memory - memory grants pending'
										when @l_avg_disk_latency_ms_pntile >= 15 then 'add memory - disk latency'
										-- when max sql usage > threshold
										when @l_sql_ram_usage_pcnt > @sql_memory_pcnt_threshold then 'reduce - sql ram'
										-- when sql ram usage < threshold & still available memory is low
										when @l_available_ram_pntile < @available_memory_pcnt_threshold then 'add memory - server team action'
										when @l_available_ram_pcnt < @available_memory_pcnt_threshold then 'debug os processes - server team action' 
										else 'unknown'
										end

			if (@d_memory_action_needed = 'no' or @d_memory_action = 'add memory - server team action')
			begin
				if @verbose > 0
					print @_tab+'no ram action from DBA side';
			end
			else
			begin
				if @verbose > 0
					print @_tab+'calculate additional ram for sql..';

				if @d_memory_action in ('add memory - disk latency')
				begin
					set @d_additional_ram_gb = case when @l_avg_disk_latency_ms >= 50 then @l_box_ram_gb
													when @l_avg_disk_latency_ms >= 30 then @l_box_ram_gb * 0.7
													when @l_avg_disk_latency_ms >= 15 then @l_box_ram_gb * 0.5
													else 0
													end
					set @d_additional_sql_ram_gb = @l_box_ram_gb * 0.65
					set @d_new_total_ram_gb = @l_box_ram_gb + @d_additional_ram_gb
				end

				if @d_memory_action in ('add memory - memory grants pending')
				begin
					set @d_additional_ram_gb = @l_box_ram_gb * 0.5
					set @d_additional_sql_ram_gb = @l_box_ram_gb * 0.3
					set @d_new_total_ram_gb = @l_box_ram_gb + @d_additional_ram_gb
				end

				if @d_memory_action in ('reduce - sql ram')
				begin
					set @d_additional_ram_gb = 0
					set @d_additional_sql_ram_gb = (@l_sql_ram_gb - (@sql_memory_pcnt_threshold*@l_box_ram_gb*1.0)/100.0) -- extra ram over threshold %
					set @d_new_total_ram_gb = 0
				end

			end
		end

		-- compute derived data for Cpu
		if 'Compute Cpu' = 'Compute Cpu'
		begin
			set @d_cpu_action_needed = case	when @l_os_cpu_pntile >= @os_cpu_pcnt_threshold
											then 'yes'
											when @l_os_cpu > @os_cpu_pcnt_threshold
											then 'debug'
											else 'no'
											end;

			set @d_cpu_action = case when @d_cpu_action_needed = 'no' then 'no action'
										-- when pntile sql cpu usage > threshold
										when @l_sql_cpu_pntile >= @sql_cpu_pcnt_threshold then 'add cpu - sql cpu high'
										-- when max sql cpu usage > threshold
										when @l_sql_cpu >= @sql_cpu_pcnt_threshold then 'debug sql cpu - once in a while peak usage'
										when @l_sql_cpu < @sql_cpu_pcnt_threshold then 'add cpu - server team action' 
										else 'unknown'
										end

			if (@d_cpu_action_needed = 'no' or @d_cpu_action = 'add cpu - server team action')
			begin
				if @verbose > 0
					print @_tab+'no cpu action from DBA side';
			end
			else
			begin
				if @verbose > 0
					print @_tab+'calculate additional cpu..';

				if @d_cpu_action in ('add cpu - sql cpu high','debug sql cpu - once in a while peak usage')
				begin
					set @d_used_cpu_cores = (@l_os_cpu*@l_cpu_count)/100.0;					
					set @d_new_total_cpu_cores = ((@d_used_cpu_cores * 100.0) / @os_cpu_pcnt_threshold) + 2; -- add 2 extra cpus
					set @d_additional_cpu_cores = @d_new_total_cpu_cores - @l_cpu_count;
				end
			end
		end

		if @filter_server is null
		begin
			insert dbo.lama_computed_metrics
			(data_points, collection_time, days_total, srv_name, memory_action_needed, memory_action, cpu_action_needed, cpu_action, additional_ram_gb, new_total_ram_gb, additional_sql_ram_gb, box_ram_gb, available_ram_gb, sql_ram_gb, available_memory_pcnt_threshold, available_ram_pntile_pcnt, available_ram_pcnt, sql_memory_pcnt_threshold, sql_ram_pntile, sql_ram_usage_pcnt, max_server_memory_mb, memory_consumers, memory_grants_pending, total_server_memory_gb, target_server_memory_gb, page_life_expectancy, avg_disk_latency_ms, avg_disk_latency_ms_pntile, additional_cpu_cores, new_total_cpu_cores, cpu_count, os_cpu_pntile, os_cpu, sql_cpu_pntile, sql_cpu, days_for_analysis, os_cpu_pntile_threshold, sql_cpu_pntile_threshold, available_memory_pntile_threshold, disk_latency_pntile_threshold, os_cpu_pcnt_threshold, sql_cpu_pcnt_threshold)
			select	[@l_data_points] = @l_data_points,
					[@l_collection_time] = @l_collection_time,
					[@l_days_total] = @l_days_total,
					[@c_srv_name] = @c_srv_name,

					-- Begin: Action Section
						[@d_memory_action_needed] = @d_memory_action_needed,
						[@d_memory_action] = @d_memory_action,
						[@d_cpu_action_needed] = @d_cpu_action_needed,
						[@d_cpu_action] = @d_cpu_action,
					-- End: Action Section

					-- Begin: Memory Section
						[@d_additional_ram_gb] = @d_additional_ram_gb,
						[@d_new_total_ram_gb] = @d_new_total_ram_gb,
						[@d_additional_sql_ram_gb] = @d_additional_sql_ram_gb,

						[@l_box_ram_gb] = @l_box_ram_gb,
						[@l_available_ram_gb] = @l_available_ram_gb,
						[@l_sql_ram_gb] = @l_sql_ram_gb,				

						[@available_memory_pcnt_threshold] = @available_memory_pcnt_threshold,
						[@l_available_ram_pntile_pcnt] = @l_available_ram_pntile,
						[@l_available_ram_pcnt] = @l_available_ram_pcnt,

						[@sql_memory_pcnt_threshold] = @sql_memory_pcnt_threshold,
						[@l_sql_ram_pntile] = @l_sql_ram_pntile,
						[@l_sql_ram_usage_pcnt] = @l_sql_ram_usage_pcnt,

						[@l_max_server_memory_mb] = @l_max_server_memory_mb,
						[@l_memory_consumers] = @l_memory_consumers,
						[@l_memory_grants_pending] = @l_memory_grants_pending,
						[@l_total_server_memory_gb] = @l_total_server_memory_gb,
						[@l_target_server_memory_gb] = @l_target_server_memory_gb,
						[@l_page_life_expectancy] = @l_page_life_expectancy,
						[@l_avg_disk_latency_ms] = @l_avg_disk_latency_ms,
						[@l_avg_disk_latency_ms_pntile] = @l_avg_disk_latency_ms_pntile,
					-- End: Memory Section

					-- Begin: Cpu Section
						[@d_additional_cpu_cores] = @d_additional_cpu_cores,
						[@d_new_total_cpu_cores] = @d_new_total_cpu_cores,

						[@l_cpu_count] = @l_cpu_count,
						[@l_os_cpu_pntile] = @l_os_cpu_pntile,
						[@l_os_cpu] = @l_os_cpu,

						[@l_sql_cpu_pntile] = @l_sql_cpu_pntile,
						[@l_sql_cpu] = @l_sql_cpu,						
					-- End: Cpu Section
					
					-- Begin: Parameters Section
						[@days_for_analysis] = @days_for_analysis,
						[@os_cpu_pntile_threshold] = @os_cpu_pntile_threshold,
						[@sql_cpu_pntile_threshold] = @sql_cpu_pntile_threshold,
						[@available_memory_pntile_threshold] = @available_memory_pntile_threshold,
						[@disk_latency_pntile_threshold] = @disk_latency_pntile_threshold,
						[@os_cpu_pcnt_threshold] = @os_cpu_pcnt_threshold,
						[@sql_cpu_pcnt_threshold] = @sql_cpu_pcnt_threshold
					-- End: Parameters Section
		end
		else
		begin
			-- return the select
			select	[@l_data_points] = @l_data_points,
					[@l_collection_time] = @l_collection_time,
					[@l_days_total] = @l_days_total,
					[@c_srv_name] = @c_srv_name,

					-- Begin: Action Section
						[@d_memory_action_needed] = @d_memory_action_needed,
						[@d_memory_action] = @d_memory_action,
						[@d_cpu_action_needed] = @d_cpu_action_needed,
						[@d_cpu_action] = @d_cpu_action,
					-- End: Action Section

					-- Begin: Memory Section
						[@d_additional_ram_gb] = @d_additional_ram_gb,
						[@d_new_total_ram_gb] = @d_new_total_ram_gb,
						[@d_additional_sql_ram_gb] = @d_additional_sql_ram_gb,

						[@l_box_ram_gb] = @l_box_ram_gb,
						[@l_available_ram_gb] = @l_available_ram_gb,
						[@l_sql_ram_gb] = @l_sql_ram_gb,				

						[@available_memory_pcnt_threshold] = @available_memory_pcnt_threshold,
						[@l_available_ram_pntile_pcnt] = @l_available_ram_pntile,
						[@l_available_ram_pcnt] = @l_available_ram_pcnt,

						[@sql_memory_pcnt_threshold] = @sql_memory_pcnt_threshold,
						[@l_sql_ram_pntile] = @l_sql_ram_pntile,
						[@l_sql_ram_usage_pcnt] = @l_sql_ram_usage_pcnt,

						[@l_max_server_memory_mb] = @l_max_server_memory_mb,
						[@l_memory_consumers] = @l_memory_consumers,
						[@l_memory_grants_pending] = @l_memory_grants_pending,
						[@l_total_server_memory_gb] = @l_total_server_memory_gb,
						[@l_target_server_memory_gb] = @l_target_server_memory_gb,
						[@l_page_life_expectancy] = @l_page_life_expectancy,
						[@l_avg_disk_latency_ms] = @l_avg_disk_latency_ms,
						[@l_avg_disk_latency_ms_pntile] = @l_avg_disk_latency_ms_pntile,
					-- End: Memory Section

					-- Begin: Cpu Section
						[@d_additional_cpu_cores] = @d_additional_cpu_cores,
						[@d_new_total_cpu_cores] = @d_new_total_cpu_cores,

						[@l_cpu_count] = @l_cpu_count,
						[@l_os_cpu_pntile] = @l_os_cpu_pntile,
						[@l_os_cpu] = @l_os_cpu,

						[@l_sql_cpu_pntile] = @l_sql_cpu_pntile,
						[@l_sql_cpu] = @l_sql_cpu,						
					-- End: Cpu Section
					
					-- Begin: Parameters Section
						[@days_for_analysis] = @days_for_analysis,
						[@os_cpu_pntile_threshold] = @os_cpu_pntile_threshold,
						[@sql_cpu_pntile_threshold] = @sql_cpu_pntile_threshold,
						[@available_memory_pntile_threshold] = @available_memory_pntile_threshold,
						[@disk_latency_pntile_threshold] = @disk_latency_pntile_threshold,
						[@os_cpu_pcnt_threshold] = @os_cpu_pcnt_threshold,
						[@sql_cpu_pcnt_threshold] = @sql_cpu_pcnt_threshold
					-- End: Parameters Section
		end

		fetch next from cur_servers into @c_srv_name;
	end

	close cur_servers;
	deallocate cur_servers;

	if @verbose > 0 and @filter_server is null
		select * from dbo.lama_computed_metrics lcm;

	-- Return config changes history if not grafana login connection
	if SUSER_NAME() <> 'grafana'
	begin
		;with t_history as (
			select	collection_time, srv_name, 
					total_physical_memory_kb, prev__total_physical_memory_kb = lag(total_physical_memory_kb) over (partition by srv_name order by collection_time),
					cpu_count, prev__cpu_count = lag(cpu_count) over (partition by srv_name order by collection_time),
					scheduler_count, prev__scheduler_count = lag(scheduler_count) over (partition by srv_name order by collection_time),
					max_server_memory_mb, prev__max_server_memory_mb = lag(max_server_memory_mb) over (partition by srv_name order by collection_time)
			from dbo.all_server_stable_info_history ssi
			where 1=1
			and ssi.collection_time >= dateadd(day,-@days_for_analysis,getdate())
			and (@filter_server is null or ssi.srv_name = @filter_server)
		)
		,t_history_filtered_for_change as (
			select RunningQuery = 'Cpu/Ram/Config-Change-History', *
			from t_history h
			where 1=1
			and (	h.cpu_count <> h.prev__cpu_count
				or	h.total_physical_memory_kb <> h.prev__total_physical_memory_kb
				or	h.scheduler_count <> h.prev__scheduler_count
				or	h.max_server_memory_mb <> h.prev__max_server_memory_mb
				)
		)
		select	rq.RunningQuery, collection_time, srv_name, total_physical_memory_kb, prev__total_physical_memory_kb,
				cpu_count, prev__cpu_count, scheduler_count, prev__scheduler_count, 
				max_server_memory_mb, prev__max_server_memory_mb
		from t_history_filtered_for_change c
		full outer join (select RunningQuery = 'Cpu/Ram/Config-Change-History') rq
			on 1=1
	end

END
GO

exec dbo.usp_compute_LAMA_targets 
		@verbose = 2, 
		@days_for_analysis = 15,
		--@filter_server = 'SqlPractice',
		@drop_create_staging_tables = 0
go


/*
select *
from DBA_Admin.dbo.lama_computed_metrics with (nolock)
where memory_action_needed <> 'no' or cpu_action_needed <> 'no'

*/