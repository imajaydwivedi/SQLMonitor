use [master]
if not exists (select * from sys.syslogins where name = 'grafana')
	exec('create login [grafana] with password=N''grafana'', default_database=[DBA], check_expiration=off, check_policy=off');
go

use [master];
if exists (select * from sys.sysusers where name = 'grafana')
	exec('drop user [grafana]')
go

use [master];
if not exists (select * from sys.sysusers where name = 'grafana')
	exec ('create user [grafana] for login [grafana]');
go

use [master];
grant view any definition to [grafana]
grant view server state to [grafana]
grant view any database to [grafana]

if (SERVERPROPERTY('ProductMajorVersion') >= 16)
	exec ('GRANT VIEW SERVER SECURITY STATE TO [grafana]');

if object_id('dbo.SqlServerVersions') is not null
	exec ('grant select on object::dbo.SqlServerVersions to [grafana]');
go


use [msdb];
if exists (select * from sys.sysusers where name = 'grafana')
	exec('drop user [grafana]');
go

use [msdb]
if not exists (select * from sys.sysusers where name = 'grafana')
	exec('create user [grafana] for login [grafana]');
go

use [msdb]
alter role [db_datareader] add member [grafana];
grant view database state to [grafana];
go


use [DBA]
if exists (select * from sys.sysusers where name = 'grafana')
	exec ('drop user [grafana];')
go

use [DBA]
if not exists (select * from sys.sysusers where name = 'grafana')
	exec('create user [grafana] for login [grafana]')
go

use [DBA]
alter role [db_datareader] add member [grafana]
grant view database state to [grafana]
go

use [DBA]
if OBJECT_ID('dbo.usp_extended_results') is not null
	exec ('grant execute on object::dbo.usp_extended_results to [grafana]')
go

use [DBA]
if OBJECT_ID('dbo.sp_WhatIsRunning') is not null
	exec ('grant execute on object::dbo.sp_WhatIsRunning to [grafana]')
go

use [DBA]
if OBJECT_ID('dbo.vw_xevent_metrics') is not null
	exec ('grant select on object::dbo.vw_xevent_metrics to [grafana]')
go

use [DBA]
if OBJECT_ID('dbo.usp_GetAllServerInfo') is not null
	exec ('grant execute on object::dbo.usp_GetAllServerInfo to [grafana]')
go

use [DBA]
if OBJECT_ID('dbo.usp_active_requests_count') is not null
	exec ('grant execute on object::dbo.usp_active_requests_count to [grafana]')
go

use [DBA]
if OBJECT_ID('dbo.usp_waits_per_core_per_minute') is not null
	exec ('grant execute on object::dbo.usp_waits_per_core_per_minute to [grafana]')
go

use [DBA]
if OBJECT_ID('dbo.usp_avg_disk_wait_ms') is not null
	exec ('grant execute on object::dbo.usp_avg_disk_wait_ms to [grafana]')
go

use [DBA]
if OBJECT_ID('dbo.usp_avg_disk_latency_ms') is not null
	exec ('grant execute on object::dbo.usp_avg_disk_latency_ms to [grafana]')
go

use [DBA]
if OBJECT_ID('dbo.sma_sql_servers') is not null
	exec ('grant select on object::dbo.sma_sql_servers to [grafana]')
go

use [DBA]
if OBJECT_ID('dbo.sma_sql_servers_including_offline') is not null
	exec ('grant select on object::dbo.sma_sql_servers_including_offline to [grafana]')
go

use [DBA]
if OBJECT_ID('dbo.vw_all_server_logins') is not null
	exec ('grant select on object::dbo.vw_all_server_logins to [grafana]')
go
