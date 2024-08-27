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

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_GetAllServerDashboardMail')
    EXEC ('CREATE PROC dbo.usp_GetAllServerDashboardMail AS SELECT ''stub version, to be replaced''')
GO

ALTER PROCEDURE dbo.usp_GetAllServerDashboardMail
(	@send_mail bit = 1,
	@recipients varchar(500) = 'dba_team@gmail.com', /* Folks who receive the failure mail */
	@mail_subject varchar(500) = 'Monitoring - Live - All Servers', /* Subject of Failure Mail */
	@job_name varchar(255) = '(dba) Get-AllServerDashboardMail',
	@os_cpu_threshold decimal(20,2) = 70,
	@sql_cpu_threshold decimal(20,2) = 65,
	@blocked_counts_threshold int = 1,
	@blocked_duration_max_seconds_threshold bigint = 60,
	@available_physical_memory_mb_threshold bigint = 4096,
	@system_high_memory_signal_state_threshold varchar(20) = 'Low',
	@memory_grants_pending_threshold int = 1,
	@connection_count_threshold int = 1000,
	@waits_per_core_per_minute_threshold decimal(20,2) = 180,
	@data_used_pct float = 70,
	@data_used_gb float = 20,
	@log_used_pct float = 70,
	@log_used_gb float = 5,
	@only_threshold_validated bit = 0,
	@ag_latency_minutes int = 30,
	@ag_redo_queue_size_gb int = 10,
	@log_send_queue_size_gb int = 10,
	@disk_warning_pct decimal(20,2) = 80,
	@disk_critical_pct decimal(20,2) = 90,
	@disk_threshold_gb decimal(20,2) = 250,
	@large_disk_threshold_pct decimal(20,2) = 95,
	@buffer_time_minutes int = 30,
	@full_threshold_days int = 8,
	@diff_threshold_hours int = 26,
	@tlog_threshold_minutes int = 240,
	@collect_core_health_metrics bit = 1,
	@collect_tempdb_health bit = 1,
	@collect_log_space bit = 1,
	@collect_ag_latency bit = 1,
	@collect_disk_space bit = 1,
	@collect_offline_servers bit = 1,
	@collect_sqlmonitor_jobs bit = 1,
	@collect_backup_history bit = 1,
	@verbose tinyint = 0 /* 0 - no messages, 1 - debug messages, 2 = debug messages + table results */
)
AS 
BEGIN
	/*
		Version:		1.6.5
		Update:			2024-01-11 - #7 - Adding Backup Issues in mailer
						2023-12-31 - #24 - Daily Mailer containing similar content of 'Monitoring - Live - All Servers' dashboard

		EXEC dbo.usp_GetAllServerDashboardMail @recipients = 'ajay.dwivedi2007@gmail.com', @verbose = 2
	*/
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET LOCK_TIMEOUT 60000; -- 60 seconds

	/* Derived Parameters */
	IF (@recipients IS NULL OR @recipients = 'dba_team@gmail.com') AND @verbose = 0
		raiserror ('@recipients is mandatory parameter', 20, -1) with log;

	declare @dashboard_link varchar(200);
	select @dashboard_link = p.param_value from dbo.sma_params p where p.param_key = 'GrafanaDashboardPortal';
	
	IF right(@dashboard_link ,3) <> '/d/'
		raiserror ('@dashboard_link should be ending with ''/d/''. For example, https://grafana.somedomain.com:3000/d/', 20, -1) with log;

	-- Local Variables
	DECLARE @_sql nvarchar(MAX);
	declare @_params nvarchar(max);
	DECLARE @_collection_time datetime = GETDATE();
	DECLARE @_mail_body_html  nvarchar(MAX); 
	declare @_title nvarchar(2000);
	declare @_style_css nvarchar(max);
	declare @_html_core_health nvarchar(MAX); -- 'Core Health Metrics'
	declare @_html_tempdb_health nvarchar(MAX); -- 'Tempdb Health'
	declare @_html_log_space_health nvarchar(MAX); -- 'Log Space'
	declare @_html_ag_health nvarchar(MAX); -- 'Ag Latency'
	declare @_html_disk_health nvarchar(MAX); -- 'Disk Space'
	declare @_html_offline_servers nvarchar(MAX); -- 'Offline Servers'
	declare @_html_sqlmonitor_jobs nvarchar(max); -- 'SQLMonitor Jobs'
	declare @_html_backup_history nvarchar(max); -- 'Backup History'
	declare @_table_headline nvarchar(500);
	declare @_table_header nvarchar(max);
	declare @_table_data nvarchar(max);	
	declare @_url_all_servers_dashboard varchar(4000) = @dashboard_link+'distributed_live_dashboard_all_servers';

	declare @_url_core_health_panel varchar(4000) = @_url_all_servers_dashboard+'?viewPanel=842';
	declare @_url_tempdb_health_panel varchar(4000) = @_url_all_servers_dashboard+'?viewPanel=860';
	declare @_url_log_space_health_panel varchar(4000) = @_url_all_servers_dashboard+'?viewPanel=856';
	declare @_url_ag_health_panel varchar(4000) = @_url_all_servers_dashboard+'?viewPanel=867';
	declare @_url_disk_health_panel varchar(4000) = @_url_all_servers_dashboard+'?viewPanel=852';
	declare @_url_offline_servers_panel varchar(4000) = @_url_all_servers_dashboard+'?viewPanel=844';
	declare @_url_sqlmonitor_jobs_panel varchar(4000) = @_url_all_servers_dashboard+'?viewPanel=864';
	declare @_url_backup_history_panel varchar(4000) = @_url_all_servers_dashboard+'?viewPanel=869';

	declare @_line nvarchar(500);
	declare @_tab nchar(2) = nchar(9);
	declare @_crlf nchar(2) = nchar(13);

	if @verbose > 0
		print 'Set local variables..';
	set @_title = 'Monitoring - Live - All Servers';
	set @_line = '-----------------------------------------------------------------';

	--set quoted_identifier off;	
	-- https://htmlcolorcodes.com/
	set @_style_css = '<style>		
		.tableContainerDiv {
			overflow: auto;
			max-height: 30em;
		}
		th {
			background-color: black;
			color: white;
			position: sticky;
			top: 0;
		}
		td {
			text-align: center;
		}
		tbody {
			display: block;
			/* height: 50px; */
			overflow: auto;
		}
		thead, tbody tr {
			display: table;
			width: 100%;
			table-layout: fixed;
		}
		thead {
			/* width: calc( 100% - 1em ) */
			width: calc( 100% )
		}

		.bg_desert {
		  background-color: #FAD5A5;
		}
		.bg_green {
		  background-color: green;
		}
		.bg_key {
			background-color: #7fd1f2;
		}
		.bg_metric_neutral {
			background-color: #C663AD;
		}
		.bg_pistachio {
		  background-color: #93C572;
		}
		.bg_orange {
		  background-color: orange;
		}
		.bg_red {
			background-color: red;
		}
		.bg_red_light {
			background-color: #F79F9D;
		}
		.bg_yellow {
		  background-color: #FFFF00;
		}
		.bg_yellow_dark {
		  background-color: #FFBF00;
		}
		.bg_yellow_medium {
		  background-color: #FFEA00;
		}
		.bg_yellow_light {
		  background-color: #FAFA33;
		}
		.bg_yellow_canary {
		  background-color: #FFFF8F;
		}
		.bg_yellow_gold {
		  background-color: #FFD700;
		}
		.scrollit {
			overflow: auto;
		}
	  </style>';
	if @verbose > 0
	begin
		print @_line;
		print '@_style_css => '+@_crlf+@_style_css;
		print @_line;
	end

	if(@collect_core_health_metrics = 1) -- 'Core Health Metrics'
	begin
		if @verbose > 0
		begin
			print @_line;
			print @_line;
			print 'Set @_html_core_health variable..';
			print @_tab+@_line;
		end

		set @_table_headline = N'<h3><a href="'+@_url_core_health_panel+'" target="_blank">All Servers - Health Metrics - Require ATTENTION</a></h3>';
		set @_table_header = N'<tr><th>Server</th> <th>OS CPU %</th> <th>SQL CPU %</th>'
						+N'<th>Blocked Over '+convert(varchar,@blocked_duration_max_seconds_threshold)+' seconds</th>'
						+N'<th>Longest Blocking</th> <th>Available Memory</th> <th>OS Memory State</th>'
						+N'<th>Used SQL Memory</th> <th>Memory Grants Pending</th> <th>SQL Connections</th>'
						+N'<th>Waits Per Core Per Minute</th>';
		set @_table_data = NULL;

		if not exists (select * from dbo.vw_all_server_info)
			raiserror ('Data does not exist in dbo.vw_all_server_info', 17, -1) with log;

		if @verbose > 1
		begin
			;with t_cte as (
				select	srv_name, os_cpu, sql_cpu, blocked_counts, blocked_duration_max_seconds, available_physical_memory_kb, system_high_memory_signal_state, physical_memory_in_use_kb, memory_grants_pending, connection_count, waits_per_core_per_minute
				from dbo.vw_all_server_info
				where 1=1
				and (   os_cpu >= @os_cpu_threshold
					or  sql_cpu >= @sql_cpu_threshold 
					or  blocked_counts >= @blocked_counts_threshold
					or  blocked_duration_max_seconds >= @blocked_duration_max_seconds_threshold
					or  ( available_physical_memory_kb < (@available_physical_memory_mb_threshold*1024) 
						and system_high_memory_signal_state = @system_high_memory_signal_state_threshold 
						)
					or  memory_grants_pending > @memory_grants_pending_threshold
					or  connection_count >= @connection_count_threshold
					or  waits_per_core_per_minute > @waits_per_core_per_minute_threshold
					)
			)
			select [RunningQuery], t_cte.*
			from t_cte
			full outer join (select [RunningQuery] = 'Core Health Metrics') rq
				on 1=1
		end

		;with asi as (
			select	srv_name, os_cpu, sql_cpu, blocked_counts, blocked_duration_max_seconds, available_physical_memory_kb, system_high_memory_signal_state, physical_memory_in_use_kb, memory_grants_pending, connection_count, waits_per_core_per_minute
			from dbo.vw_all_server_info
		)
		,t_cte as (
			select	'<tr>'
					+'<td class="bg_key">'+srv_name+'</td>'
					+'<td class="'+(case when os_cpu >= 90 then 'bg_red'
									when os_cpu >= 80 then 'bg_orange'
									when os_cpu >= 70 then 'bg_yellow_medium'
									else 'bg_none'
									end)+'">'+convert(varchar,os_cpu)+'</td>'
					+'<td class="'+(case when sql_cpu >= 90 then 'bg_red'
									when sql_cpu >= 80 then 'bg_orange'
									when sql_cpu >= 70 then 'bg_yellow_medium'
									else 'bg_none'
									end)+'">'+convert(varchar,sql_cpu)+'</td>'
					+'<td class="'+(case when blocked_counts >= 10 then 'bg_red'
									when blocked_counts >= 5 then 'bg_orange'
									when blocked_counts >= 1 then 'bg_yellow_medium'
									else 'bg_none'
									end)+'">'+convert(varchar,isnull(blocked_counts,0))+'</td>'
					+'<td class="'+(case when blocked_duration_max_seconds >= 1800 then 'bg_red'
									when blocked_duration_max_seconds >= 600 then 'bg_orange'
									when blocked_duration_max_seconds >= 300 then 'bg_yellow_dark'
									when blocked_duration_max_seconds >= 120 then 'bg_yellow_medium'
									when blocked_duration_max_seconds >= 60 then 'bg_yellow_light'
									else 'bg_none'
									end)+'">'+isnull((case when blocked_duration_max_seconds < 60 then convert(varchar,floor(blocked_duration_max_seconds))+' sec'
							when blocked_duration_max_seconds < 3600 then convert(varchar,floor(blocked_duration_max_seconds/60))+' min'
							when blocked_duration_max_seconds < 86400 then convert(varchar,floor(blocked_duration_max_seconds/3600))+' hrs'
							when blocked_duration_max_seconds >= 86400 then convert(varchar,floor(blocked_duration_max_seconds/86400))+' days'
							else 'xx' end),0)+'</td>'
					+'<td class="'+(case when available_physical_memory_kb > 4194304 then 'bg_none'
									when available_physical_memory_kb > 2097152 then 'bg_yellow'
									when available_physical_memory_kb > 512000 then 'bg_orange'
									else 'bg_red'
									end)+'">'+(case when available_physical_memory_kb < 1024 then convert(varchar,available_physical_memory_kb)+' kb'
							when available_physical_memory_kb < 1024*1024 then convert(varchar,floor(available_physical_memory_kb/1024))+' mb'
							when available_physical_memory_kb < 1024*1024*1024 then convert(varchar,floor(available_physical_memory_kb/(1024*1024)))+' gb'
							when available_physical_memory_kb >= 1024*1024*1024 then convert(varchar,floor(available_physical_memory_kb/(1024*1024*1024)))+' tb'
							else 'xx' end)+'</td>'
					+'<td>'+system_high_memory_signal_state+'</td>'
					+'<td>'+(case when physical_memory_in_use_kb < 1024 then convert(varchar,physical_memory_in_use_kb)+' kb'
							when physical_memory_in_use_kb < 1024*1024 then convert(varchar,floor(physical_memory_in_use_kb/1024))+' mb'
							when physical_memory_in_use_kb < 1024*1024*1024 then convert(varchar,floor(physical_memory_in_use_kb/(1024*1024)))+' gb'
							when physical_memory_in_use_kb >= 1024*1024*1024 then convert(varchar,floor(physical_memory_in_use_kb/(1024*1024*1024)))+' tb'
							else 'xx' end)+'</td>'
					+'<td class="'+(case when memory_grants_pending > 0 then 'bg_red'
									else 'bg_none'
									end)+'">'+convert(varchar,isnull(memory_grants_pending,0))+'</td>'
					+'<td class="'+(case when connection_count >= 1200 then 'bg_red'
									when connection_count >= 1000 then 'bg_orange'
									when connection_count >= 800 then 'bg_yellow'
									else 'bg_none'
									end)+'">'+convert(varchar,connection_count)+'</td>'
					+'<td class="'+(case when waits_per_core_per_minute >= 300 then 'bg_red'
									when waits_per_core_per_minute >= 240 then 'bg_orange'
									when waits_per_core_per_minute >= 180 then 'bg_yellow'
									else 'bg_none'
									end)+'">'+isnull((case when waits_per_core_per_minute < 60 then convert(varchar,floor(waits_per_core_per_minute))+' sec'
							when waits_per_core_per_minute < 3600 then convert(varchar,floor(waits_per_core_per_minute/60))+' min'
							when waits_per_core_per_minute < 86400 then convert(varchar,floor(waits_per_core_per_minute/3600))+' hrs'
							when waits_per_core_per_minute >= 86400 then convert(varchar,floor(waits_per_core_per_minute/86400))+' days'
							else 'xx' end),'-1')+'</td>'
					+'</tr>' as [table_row]
			from asi cte
			where 1=1
			and (   os_cpu >= @os_cpu_threshold
				or  sql_cpu >= @sql_cpu_threshold 
				or  blocked_counts >= @blocked_counts_threshold
				or  blocked_duration_max_seconds >= @blocked_duration_max_seconds_threshold
				or  ( available_physical_memory_kb < (@available_physical_memory_mb_threshold*1024) 
					and system_high_memory_signal_state = @system_high_memory_signal_state_threshold 
					)
				or  memory_grants_pending > @memory_grants_pending_threshold
				or  connection_count >= @connection_count_threshold
				or  waits_per_core_per_minute > @waits_per_core_per_minute_threshold
				)
		)
		select @_table_data = coalesce(@_table_data+' '+[table_row],[table_row])
		from t_cte;

		set @_html_core_health = @_table_headline+'<div class="tableContainerDiv"><table border="1">'
						+'<caption>@os_cpu_threshold:'+convert(varchar,@os_cpu_threshold)
							+' || @sql_cpu_threshold:'+convert(varchar,@sql_cpu_threshold)
							+' || @blocked_counts_threshold:'+convert(varchar,@blocked_counts_threshold)
							+' || @blocked_duration_max_seconds_threshold:'+convert(varchar,@blocked_duration_max_seconds_threshold)
							+' || @available_physical_memory_mb_threshold:'+convert(varchar,@available_physical_memory_mb_threshold)
							+' || @system_high_memory_signal_state_threshold:'+convert(varchar,@system_high_memory_signal_state_threshold)
							+' || @memory_grants_pending_threshold:'+convert(varchar,@memory_grants_pending_threshold)
							+' || @connection_count_threshold:'+convert(varchar,@connection_count_threshold)
							+' || @waits_per_core_per_minute_threshold:'+convert(varchar,@waits_per_core_per_minute_threshold)
						+'</caption>'
						+'<thead>'+@_table_header+'</thead><tbody>'+isnull(@_table_data,'')+'</tbody></table></div>';

		if @verbose > 0
		begin
			print @_tab+'@_table_header => '+@_crlf+@_table_header;
			print @_tab+@_line;
			print @_tab+'@_table_data => '+@_crlf+ISNULL(@_table_data,'');
			print @_tab+@_line;
			print @_tab+'@_html_core_health => '+@_crlf+ISNULL(@_html_core_health,'');
		end
	end -- 'Core Health Metrics'

	if(@collect_tempdb_health = 1) -- 'Tempdb Health'
	begin
		if @verbose > 0
		begin
			print @_line;
			print @_line;
			print 'Set @_html_tempdb_health variable..';
			print @_tab+@_line;
		end

		set @_table_headline = N'<h3><a href="'+@_url_tempdb_health_panel+'" target="_blank">All Servers - Tempdb Utilization - Require ATTENTION</a></h3>';
		set @_table_header = N'<tr><th>Collection Time</th> <th>Server</th> <th>Data Size</th>'
						+N'<th>Data Used</th> <th>Data Used %</th> <th>Log Size</th> <th>Log Used</th> <th>Log Used %</th>'
						+N'<th>Version Store</th> <th>Version Store %</th>';
		set @_table_data = NULL;

		if not exists (select * from dbo.tempdb_space_usage_all_servers)
			raiserror ('Data does not exist in dbo.tempdb_space_usage_all_servers', 17, -1) with log;

		if @verbose > 1
		begin
			;with t_cte as (
				select	[collection_time_utc] = [updated_date_utc],
						[sql_instance], [data_size_mb], [data_used_mb], [data_used_pct], [log_size_mb], [log_used_mb], 
						[log_used_pct], [version_store_mb], [version_store_pct]
				from dbo.tempdb_space_usage_all_servers su
				where 1=1
				and (su.data_used_pct > @data_used_pct
					or su.data_used_mb > (@data_used_gb*1024) -- 200 gb
					)
				and (su.updated_date_utc >= dateadd(minute,-60,getutcdate())
				  and su.collection_time_utc >= dateadd(minute,-20,getutcdate())
					)
			)
			select [RunningQuery], t_cte.*
			from t_cte
			full outer join (select [RunningQuery] = 'Tempdb Health') rq
				on 1=1
		end

		;with tsu as (
			select	[collection_time_utc] = [updated_date_utc],
					[sql_instance], [data_size_mb], [data_used_mb], [data_used_pct], [log_size_mb], [log_used_mb], 
					[log_used_pct], [version_store_mb], [version_store_pct]
			from dbo.tempdb_space_usage_all_servers su
			where (su.data_used_pct > @data_used_pct
				or su.data_used_mb > (@data_used_gb*1024) -- 200 gb
				)
			and (su.updated_date_utc >= dateadd(minute,-60,getutcdate())
			  and su.collection_time_utc >= dateadd(minute,-20,getutcdate())
				)
		)
		,t_cte as (
			select	'<tr>'
					+'<td class="bg_metric_neutral">'+convert(varchar,DATEADD(mi, DATEDIFF(mi, GETUTCDATE(), GETDATE()), collection_time_utc),120)+'</td>'
					+'<td class="bg_key">'+sql_instance+'</td>'
					+'<td>'+(case when data_size_mb < 1024 then convert(varchar,data_size_mb)+' mb'
							when data_size_mb < 1024*1024 then convert(varchar,floor(data_size_mb/1024))+' gb'
							when data_size_mb >= 1024*1024 then convert(varchar,floor(data_size_mb/(1024*1024)))+' tb'
							else 'xx' end)+'</td>'
					+'<td class="'+(case when data_used_mb > (@data_used_gb*1024) then 'bg_yellow_medium'
									else 'bg_none'
									end)+'">'+(case when data_used_mb < 1024 then convert(varchar,data_used_mb)+' mb'
							when data_used_mb < 1024*1024 then convert(varchar,floor(data_used_mb/1024))+' gb'
							when data_used_mb >= 1024*1024 then convert(varchar,floor(data_used_mb/(1024*1024)))+' tb'
							else 'xx' end)+'</td>'
					+'<td class="'+(case when data_used_pct >= 95 then 'bg_red'
									when data_used_pct >= 90 then 'bg_red_light'
									when data_used_pct >= 80 then 'bg_orange'
									when data_used_pct >= 70 then 'bg_yellow_medium'
									else 'bg_none'
									end)+'">'+convert(varchar,data_used_pct)+'</td>'
					+'<td>'+(case when log_size_mb < 1024 then convert(varchar,log_size_mb)+' mb'
							when log_size_mb < 1024*1024 then convert(varchar,floor(log_size_mb/1024))+' gb'
							when log_size_mb >= 1024*1024 then convert(varchar,floor(log_size_mb/(1024*1024)))+' tb'
							else 'xx' end)+'</td>'
					+'<td>'+(case when log_used_mb < 1024 then convert(varchar,log_used_mb)+' mb'
							when log_used_mb < 1024*1024 then convert(varchar,floor(log_used_mb/1024))+' gb'
							when log_used_mb >= 1024*1024 then convert(varchar,floor(log_used_mb/(1024*1024)))+' tb'
							else 'xx' end)+'</td>'
					+'<td class="'+(case when log_used_pct >= 90.0 then 'bg_red'
									when log_used_pct >= 80.0 then 'bg_orange'
									when log_used_pct >= 70.0 then 'bg_yellow'
									else 'bg_none'
									end)+'">'+convert(varchar,log_used_pct)+'</td>'
					+'<td class="'+(case when version_store_mb > (@data_used_gb*1024) then 'bg_yellow_medium'
									else 'bg_none'
									end)+'">'+(case when version_store_mb < 1024 then convert(varchar,version_store_mb)+' mb'
							when version_store_mb < 1024*1024 then convert(varchar,floor(version_store_mb/1024))+' gb'
							when version_store_mb >= 1024*1024 then convert(varchar,floor(version_store_mb/(1024*1024)))+' tb'
							else 'xx' end)+'</td>'
					+'<td class="'+(case when version_store_pct >= 90.0 then 'bg_red'
									when version_store_pct >= 80.0 then 'bg_orange'
									when version_store_pct >= 70.0 then 'bg_yellow'
									else 'bg_none'
									end)+'">'+convert(varchar,version_store_pct)+'</td>'
					+'</tr>' as [table_row]
			from tsu
			where 1=1
		)
		--select * from t_cte;
		select @_table_data = coalesce(@_table_data+' '+[table_row],[table_row])
		from t_cte;

		set @_html_tempdb_health = '<hr><br>'+@_table_headline+'<div class="tableContainerDiv"><table border="1">'
						+'<caption>@data_used_pct:'+convert(varchar,@data_used_pct)+' || @data_used_gb:'+convert(varchar,@data_used_gb)+'</caption>'
						+'<thead>'+@_table_header+'</thead><tbody>'+isnull(@_table_data,'')+'</tbody></table></div>';

		if @verbose > 0
		begin
			print @_tab+'@_table_header => '+@_crlf+@_table_header;
			print @_tab+@_line;
			print @_tab+'@_table_data => '+@_crlf+ISNULL(@_table_data,'');
			print @_tab+@_line;
			print @_tab+'@_html_tempdb_health => '+@_crlf+ISNULL(@_html_tempdb_health,'');
		end
	end -- 'Tempdb Health'

	if(@collect_log_space = 1) -- 'Log Space'
	begin
		if @verbose > 0
		begin
			print @_line;
			print @_line;
			print 'Set @_html_log_space_health variable..';
			print @_tab+@_line;
		end

		set @_table_headline = N'<h3><a href="'+@_url_log_space_health_panel+'" target="_blank">All Servers - Log Space Utilization - Require ATTENTION</a></h3>';
		set @_table_header = N'<tr><th>Collection Time</th> <th>Server</th> <th>Database</th>'
						+N'<th>Recovery Model</th> <th>Log Reuse Wait Desc</th>'
						+N'<th>Log Size</th> <th>Autogrowth</th> <th>Log Used</th> <th>Log Used %</th>'
						+N'<th>login_name</th> <th>program_name</th>';
		set @_table_data = NULL;

		if not exists (select * from dbo.log_space_consumers_all_servers)
			raiserror ('Data does not exist in dbo.log_space_consumers_all_servers', 17, -1) with log;

		if @verbose > 1
		begin
			set @_params = '@only_threshold_validated bit, @log_used_pct float, @log_used_gb float';
			set @_sql = '
			;with t_cte as (
				select	[collection_time_utc] = [updated_date_utc],
						[sql_instance], [database_name], [recovery_model], [log_reuse_wait_desc], [log_size_mb], [exists_valid_autogrowing_file],
						[log_used_mb], [log_used_pct], [login_name], [program_name]
						--,[log_used_pct_threshold], [log_used_gb_threshold], [spid]
						--,[transaction_start_time] = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), [transaction_start_time])
						--,[host_name], [host_process_id], [command], [additional_info]
						--,[action_taken], [sql_text]		
				from dbo.log_space_consumers_all_servers ls
				where 1=1
				'+(case when @only_threshold_validated = 1 then '' else '--' end)+'and ls.thresholds_validated = @only_threshold_validated
				'+(case when @only_threshold_validated = 1 then '--' else '' end)+'and ( (ls.log_used_pct > @log_used_pct)	or (ls.log_used_mb > (@log_used_gb*1024)) )
				and (ls.updated_date_utc >= dateadd(minute,-60,getutcdate())
				  and ls.collection_time_utc >= dateadd(minute,-20,getutcdate())
						)
			)
			select [RunningQuery], t_cte.*
			from t_cte
			full outer join (select [RunningQuery] = ''Log Space'') rq
				on 1=1
			';

			exec sp_executesql @_sql, @_params, @only_threshold_validated, @log_used_pct, @log_used_gb;
		end

		set @_params = '@only_threshold_validated bit, @log_used_pct float, @log_used_gb float, @table_data nvarchar(max) output';
		set @_sql = '
		;with lsc as 
		(
			select	[collection_time_utc] = [updated_date_utc],
					[sql_instance], [database_name], [recovery_model], [log_reuse_wait_desc], [log_size_mb], [exists_valid_autogrowing_file],
					[log_used_mb], [log_used_pct], [login_name], [program_name]
			from dbo.log_space_consumers_all_servers ls
			where 1=1
			'+(case when @only_threshold_validated = 1 then '' else '--' end)+'and ls.thresholds_validated = @only_threshold_validated
			'+(case when @only_threshold_validated = 1 then '--' else '' end)+'and ( (ls.log_used_pct > @log_used_pct)	or (ls.log_used_mb > (@log_used_gb*1024)) )
			and (ls.updated_date_utc >= dateadd(minute,-60,getutcdate())
				and ls.collection_time_utc >= dateadd(minute,-20,getutcdate())
					)
		)
		,t_cte as (
			select	''<tr>''
					+''<td class="bg_metric_neutral">''+convert(varchar,DATEADD(mi, DATEDIFF(mi, GETUTCDATE(), GETDATE()), collection_time_utc),120)+''</td>''
					+''<td class="bg_key">''+sql_instance+''</td>''
					+''<td class="bg_key">''+[database_name]+''</td>''
					+''<td>''+recovery_model+''</td>''
					+''<td>''+log_reuse_wait_desc+''</td>''
					+''<td>''+(case when log_size_mb < 1024 then convert(varchar,log_size_mb)+'' mb''
							when log_size_mb < 1024*1024 then convert(varchar,floor(log_size_mb/1024))+'' gb''
							when log_size_mb >= 1024*1024 then convert(varchar,floor(log_size_mb/(1024*1024)))+'' tb''
							else ''xx'' end)+''</td>''
					+''<td>''+convert(varchar,exists_valid_autogrowing_file)+''</td>''
					+''<td class="''+(case when log_used_mb > (@log_used_gb*1024) then ''bg_yellow_medium''
									else ''bg_none''
									end)+''">''+(case when log_used_mb < 1024 then convert(varchar,log_used_mb)+'' mb''
							when log_used_mb < 1024*1024 then convert(varchar,floor(log_used_mb/1024))+'' gb''
							when log_used_mb >= 1024*1024 then convert(varchar,floor(log_used_mb/(1024*1024)))+'' tb''
							else ''xx'' end)+''</td>''
					+''<td class="''+(case when log_used_pct >= 90.0 then ''bg_red''
									when log_used_pct >= 80.0 then ''bg_orange''
									when log_used_pct >= 70.0 then ''bg_yellow''
									else ''bg_none''
									end)+''">''+convert(varchar,log_used_pct)+''</td>''
					+''<td>''+coalesce([login_name],'''')+''</td>''
					+''<td>''+coalesce([program_name],'''')+''</td>''
					+''</tr>'' as [table_row]
			from lsc
		)
		--select * from t_cte
		select @table_data = coalesce(@table_data+'' ''+[table_row],[table_row])
		from t_cte;
		';

		exec sp_executesql @_sql, @_params, @only_threshold_validated, @log_used_pct, @log_used_gb, @table_data = @_table_data output;

		set @_html_log_space_health = '<hr><br>'+@_table_headline+'<div class="tableContainerDiv"><table border="1">'
						+'<caption>@only_threshold_validated:'+convert(varchar,@only_threshold_validated)+' || @log_used_pct:'+convert(varchar,@log_used_pct)+' || @log_used_gb:'+convert(varchar,@log_used_gb)+'</caption>'
						+'<thead>'+@_table_header+'</thead><tbody>'+isnull(@_table_data,'')+'</tbody></table></div>';

		if @verbose > 0
		begin
			print @_tab+'@_table_header => '+@_crlf+@_table_header;
			print @_tab+@_line;
			print @_tab+'@_table_data => '+@_crlf+ISNULL(@_table_data,'');
			print @_tab+@_line;
			print @_tab+'@_html_log_space_health => '+@_crlf+ISNULL(@_html_log_space_health,'');
		end
	end -- 'Log Space'

	if(@collect_ag_latency = 1) -- 'Ag Latency'
	begin
		if @verbose > 0
		begin
			print @_line;
			print @_line;
			print 'Set @_html_ag_health variable..';
			print @_tab+@_line;
		end

		set @_table_headline = N'<h3><a href="'+@_url_ag_health_panel+'" target="_blank">All Servers - AlwaysOn Latency - Require ATTENTION</a></h3>';
		set @_table_header = N'<tr><th>Server</th> <th>Database</th> <th>Is Primary</th>'
						+N'<th>Listener</th> <th>Is Local</th> <th>Sync State</th> <th>Sync Health</th>'
						+N'<th>Latency</th> <th>Log Send Queue</th> <th>Redo Queue</th>'
						+N'<th>Is Suspended</th>'
		set @_table_data = NULL;

		if not exists (select * from dbo.ag_health_state_all_servers)
			print 'Data does not exist in dbo.ag_health_state_all_servers';

		if @verbose > 1
		begin
			;with t_cte as (
				select	sql_instance, [replica_database] = replica_server_name+' || '+database_name,
						is_primary_replica,	ag_listener, is_local, synchronization_state_desc, synchronization_health_desc, 
						latency_seconds, log_send_queue_size, redo_queue_size, is_suspended
				from dbo.ag_health_state_all_servers ahs
				where 1=1
				and (	ahs.synchronization_health_desc <> 'HEALTHY'
					or	ahs.synchronization_state_desc not in ('SYNCHRONIZED','SYNCHRONIZING')
					or	(ahs.latency_seconds is not null and ahs.latency_seconds >= @ag_latency_minutes*60)
					or	(ahs.log_send_queue_size is not null and ahs.log_send_queue_size >= @log_send_queue_size_gb*1024*1024)
					or	(ahs.redo_queue_size is not null and ahs.redo_queue_size >= @ag_redo_queue_size_gb*1024*1024)
					)
			)
			select [RunningQuery], t_cte.*
			from t_cte
			full outer join (select [RunningQuery] = 'Ag Latency') rq
				on 1=1;
		end

		;with tsu as (
			select	sql_instance, [replica_database] = replica_server_name+' || '+database_name,
						is_primary_replica,	ag_listener, is_local, synchronization_state_desc, synchronization_health_desc, 
						latency_seconds, log_send_queue_size, redo_queue_size, is_suspended
				from dbo.ag_health_state_all_servers ahs
				where 1=1
				and (	ahs.synchronization_health_desc <> 'HEALTHY'
					or	ahs.synchronization_state_desc not in ('SYNCHRONIZED','SYNCHRONIZING')
					or	(ahs.latency_seconds is not null and ahs.latency_seconds >= @ag_latency_minutes*60)
					or	(ahs.log_send_queue_size is not null and ahs.log_send_queue_size >= @log_send_queue_size_gb*1024*1024)
					or	(ahs.redo_queue_size is not null and ahs.redo_queue_size >= @ag_redo_queue_size_gb*1024*1024)
					)
		)
		,t_cte as (
			select	'<tr>'
					+'<td class="bg_key">'+sql_instance+'</td>'
					+'<td class="bg_key">'+replica_database+'</td>'
					+'<td>'+convert(varchar,is_primary_replica)+'</td>'
					+'<td>'+isnull(ag_listener,'')+'</td>'
					+'<td>'+convert(varchar,is_local)+'</td>'
					+'<td class="'+(case synchronization_state_desc
									when 'SYNCHRONIZED' then 'bg_green'
									when 'NOT SYNCHRONIZING' then 'bg_red'
									when 'SYNCHRONIZING' then 'bg_cyan'
									when 'REVERTING' then 'bg_yellow_dark'
									when 'INITIALIZING' then 'bg_yellow_light'
									else 'bg_none'
									end)+'">'+isnull(synchronization_state_desc,'')+'</td>'
					+'<td class="'+(case synchronization_health_desc
									when 'HEALTHY' then 'bg_green'
									when 'NOT_HEALTHY' then 'bg_red'
									when 'PARTIALLY_HEALTHY' then 'bg_orange'
									else 'bg_none'
									end)+'">'+isnull(synchronization_health_desc,'')+'</td>'
					+'<td class="'+(case when latency_seconds >= 1800 then 'bg_red'
									when latency_seconds >= 600 then 'bg_orange'
									when latency_seconds >= 300 then 'bg_yellow_dark'
									when latency_seconds >= 240 then 'bg_yellow_medium'
									when latency_seconds >= 120 then 'bg_yellow_light'
									else 'bg_none'
									end)+'">'+isnull((case when latency_seconds < 60 then convert(varchar,floor(latency_seconds))+' sec'
							when latency_seconds < 3600 then convert(varchar,floor(latency_seconds/60))+' min'
							when latency_seconds < 86400 then convert(varchar,floor(latency_seconds/3600))+' hrs'
							when latency_seconds >= 86400 then convert(varchar,floor(latency_seconds/86400))+' days'
							else '' end),' ')+'</td>'
					+'<td class="'+(case when log_send_queue_size > 100000000 then 'bg_red'
									when log_send_queue_size > 10000000 then 'bg_orange'
									when log_send_queue_size > 1000000 then 'bg_yellow'
									else 'bg_none'
									end)+'">'+
							isnull((case when log_send_queue_size < 1024 then convert(varchar,log_send_queue_size)+' kb'
								when log_send_queue_size < 1024*1024 then convert(varchar,log_send_queue_size/1024)+' mb'
								when log_send_queue_size < 1024*1024*1024 then convert(varchar,floor(log_send_queue_size/(1024*1024)))+' gb'
								when log_send_queue_size >= 1024*1024*1024 then convert(varchar,floor(log_send_queue_size/(1024*1024*1024)))+' tb'
								else '' end),' ')+'</td>'
					+'<td class="'+(case when redo_queue_size > 100000000 then 'bg_red'
									when redo_queue_size > 10000000 then 'bg_orange'
									when redo_queue_size > 1000000 then 'bg_yellow'
									else 'bg_none'
									end)+'">'
							+isnull((case when redo_queue_size < 1024 then convert(varchar,redo_queue_size)+' kb'
								when redo_queue_size < 1024*1024 then convert(varchar,redo_queue_size/1024)+' mb'
								when redo_queue_size < 1024*1024*1024 then convert(varchar,floor(redo_queue_size/(1024*1024)))+' gb'
								when redo_queue_size >= 1024*1024*1024 then convert(varchar,floor(redo_queue_size/(1024*1024*1024)))+' tb'
								else '' end),' ')+'</td>'
					+'<td>'+convert(varchar,is_suspended)+'</td>'
					+'</tr>' as [table_row]
			from tsu
			where 1=1
		)
		--select * from t_cte;
		select @_table_data = coalesce(@_table_data+' '+[table_row],[table_row])
		from t_cte;

		set @_html_ag_health = '<hr><br>'+@_table_headline+'<div class="tableContainerDiv"><table border="1">'
						+'<caption>@ag_latency_minutes:'+convert(varchar,@ag_latency_minutes)
							+' || @log_send_queue_size_gb:'+convert(varchar,@log_send_queue_size_gb)
							+' || @ag_redo_queue_size_gb:'+convert(varchar,@ag_redo_queue_size_gb)
						+'</caption>'
						+'<thead>'+@_table_header+'</thead><tbody>'+isnull(@_table_data,'')+'</tbody></table></div>';

		if @verbose > 0
		begin
			print @_tab+'@_table_header => '+@_crlf+@_table_header;
			print @_tab+@_line;
			print @_tab+'@_table_data => '+@_crlf+ISNULL(@_table_data,'');
			print @_tab+@_line;
			print @_tab+'@_html_ag_health => '+@_crlf+ISNULL(@_html_ag_health,'');
		end
	end -- 'Ag Latency'

	if(@collect_disk_space = 1) -- 'Disk Space'
	begin
		if @verbose > 0
		begin
			print @_line;
			print @_line;
			print 'Set @_html_disk_health variable..';
			print @_tab+@_line;
		end

		set @_table_headline = N'<h3><a href="'+@_url_disk_health_panel+'" target="_blank">All Servers - Disk Utilization - Require ATTENTION</a></h3>';
		set @_table_header = N'<tr><th>Server</th> <th>Host</th> <th>Disk</th> <th>Capacity</th>'
						+N'<th>Free Space</th> <th>Status</th> <th>Used %</th>';
		set @_table_data = NULL;

		if not exists (select * from dbo.disk_space_all_servers)
			raiserror ('Data does not exist in dbo.disk_space_all_servers', 17, -1) with log;

		if @verbose > 1
		begin
			;with t_cte as (
				select	ds.sql_instance, ds.host_name, ds.disk_volume, ds.capacity_mb, 
						ds.free_mb,
						[state] = case when (ds.free_mb*100.0/ds.capacity_mb) < (100.0-@disk_critical_pct) then 'Critical' else 'Warning' end,
						[used_pct] = 100.0-convert(numeric(20,2),ds.free_mb*100.0/ds.capacity_mb)
				from dbo.disk_space_all_servers ds
				where ds.updated_date_utc >= dateadd(minute,-60,getutcdate())
				and (	(	(ds.free_mb*100.0/ds.capacity_mb) < (100-@disk_warning_pct)
							and ds.free_mb < (@disk_threshold_gb)*1024
	  					)
						or ( (ds.free_mb*100.0/ds.capacity_mb) < (100-@large_disk_threshold_pct)) -- free %
						)
			)
			select [RunningQuery], t_cte.*
			from t_cte
			full outer join (select [RunningQuery] = 'Disk Space') rq
				on 1=1
			order by [used_pct] desc
		end

		;with tsu as (
			select	top 100000
					ds.sql_instance, ds.[host_name], ds.disk_volume, ds.capacity_mb, 
					ds.free_mb,
					[state] = case when (ds.free_mb*100.0/ds.capacity_mb) < (100.0-@disk_critical_pct) then 'Critical' else 'Warning' end,
					[used_pct] = 100.0-convert(numeric(20,2),ds.free_mb*100.0/ds.capacity_mb)
			from dbo.disk_space_all_servers ds
			where ds.updated_date_utc >= dateadd(minute,-60,getutcdate())
			and (	(	(ds.free_mb*100.0/ds.capacity_mb) < (100-@disk_warning_pct)
						and ds.free_mb < (@disk_threshold_gb)*1024
	  				)
					or ( (ds.free_mb*100.0/ds.capacity_mb) < (100-@large_disk_threshold_pct)) -- free %
					)
			order by [used_pct] desc
		)
		,t_cte as (
			select	'<tr>'
					+'<td class="bg_key">'+sql_instance+'</td>'
					+'<td class="bg_key">'+[host_name]+'</td>'
					+'<td class="bg_key">'+disk_volume+'</td>'
					+'<td>'+(case when capacity_mb < 1024 then convert(varchar,capacity_mb)+' mb'
							when capacity_mb < 1024*1024 then convert(varchar,floor(capacity_mb/1024))+' gb'
							when capacity_mb >= 1024*1024 then convert(varchar,floor(capacity_mb/(1024*1024)))+' tb'
							else 'xx' end)+'</td>'
					+'<td>'+(case when free_mb < 1024 then convert(varchar,free_mb)+' mb'
							when free_mb < 1024*1024 then convert(varchar,floor(free_mb/1024))+' gb'
							when free_mb >= 1024*1024 then convert(varchar,floor(free_mb/(1024*1024)))+' tb'
							else 'xx' end)+'</td>'
					+'<td class="'+(case [state]
									when 'Critical' then 'bg_red'
									when 'Warning' then 'bg_orange'
									else 'bg_none'
									end)+'">'+[state]+'</td>'
					+'<td class="'+(case when used_pct >= 95.0 then 'bg_red'
									when used_pct >= 90.0 then 'bg_orange'
									when used_pct >= 80.0 then 'bg_yellow_dark'
									when used_pct >= 70.0 then 'bg_yellow_light'
									else 'bg_none'
									end)+'">'+convert(varchar,used_pct)+'</td>'
					+'</tr>' as [table_row]
			from tsu
			where 1=1
		)
		--select * from t_cte;
		select @_table_data = coalesce(@_table_data+' '+[table_row],[table_row])
		from t_cte;

		set @_html_disk_health = '<hr><br>'+@_table_headline+'<div class="tableContainerDiv"><table border="1">'
						+'<caption>@disk_warning_pct:'+convert(varchar,@disk_warning_pct)
							+' || @disk_critical_pct:'+convert(varchar,@disk_critical_pct)
							+' || @disk_threshold_gb:'+convert(varchar,@disk_threshold_gb)
							+' || @large_disk_threshold_pct:'+convert(varchar,@large_disk_threshold_pct)
						+'</caption>'
						+'<thead>'+@_table_header+'</thead><tbody>'+isnull(@_table_data,'')+'</tbody></table></div>';

		if @verbose > 0
		begin
			print @_tab+'@_table_header => '+@_crlf+@_table_header;
			print @_tab+@_line;
			print @_tab+'@_table_data => '+@_crlf+ISNULL(@_table_data,'');
			print @_tab+@_line;
			print @_tab+'@_html_disk_health => '+@_crlf+ISNULL(@_html_disk_health,'');
		end
	end -- 'Disk Space'

	if(@collect_offline_servers = 1) -- 'Offline Servers'
	begin
		if @verbose > 0
		begin
			print @_line;
			print @_line;
			print 'Set @_html_offline_servers variable..';
			print @_tab+@_line;
		end

		set @_table_headline = N'<h3><a href="'+@_url_offline_servers_panel+'" target="_blank">CRITICAL - SQLInstance - OFFLINE/Linked Server Issue</a></h3>';
		set @_table_header = N'<tr><th>Server</th> <th>Host</th> <th>Is Available</th>'
						+N'<th>Linked Server OK?</th> <th>Server (Tsql) Jobs</th>'
						+N'<th>Server (PS) Jobs</th> <th>Data Server</th>'
						+N'<th>Report Time</th>'
		set @_table_data = NULL;

		if @verbose > 1
		begin
			;with t_cte as (
				select	sql_instance, [host_name], 
						is_available, 
						is_linked_server_working = case when is_available = 0 then null else is_linked_server_working end,
						[tsql jobs server] = collector_tsql_jobs_server, 
						[powershell jobs server] = collector_powershell_jobs_server,
						[perfmon data server] = data_destination_sql_instance, 
						last_unavailability_time_utc
				from dbo.instance_details id
				where is_enabled = 1
				and (is_available = 0 or is_linked_server_working = 0)
			)
			select [RunningQuery], t_cte.*
			from t_cte
			full outer join (select [RunningQuery] = 'Offline Servers') rq
				on 1=1;
		end

		;with tsu as (
			select	sql_instance, [host_name], 
					is_available, 
					is_linked_server_working = case when is_available = 0 then null else is_linked_server_working end,
					[tsql jobs server] = collector_tsql_jobs_server, 
					[powershell jobs server] = collector_powershell_jobs_server,
					[perfmon data server] = data_destination_sql_instance, 
					last_unavailability_time_utc
			from dbo.instance_details id
			where is_enabled = 1
			and (is_available = 0 or is_linked_server_working = 0)
		)
		,t_cte as (
			select	'<tr>'
					+'<td class="bg_key">'+sql_instance+'</td>'
					+'<td class="bg_key">'+[host_name]+'</td>'
					+'<td class="'+(case when is_available = 0 then 'bg_red'
									else 'bg_none'
									end)+'">'+convert(varchar,is_available)+'</td>'
					+'<td class="'+(case when is_linked_server_working = 0 then 'bg_red'
									else 'bg_none'
									end)+'">'+isnull(convert(varchar,is_linked_server_working),'')+'</td>'
					+'<td>'+[tsql jobs server]+'</td>'
					+'<td>'+[powershell jobs server]+'</td>'
					+'<td>'+[perfmon data server]+'</td>'
					+'<td>'+isnull(convert(varchar,last_unavailability_time_utc,120),'')+'</td>'
					+'</tr>' as [table_row]
			from tsu
			where 1=1
		)
		--select * from t_cte;
		select @_table_data = coalesce(@_table_data+' '+[table_row],[table_row])
		from t_cte;

		set @_html_offline_servers = '<hr><br>'+@_table_headline+'<div class="tableContainerDiv"><table border="1">'
						+'<caption>select * from dbo.instance_details where is_enabled = 1 and is_available = 0</caption>'
						+'<thead>'+@_table_header+'</thead><tbody>'+isnull(@_table_data,'')+'</tbody></table></div>';

		if @verbose > 0
		begin
			print @_tab+'@_table_header => '+@_crlf+@_table_header;
			print @_tab+@_line;
			print @_tab+'@_table_data => '+@_crlf+ISNULL(@_table_data,'');
			print @_tab+@_line;
			print @_tab+'@_html_offline_servers => '+@_crlf+ISNULL(@_html_offline_servers,'');
		end
	end -- 'Offline Servers'

	if(@collect_sqlmonitor_jobs = 1) -- 'SQLMonitor Jobs'
	begin
		if @verbose > 0
		begin
			print @_line;
			print @_line;
			print 'Set @_html_sqlmonitor_jobs variable..';
			print @_tab+@_line;
		end

		set @_table_headline = N'<h3><a href="'+@_url_sqlmonitor_jobs_panel+'" target="_blank">All Servers - SQLMonitor Jobs - Require ATTENTION</a></h3>';
		set @_table_header = N'<tr><th>Collection Time</th> <th>Server</th> <th>Job Name</th>'
						+N'<th>Execution Delay</th> <th>Last Run</th> <th>Last Duration</th>'
						+N'<th>Last Outcome</th> <th>Success Clocktime</th>'
						+N'<th>Last Successful Time</th>'
		set @_table_data = NULL;

		if not exists (select * from dbo.sql_agent_jobs_all_servers)
			print 'Data does not exist in dbo.sql_agent_jobs_all_servers';

		if @verbose > 1
		begin
			;with t_cte as (
				select	top 10000000
						[CollectionTimeUTC] = [UpdatedDateUTC],
						[sql_instance], [JobName],
						[Job-Delay-Minutes] = case when sj.Last_Successful_ExecutionTime is null then 10080 else datediff(minute, sj.Last_Successful_ExecutionTime, dateadd(minute,-(sj.Successfull_Execution_ClockTime_Threshold_Minutes+@buffer_time_minutes),getutcdate())) end,
						 [Last_RunTime], [Last_Run_Duration_Seconds], [Last_Run_Outcome], 
						 [Successfull_Execution_ClockTime_Threshold_Minutes], 
						 [Last_Successful_ExecutionTime]
				from dbo.sql_agent_jobs_all_servers sj
				where 1=1
				and exists (select 1/0 from dbo.instance_details id where id.sql_instance = sj.sql_instance and id.is_enabled = 1)
				and sj.JobCategory = '(dba) SQLMonitor'
				and sj.JobName like '(dba) %'
				and sj.IsDisabled = 0
				and (	dateadd(minute,-(sj.Successfull_Execution_ClockTime_Threshold_Minutes+@buffer_time_minutes),getutcdate()) > sj.Last_Successful_ExecutionTime
							or sj.Last_Successful_ExecutionTime is null
						)
				order by [Last_Successful_ExecutionTime]
			)
			select [RunningQuery], t_cte.*
			from t_cte
			full outer join (select [RunningQuery] = 'SQLMonitor Jobs') rq
				on 1=1;
		end

		;with tsu as (
			select	top 1000000
					[CollectionTimeUTC] = [UpdatedDateUTC],
					[sql_instance], [JobName],
					[Job-Delay-Minutes] = case when sj.Last_Successful_ExecutionTime is null then 10080 else datediff(minute, sj.Last_Successful_ExecutionTime, dateadd(minute,-(sj.Successfull_Execution_ClockTime_Threshold_Minutes+@buffer_time_minutes),getutcdate())) end,
					[Last_RunTime], [Last_Run_Duration_Seconds], [Last_Run_Outcome], 
					[Successfull_Execution_ClockTime_Threshold_Minutes], 
					[Last_Successful_ExecutionTime]
			from dbo.sql_agent_jobs_all_servers sj
			where 1=1
			and exists (select 1/0 from dbo.instance_details id where id.sql_instance = sj.sql_instance and id.is_enabled = 1)
			and sj.JobCategory = '(dba) SQLMonitor'
			and sj.JobName like '(dba) %'
			and sj.IsDisabled = 0
			and (	dateadd(minute,-(sj.Successfull_Execution_ClockTime_Threshold_Minutes+@buffer_time_minutes),getutcdate()) > sj.Last_Successful_ExecutionTime
						or sj.Last_Successful_ExecutionTime is null
					)
			order by [Last_Successful_ExecutionTime]
		)
		,t_cte as (
			select	'<tr>'
					+'<td class="bg_metric_neutral">'+convert(varchar,DATEADD(mi, DATEDIFF(mi, GETUTCDATE(), GETDATE()), CollectionTimeUTC),120)+'</td>'
					+'<td class="bg_key">'+sql_instance+'</td>'
					+'<td class="bg_key">'+JobName+'</td>'
					+'<td class="'+(case when [Job-Delay-Minutes] >= 120 then 'bg_red'
									when [Job-Delay-Minutes] >= 60 then 'bg_orange'
									when [Job-Delay-Minutes] >= 30 then 'bg_yellow'
									else 'bg_none'
									end)+'">'
						+isnull((case when [Job-Delay-Minutes] < 60 then convert(varchar,floor([Job-Delay-Minutes]))+' min'
									when [Job-Delay-Minutes] < 60*24 then convert(varchar,floor([Job-Delay-Minutes]/60))+' hrs'
									when [Job-Delay-Minutes] >= 60*24 then convert(varchar,floor([Job-Delay-Minutes]/(60*24)))+' days'
									else convert(varchar,[Job-Delay-Minutes]) end),'')+'</td>'
					+'<td>'+convert(varchar,Last_RunTime,120)+'</td>'
					+'<td>'+isnull((case when Last_Run_Duration_Seconds < 60 then convert(varchar,floor(Last_Run_Duration_Seconds))+' sec'
							when Last_Run_Duration_Seconds < 3600 then convert(varchar,floor(Last_Run_Duration_Seconds/60))+' min'
							when Last_Run_Duration_Seconds < 86400 then convert(varchar,floor(Last_Run_Duration_Seconds/3600))+' hrs'
							when Last_Run_Duration_Seconds >= 86400 then convert(varchar,floor(Last_Run_Duration_Seconds/86400))+' days'
							else convert(varchar,Last_Run_Duration_Seconds) end),'')+'</td>'
					+'<td class="'+(case Last_Run_Outcome
									when 'Failed' then 'bg_red'
									when 'Canceled' then 'bg_orange'
									when 'Success' then 'bg_green'
									else 'bg_none'
									end)+'">'+Last_Run_Outcome+'</td>'
					+'<td>'+isnull((case when Successfull_Execution_ClockTime_Threshold_Minutes < 60 then convert(varchar,floor(Successfull_Execution_ClockTime_Threshold_Minutes))+' min'
									when Successfull_Execution_ClockTime_Threshold_Minutes < 1440 then convert(varchar,floor(Successfull_Execution_ClockTime_Threshold_Minutes/60))+' hrs'
									when Successfull_Execution_ClockTime_Threshold_Minutes >= 86400 then convert(varchar,floor(Successfull_Execution_ClockTime_Threshold_Minutes/1440))+' days'
									else '' end),0)+'</td>'
					+'<td>'+convert(varchar,Last_Successful_ExecutionTime,120)+'</td>'
					+'</tr>' as [table_row]
			from tsu
			where 1=1
		)
		--select * from t_cte;
		select @_table_data = coalesce(@_table_data+' '+[table_row],[table_row])
		from t_cte;

		set @_html_sqlmonitor_jobs = '<hr><br>'+@_table_headline+'<div class="tableContainerDiv"><table border="1">'
						+'<caption>dbo.sql_agent_jobs_all_servers || @buffer_time_minutes:'+convert(varchar,@buffer_time_minutes)
						+'</caption>'
						+'<thead>'+@_table_header+'</thead><tbody>'+isnull(@_table_data,'')+'</tbody></table></div>';

		if @verbose > 0
		begin
			print @_tab+'@_table_header => '+@_crlf+@_table_header;
			print @_tab+@_line;
			print @_tab+'@_table_data => '+@_crlf+ISNULL(@_table_data,'');
			print @_tab+@_line;
			print @_tab+'@_html_sqlmonitor_jobs => '+@_crlf+ISNULL(@_html_sqlmonitor_jobs,'');
		end
	end -- 'SQLMonitor Jobs'

	if(@collect_backup_history = 1) -- 'Backup History'
	begin
		if @verbose > 0
		begin
			print @_line;
			print @_line;
			print 'Set @_html_backup_history variable..';
			print @_tab+@_line;
		end

		set @_table_headline = N'<h3><a href="'+@_url_backup_history_panel+'" target="_blank">All Servers - Backup History - Require ATTENTION</a></h3>';
		set @_table_header = N'<th>Server</th> <th>Database</th> <th>Recovery Model</th>'
						+N'<th>Full Delay</th> <th>Diff Delay</th> <th>TLog Delay</th>'
						+N'<th>Full Bkp Time</th> <th>Diff Bkp Time</th> <th>TLog Bkp Time</th>'
						+N'<th>Db Created Date</th>';
		set @_table_data = NULL;

		if not exists (select * from dbo.backups_all_servers)
			raiserror ('Data does not exist in dbo.backups_all_servers', 17, -1) with log;

		if @verbose > 1
		begin
			;with t_backups as (
				select [collection_time_utc], [sql_instance], [database_name], [backup_type], [log_backups_count], [backup_start_date_utc], [backup_finish_date_utc], [latest_backup_location], [backup_size_mb], [compressed_backup_size_mb], [first_lsn], [last_lsn], [checkpoint_lsn], [database_backup_lsn], [database_creation_date_utc], [backup_software], [recovery_model], [compatibility_level], [device_type], [description]
				from dbo.backups_all_servers bas
			)
			,t_pivot as (
				select	[sql_instance], [database_name]
						,[recovery_model] = max([recovery_model])
						,[full_backup_time_utc] = max(case when bkp.[backup_type] = 'Full Database Backup' then bkp.[backup_finish_date_utc] else null end)
						,[full_backup_size_mb] = max(case when bkp.[backup_type] = 'Full Database Backup' then bkp.[backup_size_mb] else null end)
						,[full_compressed_size_mb] = max(case when bkp.[backup_type] = 'Full Database Backup' then bkp.[compressed_backup_size_mb] else null end)
						,[diff_backup_time_utc] = max(case when bkp.[backup_type] = 'Differential database Backup' then bkp.[backup_finish_date_utc] else null end)
						,[diff_backup_size_mb] = max(case when bkp.[backup_type] = 'Differential database Backup' then bkp.[backup_size_mb] else null end)
						,[diff_compressed_size_mb] = max(case when bkp.[backup_type] = 'Differential database Backup' then bkp.[compressed_backup_size_mb] else null end)
						,[tlog_backup_time_utc] = max(case when bkp.[backup_type] = 'Transaction Log Backup' then bkp.[backup_finish_date_utc] else null end)
						,[tlog_backup_size_mb] = max(case when bkp.[backup_type] = 'Transaction Log Backup' then bkp.[backup_size_mb] else null end)
						,[tlog_compressed_size_mb] = max(case when bkp.[backup_type] = 'Transaction Log Backup' then bkp.[compressed_backup_size_mb] else null end)
						,[log_backups_count] = max([log_backups_count])
						,[database_creation_date_utc] = max([database_creation_date_utc])
						,[full_backup_file] = max(case when bkp.[backup_type] = 'Full Database Backup' then bkp.[latest_backup_location] else null end)
						,[diff_backup_file] = max(case when bkp.[backup_type] = 'Differential database Backup' then bkp.[latest_backup_location] else null end)
						,[tlog_backup_file] = max(case when bkp.[backup_type] = 'Transaction Log Backup' then bkp.[latest_backup_location] else null end)
				from t_backups bkp
				where 1=1
				group by [sql_instance], [database_name]
			)
			,t_latency as (
				select 	[sql_instance], [database_name], [recovery_model], 				
						[full_latency_days] = case when [full_backup_time_utc] is null then @full_threshold_days * 10
																			else datediff(day,[full_backup_time_utc],getutcdate())
																			end,						
						[diff_latency_hours] = case when [diff_backup_time_utc] is null 
																				then	case when (datediff(day,[full_backup_time_utc],getutcdate()) > @full_threshold_days) and (@full_threshold_days >= 7)
																										then @full_threshold_days * 24
																										when (datediff(day,[full_backup_time_utc],getutcdate())*24) > @diff_threshold_hours
																										then ( (datediff(day,[full_backup_time_utc],getutcdate())-1) * 24 )
																										else null
																										end
																			else datediff(hour,[diff_backup_time_utc],getutcdate())
																			end,
						[tlog_latency_minutes] = case when recovery_model = 'SIMPLE' then null
																			when recovery_model <> 'SIMPLE'
																			then	case when [tlog_backup_time_utc] is null then @full_threshold_days * 1440
																									when [tlog_backup_time_utc] is not null
																									then datediff(minute,[tlog_backup_time_utc],getutcdate())
																									else null
																									end
																			else null
																			end,
						[full_backup_time_utc], [diff_backup_time_utc], [tlog_backup_time_utc], 
						[full_backup_size_mb], [full_compressed_size_mb], [diff_backup_size_mb], [diff_compressed_size_mb], [tlog_backup_size_mb],
						[tlog_compressed_size_mb], [log_backups_count],
						[database_creation_date_utc], [full_backup_file], [diff_backup_file], [tlog_backup_file]
				from t_pivot as bkp
				where 1=1
			)
			,t_cte as (
				select [sql_instance], [database_name], [recovery_model], 				
						[full_latency_days], [diff_latency_hours], [tlog_latency_minutes],
						[full_backup_time_utc], [diff_backup_time_utc], [tlog_backup_time_utc], 
						[full_backup_size_mb], [full_compressed_size_mb], [diff_backup_size_mb], [diff_compressed_size_mb], 
						[tlog_backup_size_mb], [tlog_compressed_size_mb], [log_backups_count], [database_creation_date_utc], 
						[full_backup_file], [diff_backup_file], [tlog_backup_file]
				from t_latency as l
				where 1=1
				AND (		(full_latency_days is null or full_latency_days >= @full_threshold_days)
						OR 	(diff_latency_hours is not null and diff_latency_hours >= @diff_threshold_hours)
						OR	(tlog_latency_minutes is not null and tlog_latency_minutes >= @tlog_threshold_minutes)
						)
			)
			select [RunningQuery], t_cte.*
			from t_cte
			full outer join (select [RunningQuery] = 'Backup History') rq
				on 1=1;
		end

		;with t_backups as (
			select [collection_time_utc], [sql_instance], [database_name], [backup_type], [log_backups_count], [backup_start_date_utc], [backup_finish_date_utc], [latest_backup_location], [backup_size_mb], [compressed_backup_size_mb], [first_lsn], [last_lsn], [checkpoint_lsn], [database_backup_lsn], [database_creation_date_utc], [backup_software], [recovery_model], [compatibility_level], [device_type], [description]
			from dbo.backups_all_servers bas
		)
		,t_pivot as (
			select	[sql_instance], [database_name]
					,[recovery_model] = max([recovery_model])
					,[full_backup_time_utc] = max(case when bkp.[backup_type] = 'Full Database Backup' then bkp.[backup_finish_date_utc] else null end)
					,[full_backup_size_mb] = max(case when bkp.[backup_type] = 'Full Database Backup' then bkp.[backup_size_mb] else null end)
					,[full_compressed_size_mb] = max(case when bkp.[backup_type] = 'Full Database Backup' then bkp.[compressed_backup_size_mb] else null end)
					,[diff_backup_time_utc] = max(case when bkp.[backup_type] = 'Differential database Backup' then bkp.[backup_finish_date_utc] else null end)
					,[diff_backup_size_mb] = max(case when bkp.[backup_type] = 'Differential database Backup' then bkp.[backup_size_mb] else null end)
					,[diff_compressed_size_mb] = max(case when bkp.[backup_type] = 'Differential database Backup' then bkp.[compressed_backup_size_mb] else null end)
					,[tlog_backup_time_utc] = max(case when bkp.[backup_type] = 'Transaction Log Backup' then bkp.[backup_finish_date_utc] else null end)
					,[tlog_backup_size_mb] = max(case when bkp.[backup_type] = 'Transaction Log Backup' then bkp.[backup_size_mb] else null end)
					,[tlog_compressed_size_mb] = max(case when bkp.[backup_type] = 'Transaction Log Backup' then bkp.[compressed_backup_size_mb] else null end)
					,[log_backups_count] = max([log_backups_count])
					,[database_creation_date_utc] = max([database_creation_date_utc])
					,[full_backup_file] = max(case when bkp.[backup_type] = 'Full Database Backup' then bkp.[latest_backup_location] else null end)
					,[diff_backup_file] = max(case when bkp.[backup_type] = 'Differential database Backup' then bkp.[latest_backup_location] else null end)
					,[tlog_backup_file] = max(case when bkp.[backup_type] = 'Transaction Log Backup' then bkp.[latest_backup_location] else null end)
			from t_backups bkp
			where 1=1
			group by [sql_instance], [database_name]
		)
		,t_latency as (
			select 	[sql_instance], [database_name], [recovery_model], 				
					[full_latency_days] = case when [full_backup_time_utc] is null then @full_threshold_days * 10
																		else datediff(day,[full_backup_time_utc],getutcdate())
																		end,						
					[diff_latency_hours] = case when [diff_backup_time_utc] is null 
																			then	case when (datediff(day,[full_backup_time_utc],getutcdate()) > @full_threshold_days) and (@full_threshold_days >= 7)
																									then @full_threshold_days * 24
																									when (datediff(day,[full_backup_time_utc],getutcdate())*24) > @diff_threshold_hours
																									then ( (datediff(day,[full_backup_time_utc],getutcdate())-1) * 24 )
																									else null
																									end
																		else datediff(hour,[diff_backup_time_utc],getutcdate())
																		end,
					[tlog_latency_minutes] = case when recovery_model = 'SIMPLE' then null
																		when recovery_model <> 'SIMPLE'
																		then	case when [tlog_backup_time_utc] is null then @full_threshold_days * 1440
																								when [tlog_backup_time_utc] is not null
																								then datediff(minute,[tlog_backup_time_utc],getutcdate())
																								else null
																								end
																		else null
																		end,
					[full_backup_time_utc], [diff_backup_time_utc], [tlog_backup_time_utc], 
					[full_backup_size_mb], [full_compressed_size_mb], [diff_backup_size_mb], [diff_compressed_size_mb], [tlog_backup_size_mb],
					[tlog_compressed_size_mb], [log_backups_count],
					[database_creation_date_utc], [full_backup_file], [diff_backup_file], [tlog_backup_file]
			from t_pivot as bkp
			where 1=1
		)
		,t_issues as (
			select [sql_instance], [database_name], [recovery_model], 				
					[full_latency_days], [diff_latency_hours], [tlog_latency_minutes],
					[full_backup_time_utc], [diff_backup_time_utc], [tlog_backup_time_utc], 
					[full_backup_size_mb], [full_compressed_size_mb], [diff_backup_size_mb], [diff_compressed_size_mb], 
					[tlog_backup_size_mb], [tlog_compressed_size_mb], [log_backups_count], [database_creation_date_utc], 
					[full_backup_file], [diff_backup_file], [tlog_backup_file]
			from t_latency as l
			where 1=1
			AND (		(full_latency_days is null or full_latency_days >= @full_threshold_days)
					OR 	(diff_latency_hours is not null and diff_latency_hours >= @diff_threshold_hours)
					OR	(tlog_latency_minutes is not null and tlog_latency_minutes >= @tlog_threshold_minutes)
					)
		)
		,t_cte as (
			select	'<tr>'
					--+'<td class="bg_metric_neutral">'+convert(varchar,DATEADD(mi, DATEDIFF(mi, GETUTCDATE(), GETDATE()), CollectionTimeUTC),120)+'</td>'
					+'<td class="bg_key">'+sql_instance+'</td>'
					+'<td class="bg_key">'+[database_name]+'</td>'
					+'<td class="bg_key">'+isnull(recovery_model,'')+'</td>'
					+'<td class="'+(case when full_latency_days >= (@full_threshold_days*2) then 'bg_red'
									when full_latency_days >= (@full_threshold_days+2) then 'bg_orange'
									when full_latency_days >= (@full_threshold_days) then 'bg_yellow'
									else 'bg_none'
									end)+'">'+isnull(convert(varchar,full_latency_days),'')+' days'+'</td>'
					+'<td class="'+(case when diff_latency_hours >= (@diff_threshold_hours*2) then 'bg_red'
									when diff_latency_hours >= (@diff_threshold_hours+2) then 'bg_orange'
									when diff_latency_hours >= (@diff_threshold_hours) then 'bg_yellow'
									else 'bg_none'
									end)+'">'
						+isnull((case when diff_latency_hours < 24 then convert(varchar,floor(diff_latency_hours))+' hrs'
									when diff_latency_hours >= 24 then convert(varchar,convert(numeric(20,2),diff_latency_hours/24))+' days'
									else convert(varchar,diff_latency_hours) end),'')+'</td>'
					+'<td class="'+(case when tlog_latency_minutes >= (@tlog_threshold_minutes*2) then 'bg_red'
									when tlog_latency_minutes >= (@tlog_threshold_minutes+2) then 'bg_orange'
									when tlog_latency_minutes >= (@tlog_threshold_minutes) then 'bg_yellow'
									else 'bg_none'
									end)+'">'
						+isnull((case when tlog_latency_minutes < 60 then convert(varchar,floor(tlog_latency_minutes))+' min'
									when tlog_latency_minutes < 60*24 then convert(varchar,convert(numeric(20,2),tlog_latency_minutes/60))+' hrs'
									when tlog_latency_minutes >= 60*24 then convert(varchar,convert(numeric(20,2),tlog_latency_minutes/(60*24)))+' days'
									else convert(varchar,tlog_latency_minutes) end),'')+'</td>'
					+'<td>'+isnull(convert(varchar,DATEADD(mi, DATEDIFF(mi, GETUTCDATE(), GETDATE()), full_backup_time_utc),120),'')+'</td>'
					+'<td>'+isnull(convert(varchar,DATEADD(mi, DATEDIFF(mi, GETUTCDATE(), GETDATE()), diff_backup_time_utc),120),'')+'</td>'
					+'<td>'+isnull(convert(varchar,DATEADD(mi, DATEDIFF(mi, GETUTCDATE(), GETDATE()), tlog_backup_time_utc),120),'')+'</td>'
					+'<td>'+isnull(convert(varchar,DATEADD(mi, DATEDIFF(mi, GETUTCDATE(), GETDATE()), database_creation_date_utc),120),'')+'</td>'
					+'</tr>' as [table_row]
			from t_issues bi
			where 1=1
		)
		--select * from t_cte;
		select @_table_data = coalesce(@_table_data+' '+[table_row],[table_row])
		from t_cte;

		set @_html_backup_history = '<hr><br>'+@_table_headline+'<div class="tableContainerDiv"><table border="1">'
						+'<caption>dbo.backups_all_servers || @full_threshold_days:'+convert(varchar,@full_threshold_days)
							+' || @diff_threshold_hours:'+convert(varchar,@diff_threshold_hours)
							+' || @tlog_threshold_minutes:'+convert(varchar,@tlog_threshold_minutes)
						+'</caption>'
						+'<thead>'+@_table_header+'</thead><tbody>'+isnull(@_table_data,'')+'</tbody></table></div>';

		if @verbose > 0
		begin
			print @_tab+'@_table_header => '+@_crlf+@_table_header;
			print @_tab+@_line;
			print @_tab+'@_table_data => '+@_crlf+ISNULL(@_table_data,'');
			print @_tab+@_line;
			print @_tab+'@_html_backup_history => '+@_crlf+ISNULL(@_html_backup_history,'');
		end
	end -- 'Backup History'

	set @mail_subject = @mail_subject+' - '+convert(varchar,@_collection_time,120);

	set @_mail_body_html = '<html>'
						+N'<head>'
						+N'<title>'+@_title+'</title>'
						+@_style_css
						+N'</head>'
						+N'<body>'
						+N'<h1><a href="'+@_url_all_servers_dashboard+'" target="_blank">'+@_title+' - '+convert(varchar,@_collection_time,120)+'</a></h1>'
						+(case when @collect_core_health_metrics = 1 then N'<p>'+@_html_core_health+'</p>' else '' end)
						+(case when @collect_tempdb_health = 1 then N'<p>'+@_html_tempdb_health+'</p>' else '' end)
						+(case when @collect_log_space = 1 then N'<p>'+@_html_log_space_health+'</p>' else '' end)
						+(case when @collect_ag_latency = 1 then N'<p>'+@_html_ag_health+'</p>' else '' end)
						+(case when @collect_disk_space = 1 then N'<p>'+@_html_disk_health+'</p>' else '' end)
						+(case when @collect_offline_servers = 1 then N'<p>'+@_html_offline_servers+'</p>' else '' end)
						+(case when @collect_sqlmonitor_jobs = 1 then N'<p>'+@_html_sqlmonitor_jobs+'</p>' else '' end)
						+(case when @collect_backup_history = 1 then N'<p>'+@_html_backup_history+'</p>' else '' end)
						+N'<br><br><br><p>Regards,<br>Job ['+@job_name+']</p>'
						+N'</body>';	

	if @verbose > 0
	begin
		print @_line;
		print '@_mail_body_html => '+@_crlf+@_mail_body_html;
		print @_line;
	end

	if @send_mail =1
	begin
		exec msdb.dbo.sp_send_dbmail @recipients = @recipients,
			@subject = @mail_subject,
			@body = @_mail_body_html,
			@body_format = 'HTML';
	end	
END
GO

if APP_NAME() = 'Microsoft SQL Server Management Studio - Query'
	EXEC dbo.usp_GetAllServerDashboardMail 
			@recipients = 'ajay.dwivedi2007@gmail.com;',
			@dashboard_link = 'https://sqlmonitor.ajaydwivedi.com:3000/d/',
			@collect_offline_servers = 1, @collect_sqlmonitor_jobs = 1,
			@collect_disk_space = 1,
			@only_threshold_validated = 1, @send_mail = 1, @verbose = 2
go