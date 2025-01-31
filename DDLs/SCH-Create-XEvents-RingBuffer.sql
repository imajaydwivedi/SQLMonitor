IF DB_NAME() <> 'master'
	raiserror ('Kindly execute all queries in [master] database', 20, -1) with log;
go

IF APP_NAME() <> 'Microsoft SQL Server Management Studio - Query'
	print 'Working on Creating XEvent Session..'
go

--	Drop and Re-create Extended Event Session
	-- EXEC ('DROP EVENT SESSION [xevent_metrics] ON SERVER;');
IF NOT EXISTS (SELECT * FROM sys.server_event_sessions WHERE name = 'xevent_metrics')
BEGIN
	CREATE EVENT SESSION [xevent_metrics] ON SERVER 
	ADD EVENT sqlserver.rpc_completed(SET collect_statement=(1)
		ACTION(sqlos.scheduler_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.context_info,sqlserver.database_name,sqlserver.query_hash,sqlserver.query_plan_hash,sqlserver.request_id,sqlserver.session_id,sqlserver.session_resource_group_id,sqlserver.session_resource_pool_id,sqlserver.username)
		WHERE ( ([duration]>=5000000) OR ([result]<>('OK')) )),
	ADD EVENT sqlserver.sql_batch_completed(SET collect_batch_text=(0)
		ACTION(sqlos.scheduler_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.context_info,sqlserver.database_name,sqlserver.query_hash,sqlserver.query_plan_hash,sqlserver.request_id,sqlserver.session_id,sqlserver.session_resource_group_id,sqlserver.session_resource_pool_id,sqlserver.sql_text,sqlserver.username)
		WHERE ( ([duration]>=5000000) OR ([result]<>('OK')) ))
	ADD TARGET package0.ring_buffer(SET max_events_limit=(5000),max_memory=(2097152))
	WITH (STARTUP_STATE=ON);
END
GO

if not exists (select * from sys.dm_xe_sessions where name = 'xevent_metrics')
	ALTER EVENT SESSION [xevent_metrics] ON SERVER STATE = START
GO

SELECT * FROM sys.server_event_sessions WHERE name = 'xevent_metrics'
GO
