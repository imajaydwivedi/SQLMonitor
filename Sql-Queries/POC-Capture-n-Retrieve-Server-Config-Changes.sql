CREATE EVENT SESSION [ConfigurationItemsChanged] ON SERVER 
ADD EVENT sqlserver.error_reported(
    ACTION(sqlserver.client_app_name,sqlserver.client_connection_id,sqlserver.database_name,sqlserver.nt_username,sqlserver.sql_text,sqlserver.username)
    WHERE ([error_number]=(15457) OR [error_number]=(5084)))
ADD TARGET package0.ring_buffer(SET max_memory=(4096))
WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=ON)
GO


WITH xe(Events) AS (
    SELECT CAST(xest.target_data as xml)
    FROM sys.dm_xe_session_targets xest  
    JOIN sys.dm_xe_sessions xes ON xes.address = xest.event_session_address  
    WHERE xest.target_name = 'ring_buffer' AND xes.name = 'ConfigurationItemsChanged'  
)
SELECT
  timestamp    = x1.evnt.value('@timestamp','datetimeoffset'),
  message     = x1.evnt.value('(data[@name="message"]/value/text())[1]','nvarchar(4000)'),
  sql_text     = x1.evnt.value('(action[@name="sql_text"]/value/text())[1]','nvarchar(4000)'),
  username  = x1.evnt.value('(action[@name="username"]/value/text())[1]','nvarchar(4000)'),
  client_app_name  = x1.evnt.value('(action[@name="client_app_name"]/value/text())[1]','nvarchar(4000)')

FROM xe
CROSS APPLY xe.Events.nodes('RingBufferTarget/event') x1(evnt);
