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
declare @duration int;

set @database = case when ltrim(rtrim(@database)) = '__All__' then null else @database end;
set @duration = case when ltrim(rtrim('$duration')) <> '' then $duration else 0 end;
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
				@session_id int, @session_host_name nvarchar(125), @query_pattern nvarchar(500),
				@duration int';

set quoted_identifier off;
set @sql = "/* SQLMonitor Dashboard $__dashboard: LongRunningQueries  */
set nocount on;			
if exists ( select * from $whoisactive_table_name w with (nolock)
            where w.collection_time = (select max(i.collection_time) from $whoisactive_table_name i with (nolock)) 
            and datediff(minute,start_time,collection_time) >= @duration )
begin
  ;with t_WhoIsActive as (
    select [collection_time], w.session_id, 
        w.program_name, w.login_name, w.database_name, w.host_name,
        w.status, w.CPU, w.used_memory, w.open_tran_count, [duration_s], [duration_ms], cv.days_gap, cv.days_threshold_ms,
        w.wait_info, granted_memory, tempdb_current,
        sql_command = case when w.sql_command is not null then left(replace(replace(convert(nvarchar(max),w.sql_command),char(13)+char(10),''),'<?query --',''),150)
                  else left(replace(replace(convert(nvarchar(max),w.sql_text),char(13)+char(10),''),'<?query --',''),150) end, 
        w.blocked_session_count, w.blocking_session_id, w.reads, w.writes, w.tempdb_allocations, 
        w.tasks, w.percent_complete, start_time = convert(varchar,w.start_time,120)
    from $whoisactive_table_name w with (nolock)
  outer apply (select 	[days_threshold_ms] = 24,
                        [days_gap] = DATEDIFF(DAY, w.start_time, w.collection_time),
						[duration_s] = datediff(second, w.start_time, w.collection_time)
            ) as cv
  outer apply (select 	duration_ms = case when days_gap >= days_threshold_ms then [duration_s]*1000
										else datediff(MILLISECOND, start_time, collection_time)
										end
			) cv2
    where w.collection_time = (select max(i.collection_time) from dbo.WhoIsActive i with (nolock))
    and datediff(minute,start_time,collection_time) >= @duration
    "+(case when @program_name is null then '-- ' else '' end)+"and w.program_name like ('%'+@program_name+'%')
    "+(case when @database is null then '-- ' else '' end)+"and w.database_name like ('%'+@database+'%')
    "+(case when @login_name is null then '-- ' else '' end)+"and w.login_name like ('%'+@login_name+'%')
    "+(case when @session_host_name is null then '-- ' else '' end)+"and w.host_name like ('%'+@session_host_name+'%')
    "+(case when @query_pattern is null then '-- ' else '' end)+"and w.sql_command like ('%'+@query_pattern+'%')
    "+(case when @session_id is null then '-- ' else '' end)+"and w.session_id like ('%'+@session_id+'%')
  )
  select [collection_time] = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), [collection_time]), w.session_id,
          --[ddd hh:mm:ss.mss] = right('0000'+convert(varchar, duration_ms/86400000),3)+ ' '+convert(varchar,dateadd(MILLISECOND,duration_ms,'1900-01-01 00:00:00'),114), 
          [dd hh:mm:ss.mss],
          w.program_name, w.login_name, w.database_name, w.host_name, w.status, w.CPU, 
          granted_memory_kb = (w.granted_memory * 8.0), w.open_tran_count, w.wait_info, w.sql_command, w.blocked_session_count, 
          w.blocking_session_id, [reads_kb] = (w.[reads]*8.0), w.writes, [tempdb_allocations_kb] = (w.tempdb_allocations*8.0), 
          tempdb_current_kb = (tempdb_current*8.0), w.tasks, w.percent_complete, [used_memory_kb] = (w.used_memory*8.0),
          start_time = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), [start_time])
  from t_WhoIsActive w
cross apply (   select [dd hh:mm:ss.mss] = case when w.days_gap >= w.days_threshold_ms
                                                then right('   0'+convert(varchar, duration_s/86400),4)+ ' '+convert(varchar,dateadd(SECOND,duration_s,'1900-01-01 00:00:00'),114)
                                                else right('   0'+convert(varchar, duration_s/86400),4)+ ' '+convert(varchar,dateadd(MILLISECOND,duration_ms,'1900-01-01 00:00:00'),114)
                                                end

            ) cv2
  order by w.collection_time DESC, w.start_time ASC
end
ELSE
  select 'No long running query found for time window' as [No Result]
"
set quoted_identifier on;
--print @sql

--if (@sql_instance = SERVERPROPERTY('SERVERNAME'))
if ($is_local = 1)
  exec dbo.sp_executesql @sql, @params, @perfmon_host_name, @start_time_utc, @end_time_utc, 
					@program_name, @login_name, @database, @session_id, @session_host_name, 
					@query_pattern, @duration;
else
  exec [$server].[$dba_db].dbo.sp_executesql @sql, @params, @perfmon_host_name, @start_time_utc, @end_time_utc,
					@program_name, @login_name, @database, @session_id, @session_host_name, 
					@query_pattern, @duration;