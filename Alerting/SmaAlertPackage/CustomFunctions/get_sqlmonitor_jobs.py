import pyodbc

def get_sqlmonitor_jobs(sql_connection, logger:None, verbose:bool=False, **kwargs):
    cursor = sql_connection.cursor()

    # Extract parameters
    buffer_time_minutes = kwargs['buffer_time_minutes']

    sql_query = f"""
declare @buffer_time_minutes int = {buffer_time_minutes};
declare @_sql nvarchar(max);
declare @_params nvarchar(max);

set @_params = N'@buffer_time_minutes int';
set quoted_identifier off;
set @_sql = "
select	/* {__name__} */ sj.[sql_instance], [JobName],
		[Job-Delay] = case 	when sj.Last_Successful_ExecutionTime is null then (sj.Successfull_Execution_ClockTime_Threshold_Minutes+@buffer_time_minutes) 
									else datediff(minute,sj.Last_Successful_ExecutionTime,getutcdate())
									end,
		--[Last_RunTime], [Last_Run_Outcome],
		[Threshold] = [Successfull_Execution_ClockTime_Threshold_Minutes],
		[Success_Time] = DATEADD(mi, DATEDIFF(mi, GETUTCDATE(), GETDATE()), Last_Successful_ExecutionTime),
		--[Successful_Execution_Threshold_Time] = dateadd(minute,-(sj.Successfull_Execution_ClockTime_Threshold_Minutes+@buffer_time_minutes),getutcdate()),
        [state] = case  when datediff(minute,sj.Last_Successful_ExecutionTime,getutcdate()) > 3*Successfull_Execution_ClockTime_Threshold_Minutes then 'Critical'
                        when datediff(minute,sj.Last_Successful_ExecutionTime,getutcdate()) > 2*Successfull_Execution_ClockTime_Threshold_Minutes then 'High'
						else 'Warning'
						end,
		[Collection Time] = DATEADD(mi, DATEDIFF(mi, GETUTCDATE(), GETDATE()), [UpdatedDateUTC])
from dbo.sql_agent_jobs_all_servers sj
inner join dbo.services_all_servers sas
	on sas.sql_instance = sj.sql_instance
	and sas.service_type = 'Agent'
	and sas.status_desc = 'Running'
where 1=1
and exists (select 1/0 from dbo.instance_details id where id.sql_instance = sj.sql_instance and id.is_enabled = 1)
and sj.JobCategory = '(dba) SQLMonitor'
and sj.JobName like '(dba) %'
and sj.IsDisabled = 0
and (	isnull(sj.Last_Successful_ExecutionTime,sj.Last_RunTime) < dateadd(minute,-(sj.Successfull_Execution_ClockTime_Threshold_Minutes+@buffer_time_minutes),getutcdate())
		and (sj.Last_Successful_ExecutionTime is not null or sj.Last_RunTime is not null)
	)
--order by Last_Run_Outcome
"
set quoted_identifier off;

exec sp_executesql @_sql, @_params, @buffer_time_minutes;
"""
    if verbose:
        logger.info(f"following query is being executed inside {__name__}()..")
        print(sql_query)

    cursor.execute(sql_query)
    sql_query_resultset = cursor.fetchall()
    return sql_query_resultset

