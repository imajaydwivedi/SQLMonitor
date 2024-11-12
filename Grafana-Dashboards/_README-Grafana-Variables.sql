/*
1) Create a folder on Grafana named "SQLServer". This name is case sensitive.
2) Then import all the dashboards using *.json files into The SQLServer folder created above.
3) Select appropriate Data Source

https://grafana.com/docs/grafana/v9.0/variables/variable-types/global-variables/
https://grafana.com/docs/grafana/latest/dashboards/variables/variable-syntax/
https://grafana.com/docs/grafana/latest/dashboards/variables/variable-syntax/#advanced-variable-format-options
https://grafana.com/docs/grafana/v9.0/variables/syntax/

https://grafana.com/docs/grafana/latest/panels-visualizations/configure-data-links/

d/wait_stats?var-server=${server}
d/distributed_perfmon?var-server=${__data.fields.srv_name}
d/distributed_perfmon?var-server=${__data.fields.srv_name}&var-perfmon_host_name=${__data.fields.srv_name}
d/distributed_perfmon?var-server=${__data.fields.srv_name}&viewPanel=30
d/distributed_perfmon?var-server=${__data.fields.sql_instance}&var-database=tempdb&viewPanel=115
d/distributed_perfmon?var-server=${__data.fields.sql_instance}&var-database=tempdb&viewPanel=38

d/distributed_live_dashboard?var-server=${__data.fields.srv_name}
d/distributed_live_dashboard?var-server=${__data.fields.srv_name}&viewPanel=111
d/distributed_live_dashboard?var-server=${server}&viewPanel=124

d/WhoIsActive?var-server=${server}&viewPanel=122
d/WhoIsActive?var-server=${server}&var-session_id=${__data.fields.spid}&viewPanel=132
d/WhoIsActive?var-server=${server}&var-login_name=${__data.fields.login_name}&viewPanel=132
d/WhoIsActive?var-server=${server}&var-program_name=${__data.fields.program_name}&viewPanel=132
d/WhoIsActive?var-server=${server}&var-session_host_name=${__data.fields.host_name}&viewPanel=132

d/disk_space?var-server=${__data.fields.sql_instance}&var-perfmon_host_name=${__data.fields.host_name}&var-disk_drive=${__data.fields.disk_volume}&viewPanel=26
d/disk_space?var-server=${__data.fields.sql_instance}&var-perfmon_host_name=${__data.fields.host_name}&var-disk_drive=${__data.fields.disk_volume}&viewPanel=22
d/disk_space?var-server=${server}&var-database=${__data.fields.database_name}&viewPanel=30

https://sqlmonitor.ajaydwivedi.com:3000/d/disk_space/t-disk-space?orgId=1&var-sqlmonitor_datasource=ygPVA4snk&var-server=21L-LTPABL-1187&var-inventory_db=DBA&var-is_local=1&var-dba_db=DBA&var-perfmon_host_name=21L-LTPABL-1187&var-host_name=21L-LTPABL-1187&var-ip=192.168.1.5&var-fqdn=WORKGROUP&var-diskspace_table_name=dbo.vw_disk_space&var-diskspace_collection_time_utc=1693558809487&var-sql_schedulers=8&var-sqlserver_start_time_utc=1693547309393&var-disk_drive=__All__&var-database=DBA&var-fileiostats_table_name=dbo.file_io_stats&var-fileiostats_collection_time_utc=1693559401279&viewPanel=30

d/job_activity_monitor/monitoring-live-all-servers-job-activity-monitor?orgId=1&viewPanel=2&var-server=${__data.fields.sql_instance}&var-last_outcome=Canceled
d/job_activity_monitor/monitoring-live-all-servers-job-activity-monitor?orgId=1&viewPanel=2&var-server=${__data.fields.sql_instance}&var-status=Running
d/job_activity_monitor/monitoring-live-all-servers-job-activity-monitor?orgId=1&viewPanel=2&var-server=${__data.fields.sql_instance}&var-failure_pct=50

Data Links - WaitType
https://www.sqlskills.com/help/waits/${__value.raw}

Data Links - Absolute URL
${__data.fields.url}
*/

Grafana Variables
--------------------

$__dashboard
$__timeFrom()
$__timeTo()
$__name
$__timeFilter(collection_time_utc)
collection_time_utc between $__timeFrom() and $__timeTo()
go

Disk IO Stats ____Since Startup ___ till ___ Current Time___
Disk IO Stats ____Since Startup ___ till ___ ${collection_time_utc:date:YYYY-MM-DD HH.mm}___
Disk IO Stats ____Since Startup ___ till ___ ${__from:date:YYYY-MM-DD HH.mm}___
Database IO Stats ____In Selected Time Duration____Since____${__from:date:YYYY-MM-DD HH.mm}___till___${__to:date:YYYY-MM-DD HH.mm}____
go


