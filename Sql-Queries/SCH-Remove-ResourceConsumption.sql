declare @xe_exists bit = 1;

if not exists (select * from sys.dm_xe_sessions xe where xe.name = 'resource_consumption')
	set @xe_exists = 0;

if @xe_exists = 1
	exec ('ALTER EVENT SESSION resource_consumption ON SERVER STATE = STOP;');

if @xe_exists = 1
	exec ('DROP EVENT SESSION resource_consumption ON SERVER');

if @xe_exists = 1 and exists (select * from msdb.dbo.sysjobs_view v where v.name = '(dba) Collect-XEvents')
exec ('EXEC msdb..sp_delete_job @job_name = ''(dba) Collect-XEvents''');

if object_id('[dbo].[vw_resource_consumption]') is not null
	exec ('drop view [dbo].[vw_resource_consumption]')

if object_id('[dbo].[resource_consumption_Processed_XEL_Files]') is not null
	exec ('drop table [dbo].[resource_consumption_Processed_XEL_Files]');

if object_id('[dbo].[resource_consumption_queries]') is not null
	exec ('drop table [dbo].[resource_consumption_queries]');

if object_id('[dbo].[resource_consumption]') is not null
	exec ('drop table [dbo].[resource_consumption]');

if exists (select * from sys.tables t where t.name = 'sql_agent_job_thresholds' and create_date < '2024-01-15')
    exec ('drop table [dbo].[sql_agent_job_thresholds]');

if exists (select * from sys.tables t where t.name = 'sql_agent_job_stats' and create_date < '2024-01-15')
    exec ('drop table [dbo].[sql_agent_job_stats]');
