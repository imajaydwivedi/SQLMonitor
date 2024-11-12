EXEC sp_WhoIsActive @get_outer_command = 1, @get_task_info=2, @get_additional_info=1, @get_memory_info = 1 --,@get_avg_time=1,
					,@find_block_leaders=1
					--,@get_transaction_info=1
					--,@get_full_inner_text=1
					--,@get_locks=1
					,@get_plans=1
					--,@sort_order = '[CPU] DESC'
					--,@filter = 201
					--,@filter_type = 'login' ,@filter = 'grafana'
					--,@filter_type = 'program' ,@filter = 'facebook.py'
					--,@filter_type = 'database' ,@filter = 'StackOverflow'
					--,@filter_type = 'host' ,@filter = 'SQLMonitor'
					--,@show_sleeping_spids = 1
					--,@sort_order = '[used_memory] desc, [start_time]'
					--,@sort_order = '[blocked_session_count] desc, [granted_memory] desc, [start_time]'
					,@output_column_list = '[dd hh:mm:ss.mss][session_id][sql_text][query_plan][sql_command][login_name][wait_info][status][blocked_session_count][blocking_session_id][tasks][CPU][reads][used_memory][granted_memory][host_name][database_name][program_name][open_tran_count][start_time][%]'

/*	Enable LIVE Query Plans
DBCC TRACESTATUS(7412);
DBCC TRACEON(7412, -1);
DBCC TRACEOFF(7412, -1);

exec sp_BlitzWho @GetLiveQueryPlan=1

--Get the execution plan and current progress for session 159
select * from sys.dm_exec_query_statistics_xml(159);
*/

--kill 814 with statusonly
--EXEC sp_WhoIsActive @get_outer_command = 1, @get_task_info=2, @get_locks=1

-- EXEC sp_WhoIsActive  @delta_interval = 5

--	exec sp_WhoIsActive @help = 1

/*
select [ddd hh:mm:ss:mss] = right('   0'+convert(varchar, datediff(second,w.start_time,w.collection_time)/86400),4)+ ' '+convert(varchar,dateadd(SECOND,datediff(second,w.start_time,w.collection_time),'1900-01-01 00:00:00'),114), *
from dbo.WhoIsActive w
where w.collection_time between '2024-01-12 09:00' and '2024-01-12 14:30'
*/