SELECT [DateTime]
      ,[AirTemp]
  FROM [meteoData]
  WHERE [DateTime] BETWEEN '${__from:date:iso}' AND '${__to:date:iso}'
  ORDER BY [DateTime] DESC;
GO


set @start_time_utc = dateadd(second,$sqlserver_start_time_utc/1000,'1970-01-01 00:00:00');

use DBA
go

select top 1 *
from dbo.vw_performance_counters
go

/* 
Refresh -> On dashboard load
Query -> Below
Sort -> Alphabetical (case-insensitive, asc)
Validate -> __All__ is top value in Preview

$disk_drive
$database
*/
declare @sql nvarchar(max);
declare @params nvarchar(max);
declare @sql_instance varchar(255);
declare @perfmon_host_name varchar(255);

set @sql_instance = '$server';
--set @perfmon_host_name = '$perfmon_host_name';
set @params = N'@perfmon_host_name varchar(255)';

set quoted_identifier off;
set @sql = "select ds.disk_volume as disk_drive
	from dbo.disk_space ds
	where ds.collection_time_utc = (select max(i.collection_time_utc) from dbo.disk_space i)
	union all
	select '__All__' as disk_drive
	order by disk_drive"
set quoted_identifier on;

--if (@sql_instance = SERVERPROPERTY('SERVERNAME'))
if ($is_local = 1)
  exec dbo.sp_executesql @sql , @params, @perfmon_host_name;
else
  exec [$server].[$dba_db].dbo.sp_executesql @sql , @params, @perfmon_host_name;
go


declare @sql nvarchar(max);
declare @params nvarchar(max);
declare @sql_instance varchar(255);
declare @perfmon_host_name varchar(255);

set @sql_instance = '$server';
--set @perfmon_host_name = '$perfmon_host_name';
set @params = N'@perfmon_host_name varchar(255)';

set quoted_identifier off;
set @sql = "select name from sys.databases d where d.state_desc = 'ONLINE' union all select '__All__' as name order by name;"
set quoted_identifier on;

--if (@sql_instance = SERVERPROPERTY('SERVERNAME'))
if ($is_local = 1)
  exec dbo.sp_executesql @sql , @params, @perfmon_host_name;
else
  exec [$server].[$dba_db].dbo.sp_executesql @sql , @params, @perfmon_host_name;
go

declare @disk_drive varchar(255) = '$disk_drive';
declare @database varchar(255) = '$database';

set @database = case when ltrim(rtrim(@database)) = '__All__' then null else @database end;
set @disk_drive = case when ltrim(rtrim(@disk_drive)) = '__All__' then null else @disk_drive end;

set @params = N', @disk_drive varchar(255), @database varchar(255)';
, @disk_drive, @database

/*
"+(case when @disk_drive is null then '-- ' else '' end)+"and ds.disk_volume = @disk_drive
"+(case when @disk_drive is null then '-- ' else '' end)+"and (pc.instance+'\') = @disk_drive

"+(case when @database is null then '-- ' else '' end)+"AND fis.[database_name] = @database

"+(case when @database is null then '-- ' else '' end)+"AND [Stats].[database_name] = @database
"+(case when @disk_drive is null then '-- ' else '' end)+"and [Stats].disk_volume = @disk_drive


*/
go


/*	How to get From & To in Grafana URL */
$StartTime = $Entry.Starttime
$EndTime = $Entry.Endtime

$unixEpochStart = Get-Date -Date "01/01/1970"

$startTimeSeconds = [bigint]((New-TimeSpan -Start $UnixEpochStart -End $StartTimeUTC).TotalSeconds)
$endTimeSeconds = [bigint]((New-TimeSpan -Start $UnixEpochStart -End $EndTimeUTC).TotalSeconds)

#$grafana ="https://sqlmonitor.ajaydwivedi.com:3000/d-solo/distributed_live_dashboard_all_servers/monitoring---live---all-servers?orgId=1&from=now-15m&to=now&var-Server=$EvaluatedServer"
#$grafana = "http://$($CentralServer):8989/d-solo/distributed_live_dashboard_all_servers/monitoring---live---all-servers?orgId=1&from=$($startTimeSeconds)000&to=$($endTimeSeconds)000&var-Server=$EvaluatedServer"
$grafana = "http://$($CentralServer):8989/d-solo/distributed_live_dashboard_all_servers/monitoring---live---all-servers?orgId=1&from=$($startTimeSeconds)000&to=$($endTimeSeconds)000&var-Server=$EvaluatedServer"
    

/*	Embed Image in Email	*/
C:\Program Files\GrafanaLabs\grafana\bin> .\grafana-cli.exe plugins install grafana-image-renderer

https://stackoverflow.com/a/27305815/4449743
https://stackoverflow.com/a/41994121/4449743
https://www.sqlservercentral.com/forums/topic/how-to-imbed-an-image-into-an-email-sent-by-dbmail#post-1183987

