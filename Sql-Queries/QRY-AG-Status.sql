set nocount on;

if object_id('tempdb..#availability_databases') is not null
	drop table #availability_databases;

select	ar.replica_server_name,
		drs.is_primary_replica,
		adc.database_name,
		ag.name AS ag_name,
		drs.is_local,
		ag.is_distributed,
		drs.synchronization_state_desc,
		drs.synchronization_health_desc,
		last_redone_time = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), drs.last_redone_time),
		drs.log_send_queue_size,
		drs.log_send_rate,
		drs.redo_queue_size,
		drs.redo_rate,
		[estimated_redo_completion_time_min] = case when drs.redo_rate <> 0 then (drs.redo_queue_size / drs.redo_rate) / 60.0 else (drs.redo_queue_size / 1) / 60.0 end,
		last_commit_time = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), drs.last_commit_time),
		drs.is_suspended,
		drs.suspend_reason_desc,
		ag.group_id
into #availability_databases
from sys.dm_hadr_database_replica_states as drs
inner join sys.availability_databases_cluster as adc on drs.group_id = adc.group_id
	and drs.group_database_id = adc.group_database_id
inner join sys.availability_groups as ag on ag.group_id = drs.group_id
inner join sys.availability_replicas as ar on drs.group_id = ar.group_id
	and drs.replica_id = ar.replica_id
--order by ag.name, ar.replica_server_name, adc.database_name

select	[collection_time_utc] = SYSUTCDATETIME(),
		replica_server_name,
		is_primary_replica,
		database_name,
		ag_name,
		[ag_listener] = agl.dns_name+' ('+ia.ip_address+')',
		is_local,
		is_distributed,
		synchronization_state_desc,
		synchronization_health_desc,
		latency_seconds = case when is_primary_replica = 1 then 0
								else (	select DATEDIFF(second,ag.last_commit_time,p.last_commit_time) 
										from #availability_databases p 
										where p.is_primary_replica = 1 and p.database_name = ag.database_name
									)
								end,
		redo_queue_size,
		log_send_queue_size,
		last_redone_time,
		log_send_rate,		
		redo_rate,
		estimated_redo_completion_time_min,
		last_commit_time,
		is_suspended,
		suspend_reason_desc
into dbo.ag_health_state
from #availability_databases as ag
left join sys.availability_group_listeners agl on agl.group_id = ag.group_id
left join sys.availability_group_listener_ip_addresses ia on ia.listener_id = agl.listener_id and ia.state_desc = 'ONLINE'
order by ag.ag_name, ag.replica_server_name, ag.database_name;
