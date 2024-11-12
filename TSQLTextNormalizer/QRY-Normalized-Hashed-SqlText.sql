use [DBA]
go

/*
	1) Create function 
			\SQLMonitor\DDLs\SCH-fn_get_hash_for_string.sql in [DBA] database
	2) Create CLR function 
			\SQLMonitor\TSQLTextNormalizer\SCH-Assembly-[SQLMonitorAssembly].sql
	3) Create procedure 
			\SQLMonitor\DDLs\SCH-usp_collect_xevents_xevent_metrics_hashed
	4) Change Job [(dba) Collect-XEvents] to use [usp_collect_xevents_xevent_metrics_hashed]
*/
go

;with xevent_metrics as (
	select *,[sql_text_ripped] = case when ltrim(rc.sql_text) like 'exec sp_executesql @statement=N%' 
									then substring(ltrim(rtrim(rc.sql_text)),33,len(ltrim(rtrim(rc.sql_text)))-33)
									when ltrim(rc.sql_text) like 'exec sp_executesql%' 
									then substring(ltrim(rtrim(rc.sql_text)),22,len(ltrim(rtrim(rc.sql_text)))-22)
									else rc.sql_text
									end
	from dbo.vw_xevent_metrics rc
	where rc.sql_text like '%Posts%'
	and rc.event_time >= dateadd(day,-7,getdate())
)
select top 1000 hs.sqlsig, 
		hash_counts = count(rc.session_id)over(partition by hs.sqlsig), 
		sql_handle_counts = count(rc.session_id)over(partition by rc.sql_text),
		rc.sql_text, rc.sql_text_ripped,
		rc.*
--update rc set query_hash = hs.sqlsig
from xevent_metrics rc
outer apply (select sqlsig = hs.varbinary_value
			from dbo.fn_get_hash_for_string(dbo.normalized_sql_text(rc.[sql_text_ripped],130,0)) hs  
			) hs
where 1=1
--and rc.start_time between '2022-12-06 00:00' and '2022-12-16 16:00'
--and rc.username = 'grafana'
order by hash_counts desc, rc.sql_text, hs.sqlsig
--order by rc.start_time, rc.event_time
go

-- dbo.fn_get_hash_for_string('EXEC dbo.usp_run_WhoIsActive @recipients = ''sqlagentservice@gmail.com'';')
-- select sqlsig = DBA.dbo.normalized_sql_text('exec sp_WhoIsActive 110',150,0)
go

select *
from dbo.xevent_metrics rc
where 1=1
and rc.event_time >= dateadd(MINUTE,-10,getdate())
go

/*	Update existing records with Hash */
while exists (select 1 from dbo.xevent_metrics where query_hash is null and result = 'OK')
begin
	update top (3000) rc set query_hash = hs.sqlsig
	from dbo.xevent_metrics rc
	cross apply (select sqlsig = hs.varbinary_value
				from dbo.fn_get_hash_for_string(dbo.normalized_sql_text(rc.sql_text,150,0)) hs  
				) hs
	where 1=1
	and result = 'OK'
	and rc.query_hash is null
	option (maxrecursion 0);
end
go
