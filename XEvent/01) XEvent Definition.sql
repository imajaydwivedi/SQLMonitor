--	Drop and Re-create Extended Event Session
IF EXISTS (SELECT * FROM sys.server_event_sessions WHERE name = 'xevent_metrics')
	EXEC ('DROP EVENT SESSION [xevent_metrics] ON SERVER;');

CREATE EVENT SESSION [xevent_metrics] ON SERVER 
ADD EVENT sqlserver.rpc_completed(SET collect_statement=(1)
    ACTION(sqlos.scheduler_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.context_info,sqlserver.database_name,sqlserver.query_hash,sqlserver.query_plan_hash,sqlserver.request_id,sqlserver.session_id,sqlserver.session_resource_group_id,sqlserver.session_resource_pool_id,sqlserver.username)
    WHERE ( ([duration]>=5000000) OR ([result]<>('OK')) )),
ADD EVENT sqlserver.sql_batch_completed(SET collect_batch_text=(0)
    ACTION(sqlos.scheduler_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.context_info,sqlserver.database_name,sqlserver.query_hash,sqlserver.query_plan_hash,sqlserver.request_id,sqlserver.session_id,sqlserver.session_resource_group_id,sqlserver.session_resource_pool_id,sqlserver.sql_text,sqlserver.username)
    WHERE ( ([duration]>=5000000) OR ([result]<>('OK')) ))
/*
ADD EVENT sqlserver.sql_statement_completed(SET collect_statement=(0)
    ACTION(sqlos.scheduler_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.context_info,sqlserver.database_name,sqlserver.query_hash,sqlserver.query_plan_hash,sqlserver.session_id,sqlserver.session_resource_group_id,sqlserver.session_resource_pool_id,sqlserver.sql_text,sqlserver.username)
    WHERE ( ([duration]>=5000000) )),
*/
ADD TARGET package0.event_file(SET filename=N'E:\Data\xevents\xevent_metrics.xel',max_file_size=(100),max_rollover_files=(100))
WITH (MAX_MEMORY=204800 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=ON)
GO

ALTER EVENT SESSION [xevent_metrics] ON SERVER STATE = START
GO

SELECT * FROM sys.server_event_sessions WHERE name = 'xevent_metrics'
GO
