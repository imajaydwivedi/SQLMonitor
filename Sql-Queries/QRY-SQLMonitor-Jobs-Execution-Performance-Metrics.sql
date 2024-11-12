use DBA
go

select	xm.start_time, xm.event_time, 
		[job_name] = case when client_app_name like '(dba) %' then client_app_name else xm.client_hostname end, 
		xm.database_name, xm.sql_text,
		xm.duration_seconds, xm.cpu_time_ms, xm.logical_reads,
		xm.client_app_name, xm.username, xm.client_hostname
from dbo.vw_xevent_metrics xm
where xm.event_time >= dateadd(HOUR,-2,getdate())
and (	xm.client_hostname like '(dba) %'
	or	xm.client_app_name like '(dba) %'
	)
order by event_time desc
