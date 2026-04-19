-- !------------------------------------------------------------------------------------------------!
-- !~~~~ IMPORTANT - USE BELOW CODE TO FIND TABLES NOT PRESENT IN dbo.purge table for Purging ~~~~~~!
-- !------------------------------------------------------------------------------------------------!
declare @_table_name varchar(500);
declare @_sql nvarchar(max);

if OBJECT_ID('tempdb..#tables') is not null drop table #tables;
create table #tables (table_name varchar(500) not null, [rows] bigint not null);
if OBJECT_ID('tempdb..#tables_to_skip') is not null drop table #tables_to_skip;
create table #tables_to_skip (table_name varchar(500) not null);

insert #tables_to_skip
select table_name
from ( values ('dbo.BlitzFirst_WaitStats_Categories'),
		('dbo.sql_agent_job_stats'),
		('dbo.sql_agent_jobs_all_servers'),
		('dbo.sql_agent_job_thresholds'),
		('dbo.alert_categories'),
		('dbo.purge_table'),
		('dbo.log_space_consumers_all_servers'),
		('dbo.tempdb_space_usage_all_servers'),
		('dbo.backups_all_servers'),
		('dbo.disk_space_all_servers'),
		('dbo.instance_details'),
		('dbo.instance_hosts'),
		('dbo.credential_manager'),
		('dbo.credential_manager_history'),
		('dbo.services_all_servers'),
		('dbo.all_server_volatile_info'),
		('dbo.sent_alert_history_all_servers'),
		('dbo.login_email_mapping'),
		('dbo.all_server_login_expiry_info_dashboard'),
		('dbo.all_server_collection_latency_info'),
		('dbo.server_login_expiry_collection_computed'),
		('dbo.ag_health_state_all_servers'),
		('dbo.alert_history_all_servers_last_actioned'),
		('dbo.all_server_stable_info')
	 ) tables_2_skip (table_name);

declare cur_tables cursor local forward_only for
	with cte_user_tables as (
		select table_name = s.name+'.'+t.name from sys.tables t join sys.schemas s on s.schema_id = t.schema_id
		where t.is_ms_shipped = 0
	)
	select ut.table_name
	from cte_user_tables ut
	left join dbo.purge_table pt
	on pt.table_name = ut.table_name
	where 1=1
	and not (	ut.table_name like 'dbo.sma_%'
		or	ut.table_name like '%__staging'
		)
	and ut.table_name not in (select s.table_name from #tables_to_skip s)
	and pt.date_key is null;

open cur_tables;
fetch next from cur_tables into @_table_name;

while @@FETCH_STATUS = 0
begin
	print 'Working on '+quotename(@_table_name)+'..';
	set @_sql = null;

	set @_sql = N'
	select table_name = '''+@_table_name+''', rows = count(*)
	from '+@_table_name+' t
	right join (select [table_name] = '''+@_table_name+''') d
		on 1=1;
	'
	--print @_sql;
	insert #tables (table_name, [rows])
	exec (@_sql);

	fetch next from cur_tables into @_table_name;
end

close cur_tables;
deallocate cur_tables;

select * from #tables order by rows desc;
go
