declare @sql nvarchar(max);
declare @params nvarchar(max);
declare @sql_instance varchar(255);
declare @perfmon_host_name varchar(255);
declare @start_time_utc datetime2;
declare @end_time_utc datetime2;
declare @crlf nchar(2) = nchar(13)+nchar(10);

--declare @delta_minutes int;
declare @program_name nvarchar(500);
declare @login_name nvarchar(255);
declare @database nvarchar(500) = '$database';
declare @session_id int;
declare @session_host_name nvarchar(125);
declare @query_pattern nvarchar(500);

set @database = case when ltrim(rtrim(@database)) = '__All__' then null else @database end;
if len(ltrim(rtrim('$program_name'))) > 0
  set @program_name = '$program_name'
if len(ltrim(rtrim('$login_name'))) > 0
  set @login_name = '$login_name'
if len(ltrim(rtrim('$session_host_name'))) > 0
  set @session_host_name = '$session_host_name'
if len(ltrim(rtrim('$query_pattern'))) > 0
  set @query_pattern = '$query_pattern'
if len(ltrim(rtrim('$session_id'))) > 0 and (case when '$session_id' like '%[^0-9.]%' then 'invalid' when '$session_id' like '%.%.%' then 'invalid' else 'valid' end) = 'valid'
  set @session_id = convert(int,'$session_id');

set @sql_instance = '$server';
--set @perfmon_host_name = '$perfmon_host_name';
set @start_time_utc = $__timeFrom();
--set @start_time_utc = dateadd(second,$sqlserver_start_time_utc/1000,'1970-01-01 00:00:00');
set @end_time_utc = $__timeTo();
--set @end_time_utc = $__timeFrom();
--set @delta_minutes = $cpu_delta_minutes;
set @params = N'@perfmon_host_name varchar(255), @start_time_utc datetime2, @end_time_utc datetime2,
				@program_name nvarchar(500), @login_name nvarchar(255), @database nvarchar(500),
				@session_id int, @session_host_name nvarchar(125), @query_pattern nvarchar(500)';

set quoted_identifier off;
set @sql = "
set nocount on;	

;with cte_sessions as (
  select [collection_time], w.session_id, 
  		w.program_name, w.login_name, w.database_name, w.host_name, granted_memory, tempdb_current,
  		w.status, w.CPU, w.used_memory, w.open_tran_count, command = additional_info.value('(/additional_info/command_type)[1]','varchar(125)'),
  		w.wait_info, [duration_s], [duration_ms], days_threshold_ms, days_gap,
  		sql_command = case when w.sql_command is not null then left(replace(replace(convert(nvarchar(max),w.sql_command),char(13)+char(10),''),'<?query --',''),150)
  							else left(replace(replace(convert(nvarchar(max),w.sql_text),char(13)+char(10),''),'<?query --',''),150) end, 
  		w.blocked_session_count, 
  		w.blocking_session_id, w.reads, w.writes, w.tempdb_allocations, 
  		w.tasks, w.percent_complete, start_time = convert(varchar,w.start_time,120)
  from $whoisactive_table_name w with (nolock)
  outer apply (select 	[days_threshold_ms] = 24,
                        [days_gap] = DATEDIFF(DAY, w.start_time, w.collection_time),
						[duration_s] = datediff(second, start_time, collection_time)
            ) cv
  outer apply (select 	duration_ms = case when days_gap >= days_threshold_ms then [duration_s]*1000
										else datediff(MILLISECOND, start_time, collection_time)
										end
			) cv2
  where w.collection_time = (select top 1 i.collection_time from $whoisactive_table_name i with (nolock)order by i.collection_time desc)
)
select [collection_time] = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), [collection_time]), w.session_id,
          --[dd hh:mm:ss.mss] = right('0000'+convert(varchar, duration_ms/86400000),3)+ ' '+convert(varchar,dateadd(MILLISECOND,duration_ms,'1900-01-01 00:00:00'),114), 
					[dd hh:mm:ss.mss],
          w.program_name, w.login_name, w.database_name, w.host_name, w.status, w.CPU, 
          granted_memory_kb = (w.granted_memory * 8.0), w.open_tran_count, w.wait_info, w.sql_command, w.blocked_session_count, 
          w.blocking_session_id, [reads_kb] = (w.[reads]*8.0), w.writes, [tempdb_allocations_kb] = (w.tempdb_allocations*8.0), 
          tempdb_current_kb = (tempdb_current*8.0), w.tasks, w.percent_complete, [used_memory_kb] = (w.used_memory*8.0),
          start_time = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), [start_time])	
from cte_sessions w
cross apply (   select [dd hh:mm:ss.mss] = case when w.days_gap >= w.days_threshold_ms
                                                then right('   0'+convert(varchar, duration_s/86400),4)+ ' '+convert(varchar,dateadd(SECOND,duration_s,'1900-01-01 00:00:00'),114)
                                                else right('   0'+convert(varchar, duration_s/86400),4)+ ' '+convert(varchar,dateadd(MILLISECOND,duration_ms,'1900-01-01 00:00:00'),114)
                                                end

            ) cv2
where 1 = 1"

if @program_name is not null
	set @sql = @sql + @crlf + "and w.program_name like ('%'+@program_name+'%')"
if @database is not null
	set @sql = @sql + @crlf + "and w.database_name like ('%'+@database+'%')"
if @login_name is not null
	set @sql = @sql + @crlf + "and w.login_name like ('%'+@login_name+'%')"
if @session_host_name is not null
	set @sql = @sql + @crlf + "and w.host_name like ('%'+@session_host_name+'%')"
if @query_pattern is not null
	set @sql = @sql + @crlf + "and w.sql_command like ('%'+@query_pattern+'%')"
if @session_id is not null
	set @sql = @sql + @crlf + "and w.session_id = @session_id"
set @sql = @sql + @crlf + "order by w.collection_time DESC, w.start_time ASC";

set quoted_identifier on;
--print @sql

--if (@sql_instance = SERVERPROPERTY('SERVERNAME'))
if ($is_local = 1)
  exec dbo.sp_executesql @sql, @params, @perfmon_host_name, @start_time_utc, @end_time_utc, 
					@program_name, @login_name, @database, @session_id, @session_host_name, @query_pattern;
else
  exec [$server].[$dba_db].dbo.sp_executesql @sql, @params, @perfmon_host_name, @start_time_utc, @end_time_utc,
					@program_name, @login_name, @database, @session_id, @session_host_name, @query_pattern;