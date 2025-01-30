USE DBA
GO


select @@SERVERNAME, name, recovery_model_desc, collation_name from sys.databases where database_id = db_id();
go

--	Find used/free space in Database Files
select	SERVERPROPERTY('MachineName') AS srv_name,
		DB_NAME() AS [db_name], f.type_desc, fg.name as file_group, f.name, f.physical_name, (f.size*8.0)/1024/1024 as size_GB, f.max_size, f.growth,
		CAST(FILEPROPERTY(f.name, 'SpaceUsed') as BIGINT)/128.0/1024 AS SpaceUsed_gb
		,(size/128.0 -CAST(FILEPROPERTY(f.name,'SpaceUsed') AS INT)/128.0)/1024 AS FreeSpace_GB
		,cast((FILEPROPERTY(f.name,'SpaceUsed')*100.0)/size as decimal(20,2)) as Used_Percentage
		,CASE WHEN f.type_desc = 'LOG' THEN (select d.log_reuse_wait_desc from sys.databases as d where d.name = DB_NAME()) ELSE NULL END as log_reuse_wait_desc
--into tempdb..db_size_details
from sys.database_files f with (nolock) left join sys.filegroups fg with (nolock)  on fg.data_space_id = f.data_space_id
order by FreeSpace_GB desc;
go

DECLARE @Domain NVARCHAR(255);
begin try
	EXEC master.dbo.xp_regread 'HKEY_LOCAL_MACHINE', 'SYSTEM\CurrentControlSet\services\Tcpip\Parameters', N'Domain',@Domain OUTPUT;
end try
begin catch
	print 'some erorr accessing registry'
end catch

declare @ports varchar(2000);
select @ports = coalesce(@ports+', '+convert(varchar,p.local_tcp_port),convert(varchar,p.local_tcp_port))
from (
		select distinct local_net_address, local_tcp_port 
		from sys.dm_exec_connections 
		where local_net_address is not null
	) p;

;with server_services as (
	select *
	from sys.dm_server_services 
	where servicename like 'SQL Server (%)'
	or servicename like 'SQL Server Agent (%)'
)
select	[domain] = DEFAULT_DOMAIN(),
		[domain_reg] = @Domain,
		[ip] = CONNECTIONPROPERTY('local_net_address'),
		[@@SERVERNAME] = @@SERVERNAME,
		[MachineName] = serverproperty('MachineName'),
		[ServerName] = serverproperty('ServerName'),
		[host_name] = COALESCE(SERVERPROPERTY('ComputerNamePhysicalNetBIOS'),SERVERPROPERTY('ServerName')),
		[sql_version] = @@VERSION,
		[service_name_str] = servicename,
		[service_name] = case	when @@servicename is null then 'MSSQLSERVER'
								when @@servicename = 'MSSQLSERVER' and servicename like 'SQL Server (%)' then 'MSSQLSERVER'
								when @@servicename = 'MSSQLSERVER' and servicename like 'SQL Server Agent (%)' then 'SQLSERVERAGENT'
								when @@servicename <> 'MSSQLSERVER' and servicename like 'SQL Server (%)' then 'MSSQL$'+@@servicename
								when @@servicename <> 'MSSQLSERVER' and servicename like 'SQL Server Agent (%)' then 'SQLAgent'+@@servicename
								else 'MSSQL$'+@@servicename end,
		[instance_name] = coalesce(@@servicename,'MSSQLSERVER'),
		service_account,
		[@ports] = @ports,
		SERVERPROPERTY('Edition') AS Edition,
		SERVERPROPERTY('ProductVersion') AS ProductVersion,
		SERVERPROPERTY('ProductLevel') AS ProductLevel
		--,instant_file_initialization_enabled
		--,*
from (values ('Basic-Details')) d (RunningQuery)
full outer join	server_services ss
	on 1=1;
go

select *
from sys.dm_os_cluster_nodes;
go

select RunningQuery = 'ag replicas', [at_server_name] = @@SERVERNAME, ar.replica_server_name, rs.role_desc, rs.is_local, rs.operational_state_desc, rs.connected_state_desc, rs.recovery_health_desc, rs.synchronization_health_desc
from sys.dm_hadr_availability_replica_states rs
	join sys.availability_replicas ar
	on ar.group_id = rs.group_id and ar.replica_id = rs.replica_id
go

select 'instance_hosts' as QueryData, * from dbo.instance_hosts with (nolock);

select 'instance_details' as QueryData, getdate() as [getdate()], * from dbo.instance_details with (nolock);
go

select top 1 'vw_performance_counters' as QueryData, getutcdate() as current_time_utc, collection_time_utc, pc.host_name
from dbo.vw_performance_counters pc with (nolock)
order by pc.collection_time_utc desc
go

select top 1 'vw_os_task_list' as QueryData, getutcdate() as current_time_utc, collection_time_utc, pc.host_name
from dbo.vw_os_task_list pc with (nolock)
order by pc.collection_time_utc desc
go

select top 1 'dbo.xevent_metrics' as QueryDate, getdate() as [getdate()], rc.*
from dbo.xevent_metrics rc
order by event_time desc
go