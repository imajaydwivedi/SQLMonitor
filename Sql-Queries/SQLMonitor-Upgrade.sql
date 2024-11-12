use DBA
go

-- https://learn.microsoft.com/en-us/sql/relational-databases/json/json-data-sql-server?view=sql-server-ver16\

-- Get servers with customized job info
select ISJSON(id.more_info), id.sql_instance, id.sql_instance_port, id.[database], id.more_info
from dbo.instance_details id
where id.is_enabled = 1
and id.is_available = 1
and id.is_alias = 0
and id.more_info is not null
go

-- Set a sql_instance to have customized job info
declare @json_data nvarchar(max);
set @json_data = (select cast(1 as bit) as "HasCustomizedTsqlJobs", 
						cast(0 as bit) as HasCustomizedPowerShellJobs, 
						cast(0 as bit) as ForceSetupOfTaskSchedulerJobs
						for JSON PATH
				);
update id
set more_info = @json_data
from dbo.instance_details id
where id.is_enabled = 1
and id.is_available = 1
and id.is_alias = 0
and id.sql_instance in ('192.168.1.110');
go

select	[domain] = asi.domain, id.sql_instance, id.host_name, id.[database], 
		id.data_destination_sql_instance, id.collector_powershell_jobs_server, id.collector_tsql_jobs_server,
		id.dba_group_mail_id, id.sqlmonitor_version,
		id.is_alias, id.is_linked_server_working, id.source_sql_instance, id.sql_instance_port		
from dbo.instance_details id
outer apply (select top 1 * from dbo.vw_all_server_info asi where asi.srv_name = id.sql_instance) asi
where 1=1
and id.is_enabled = 1 and id.is_available = 1 and id.is_alias = 0
and id.sqlmonitor_version <> '1.6.5'
--and id.sqlmonitor_version = '1.5.0.4'
order by id.sql_instance, id.host_name
go

/*
select *
from vw_all_server_info asi
where asi.at_server_name like '%SomeHostName%'

select id.*, asi.domain
from dbo.instance_details id
outer apply (select top 1 asi.domain from dbo.vw_all_server_info asi where asi.srv_name = id.sql_instance) asi
where 1=1 and id.sqlmonitor_version <> '1.3.0'
and asi.domain in ('WORKGROUP')
-- 

-- Query to find out JobServers with List of Hosts & SQLInstances
;with t_job_servers as (
	select distinct js.collector_powershell_jobs_server --, id.[job_server_hosts]
	from dbo.instance_details js /* PowerShell Job Server */
	outer apply (select top 1 asi.domain from dbo.vw_all_server_info asi where asi.srv_name = js.sql_instance) asi
	where 1=1
	and js.sqlmonitor_version <> '1.3.0'
	--and asi.domain = 'Lab'
)
, t_job_servers_hosts as (
	select js.collector_powershell_jobs_server, id.job_server_hosts, srvs.sql_instances
	from t_job_servers js
	outer apply (select [job_server_hosts] = STUFF(( select ', '+id.host_name
				 from (select distinct id.host_name from dbo.instance_details id where id.sql_instance = js.collector_powershell_jobs_server) id
				 for xml path(''), TYPE)
				.value('.','varchar(max)'),1,2,' ')
				) id
	outer apply (select [sql_instances] = STUFF(( select ', '+srvs.sql_instance
				 from (select distinct srvs.sql_instance from dbo.instance_details srvs where srvs.collector_powershell_jobs_server = js.collector_powershell_jobs_server) srvs
				 for xml path(''), TYPE)
				.value('.','varchar(max)'),1,2,' ')
				) srvs
)
select js.collector_powershell_jobs_server, job_server_hosts = ltrim(rtrim(js.job_server_hosts)), sql_instances = ltrim(rtrim(js.sql_instances))
from t_job_servers_hosts js
order by js.collector_powershell_jobs_server --, sql_instance
go
*/

/*
select upd.*
-- update upd set sqlmonitor_version = '1.5.0.5'
from dbo.instance_details id
join dbo.instance_details upd
	on upd.sql_instance = id.sql_instance
	and upd.[database] = id.[database]
	and upd.sqlmonitor_version <> '1.5.0.5'
	and upd.host_name <> id.host_name
	and upd.is_available = 1
	and upd.is_enabled = 1
where id.sqlmonitor_version = '1.5.0.5'
and id.is_alias = 0 and id.is_enabled = 1 and id.is_available = 1
go
*/

/*
select id.*, asi.*
-- update id set sqlmonitor_version = '1.3.0'
from dbo.instance_details id
outer apply (select top 1 asi.domain from dbo.vw_all_server_info asi where asi.srv_name = id.sql_instance) asi
where 1=1 
and id.sqlmonitor_version <> '1.3.0'
and asi.domain in ('Lab')
and id.sql_instance in ('192.168.1.10')
*/

/*
declare @_alias_server nvarchar(500);
set @_alias_server = '192.168.200.21';

insert dbo.instance_details 
(sql_instance, [host_name], [database], collector_tsql_jobs_server, collector_powershell_jobs_server, data_destination_sql_instance, is_available, created_date_utc, last_unavailability_time_utc, dba_group_mail_id, sqlmonitor_script_path, sqlmonitor_version, is_alias, source_sql_instance, sql_instance_port, more_info, is_enabled, is_linked_server_working)
select sql_instance = @_alias_server, [host_name], [database], collector_tsql_jobs_server, collector_powershell_jobs_server, data_destination_sql_instance, is_available, created_date_utc, last_unavailability_time_utc, dba_group_mail_id, sqlmonitor_script_path, sqlmonitor_version, is_alias = 1, source_sql_instance = data_destination_sql_instance, sql_instance_port, more_info, is_enabled, is_linked_server_working
from dbo.instance_details id
where 1=1
and id.sql_instance in ('192.168.100.22')
go
*/

/*
declare @_alias_server nvarchar(500);
set @_alias_server = 'SqlGuest1';

--insert into dbo.instance_hosts
--select 'SQLGUEST1';

insert dbo.instance_details 
(sql_instance, sql_instance_port, [host_name], [database], collector_tsql_jobs_server, collector_powershell_jobs_server, data_destination_sql_instance, is_available, created_date_utc, last_unavailability_time_utc, dba_group_mail_id, sqlmonitor_script_path, sqlmonitor_version, is_alias, source_sql_instance, more_info, is_enabled, is_linked_server_working)
select sql_instance = @_alias_server, 
		sql_instance_port = '50012', 
		[host_name] = 'SQLGUEST1', [database], 
		collector_tsql_jobs_server = 'SqlGuest1,50012', 
		collector_powershell_jobs_server = 'SqlGuest1,50012', 
		data_destination_sql_instance = 'SqlGuest1,50012', 
		is_available, created_date_utc, last_unavailability_time_utc, dba_group_mail_id, sqlmonitor_script_path, sqlmonitor_version, is_alias = 0, source_sql_instance = null, more_info, is_enabled, is_linked_server_working = 1
from dbo.instance_details id
where 1=1
and id.sql_instance in ('SqlProd-GC')
*/