import pyodbc

def get_nonag_db_backup_issue(sql_connection, logger:None, verbose:bool=False, **kwargs):
    cursor = sql_connection.cursor()

    # Extract parameters
    full_threshold_days = kwargs['full_threshold_days']
    diff_threshold_hours = kwargs['diff_threshold_hours']
    tlog_threshold_minutes = kwargs['tlog_threshold_minutes']

    sql_query = f"""
declare @sql nvarchar(max);
declare @params nvarchar(max);
declare @full_threshold_days int = {full_threshold_days};
declare @diff_threshold_hours int = {diff_threshold_hours};
declare @tlog_threshold_minutes int = {tlog_threshold_minutes};

set @params = N'@full_threshold_days int, @diff_threshold_hours int, @tlog_threshold_minutes int';

set quoted_identifier off;
set @sql = "
set nocount on;
;with t_backups as ( /* {__name__} */
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
			select 	[sql_instance], [database_name], recovery_model,
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
select [sql_instance], [database_name], --[rev_model] = recovery_model, [create_dt] = database_creation_date_utc,
        [full_latency] = full_latency_days, [diff_latency] = diff_latency_hours, [tlog_latency] = tlog_latency_minutes,
        [state] = 'Critical'
        --[full_backup_time_utc], [diff_backup_time_utc], [tlog_backup_time_utc],
        --[full_backup_size_mb], [full_compressed_size_mb], [diff_backup_size_mb], [diff_compressed_size_mb],
        --[tlog_backup_size_mb], [tlog_compressed_size_mb], [log_backups_count],
        --[full_backup_file], [diff_backup_file], [tlog_backup_file]
from t_latency as l
where 1=1
AND (		(full_latency_days is null or full_latency_days >= @full_threshold_days)
		OR 	(diff_latency_hours is not null and diff_latency_hours >= @diff_threshold_hours)
		OR	(tlog_latency_minutes is not null and tlog_latency_minutes >= @tlog_threshold_minutes)
		)
and exists (select * from dbo.sma_servers s where s.is_decommissioned = 0 and s.is_onboarded = 1 and s.server = l.sql_instance and (s.hadr_strategy is null or s.hadr_strategy <> 'ag'))
"
set quoted_identifier on;

exec dbo.sp_executesql @sql, @params, @full_threshold_days, @diff_threshold_hours, @tlog_threshold_minutes;
"""
    if verbose:
        logger.info(f"following query is being executed inside {__name__}()..")
        print(sql_query)

    cursor.execute(sql_query)
    sql_query_resultset = cursor.fetchall()
    return sql_query_resultset

