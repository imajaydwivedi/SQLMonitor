IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
SET ARITHABORT ON;
GO

CREATE OR ALTER PROCEDURE dbo.usp_populate_sma_sql_instance
	@server varchar(125),
	@collection_time datetime2 = null,
	@execute bit = 1, /* 0 = Don't insert data */
	@verbose tinyint = 0 /* 0 = No logs, 1 = Print Message, 2 = Table Result + Messages */
AS

BEGIN
/*
	Purpose:		Populate table dbo.sma_servers.
					[dbo].[usp_populate_sma_servers] is target table.

	Modifications:	2024-08-27 - Ajay - Adding code to find possible decomissioned hosts
					2024-07-24 - Ajay - First draft

	Examples:	
		exec usp_populate_sma_sql_instance @server = '21L-LTPABL-1187', @verbose = 2
*/
	SET NOCOUNT ON;

	if @verbose >= 1
		print 'Declare variables..'

	declare @_start_time datetime2 = coalesce(@collection_time,sysdatetime());
	declare @_crlf nchar(2) = char(10)+char(13);
	declare @_long_star_line varchar(500) = replicate('*',75);
	declare @_server_count int = 0;
	declare @_rows_affected int = 0;

	declare @_failed_server_count int = 0;
	declare	@_errorNumber int,
			@_errorSeverity int,
			@_errorState int,
			@_errorLine int,
			@_errorMessage nvarchar(4000);
	declare @_sql NVARCHAR(MAX);
	declare @_params nvarchar(max);

	if @verbose >= 1
		print 'Declaring temp tables..'

	if OBJECT_ID('tempdb..#dm_os_cluster_nodes') is not null
		drop table #dm_os_cluster_nodes;
	create table #dm_os_cluster_nodes
	( NodeName varchar(125), status_description varchar(20), current_role varchar(50), [host_name] varchar(125) );

	if OBJECT_ID('tempdb..#dm_hadr_cluster') is not null
		drop table #dm_hadr_cluster;
	create table #dm_hadr_cluster
	( cluster_name varchar(125), quorum_type_desc varchar(125), quorum_state_desc varchar(125) );

	if OBJECT_ID('tempdb..#availability_replicas') is not null
		drop table #availability_replicas;
	create table #availability_replicas
	( ag_name varchar(125), replica_server_name varchar(125), current_role varchar(125), sync_health varchar(125) );

	if OBJECT_ID('tempdb..#availability_groups') is not null
		drop table #availability_groups;
	create table #availability_groups
	( replica_server_name varchar(125), is_primary_replica bit, [dbs] varchar(max),
	  ag_name varchar(125), ag_listener varchar(125), ag_listener_ips varchar(500), is_local bit
	);

	if @verbose >= 2
	begin
		select RunningQuery, t.* from dbo.instance_details t
		full outer join (select RunningQuery = 'dbo.instance_details') rq on 1=1
		where sql_instance = @server;

		select RunningQuery, t.* from dbo.vw_all_server_info t
		full outer join (select RunningQuery = 'dbo.vw_all_server_info') rq on 1=1
		where srv_name = @server;
	end


	if ('Get-Cluster-Nodes' = 'Get-Cluster-Nodes')
	begin
		set @_sql = '
			select	--RunningQuery = ''sys.dm_os_cluster_nodes'', 
					NodeName, status_description, 
					[current_role] = case when is_current_owner = 1 then ''Active'' else ''Passive'' end, 
					[host_name] = convert(varchar,SERVERPROPERTY(''ComputerNamePhysicalNetBIOS''))
			from sys.dm_os_cluster_nodes
			';
		if @@SERVERNAME <> @server
			set @_sql = 'select * from openquery(' + QUOTENAME(@server) + ', '''+ replace(@_sql,'''','''''') + ''')';
	
		if @verbose >= 1
		begin
			print @_long_star_line
			print @_sql;
			print @_long_star_line
		end

		insert #dm_os_cluster_nodes (NodeName, status_description, current_role, host_name)
		exec (@_sql);

		if @verbose >= 2
			select RunningQuery, t.* from #dm_os_cluster_nodes t
			full outer join (select RunningQuery = '#dm_os_cluster_nodes') rq on 1=1;
	end


	if ('Get-WSFC-Cluster-Details' = 'Get-WSFC-Cluster-Details')
	begin
		set @_sql = '
			select	--RunningQuery = ''sys.dm_hadr_cluster'', 
					cluster_name, quorum_type_desc, quorum_state_desc  
			from sys.dm_hadr_cluster;
			';
		if @@SERVERNAME <> @server
			set @_sql = 'select * from openquery(' + QUOTENAME(@server) + ', '''+ replace(@_sql,'''','''''') + ''')';
	
		if @verbose >= 1
		begin
			print @_long_star_line
			print @_sql;
			print @_long_star_line
		end

		insert #dm_hadr_cluster (cluster_name, quorum_type_desc, quorum_state_desc)
		exec (@_sql);

		if @verbose >= 2
			select RunningQuery, t.* from #dm_hadr_cluster t
			full outer join (select RunningQuery = '#dm_hadr_cluster') rq on 1=1;
	end


	if ('Get-Availability-Replicas' = 'Get-Availability-Replicas')
	begin
		set @_sql = '
			select	--RunningQuery = ''sys.availability_replicas'', 
					[ag_name] = ag.name, 
					ar.replica_server_name, 
					[current_role] = ars.role_desc, 
					[sync_health] = ars.synchronization_health_desc
			from sys.availability_groups AS ag 
			JOIN sys.availability_replicas AS ar 
				ON ag.group_id = ar.group_id
			JOIN sys.dm_hadr_availability_replica_states AS ars
				ON ar.replica_id = ars.replica_id
			';
		if @@SERVERNAME <> @server
			set @_sql = 'select * from openquery(' + QUOTENAME(@server) + ', '''+ replace(@_sql,'''','''''') + ''')';

		if @verbose >= 1
		begin
			print @_long_star_line
			print @_sql;
			print @_long_star_line
		end

		insert #availability_replicas ( ag_name, replica_server_name, current_role, sync_health )
		exec (@_sql);

		if @verbose >= 2
			select RunningQuery, t.* from #availability_replicas t
			full outer join (select RunningQuery = '#availability_replicas') rq on 1=1;
	end


	if ('Get-Ag-Databases' = 'Get-Ag-Databases')
	begin
		set @_sql = '
			;with cte_availability_databases as (
				select	ar.replica_server_name,
						drs.is_primary_replica,
						adc.database_name,
						ag.name AS ag_name,
						drs.is_local,
						ag.group_id,
						ag_id = ROW_NUMBER()over(partition by ar.replica_server_name, ag.name order by adc.database_name)
				from sys.dm_hadr_database_replica_states as drs
				inner join sys.availability_databases_cluster as adc on drs.group_id = adc.group_id
					and drs.group_database_id = adc.group_database_id
				inner join sys.availability_groups as ag on ag.group_id = drs.group_id
				inner join sys.availability_replicas as ar on drs.group_id = ar.group_id
					and drs.replica_id = ar.replica_id
			)
			select	replica_server_name,
					is_primary_replica,
					db_names.dbs,
					ag_name,
					[ag_listener] = agl.dns_name,
					ag_listener_ips = ips.ag_listener_ips,
					is_local
			from cte_availability_databases as ag
			left join sys.availability_group_listeners agl
				on agl.group_id = ag.group_id
			outer apply (
				select ag_listener_ips = STUFF((select '', '' + cast(ia.ip_address as varchar(125)) [text()]
												 from sys.availability_group_listener_ip_addresses ia
												 where ia.listener_id = agl.listener_id 
												 --and ia.state_desc = ''ONLINE''
												 FOR XML PATH(''''), TYPE)
												.value(''.'',''nvarchar(max)''),1,2,'' '')
				) ips
			outer apply (
				select dbs = STUFF((select '', '' + cast(d.[database_name] as varchar(125)) [text()]
												 from cte_availability_databases d
												 where d.replica_server_name = ag.replica_server_name
												 and d.ag_name = ag.ag_name
												 FOR XML PATH(''''), TYPE)
												.value(''.'',''nvarchar(max)''),1,2,'' '')
				) db_names
			where is_local = 1
			and ag_id = 1
			order by ag.ag_name, ag.replica_server_name, ag.database_name;
		';

		if @@SERVERNAME <> @server
			set @_sql = 'select * from openquery(' + QUOTENAME(@server) + ', '''+ replace(@_sql,'''','''''') + ''')';

		if @verbose >= 1
		begin
			print @_long_star_line
			print @_sql;
			print @_long_star_line
		end

		insert #availability_groups 
		( replica_server_name, is_primary_replica, [dbs], ag_name, [ag_listener], ag_listener_ips, is_local )
		exec (@_sql);

		if @verbose >= 2
			select RunningQuery, t.* from #availability_groups t
			full outer join (select RunningQuery = '#availability_groups') rq on 1=1;
	end


	if ('Populate-[sma_servers]' = 'Populate-[sma_servers]')
	begin
		if OBJECT_ID('tempdb..#sma_servers') is not null
			drop table #sma_servers;
		select	[server] = sql_instance, [server_port] = sql_instance_port, 
				[domain] = asi.domain, [friendly_name] = null, 
				[stability] = 'prod', [priority] = 3, 
				[server_type] = 'SQLServer', 
				[has_hadr] = (case when exists (select 1/0 from #availability_replicas) then 1
									when exists (select 1/0 from #dm_os_cluster_nodes) then 1
									else 0
									end), 
				[hadr_strategy] = (case when exists (select 1/0 from #availability_replicas) then 'ag'
									when exists (select 1/0 from #dm_os_cluster_nodes) then 'sqlcluster'
									else 'standalone'
									end), 
				[backup_strategy] = null, [server_owner_email] = null, 
				[rdp_credential] = null, [sql_credential] = 'linkadmin', [is_monitoring_enabled] = 1, [is_maintenance_scheduled] =  0, 
				[is_tde_implemented] = 0, [enabled_restart_schedule] = 0, [is_decommissioned] = 0, [more_info] = null, [is_onboarded] = 1
		into #sma_servers
		from dbo.instance_details id
		join dbo.vw_all_server_info asi
			on asi.srv_name = id.sql_instance and asi.host_name = id.host_name
		where 1=1
		and id.is_enabled = 1
		and id.sql_instance = @server;

		if @verbose >= 2
		begin
			select RunningQuery, t.* from  #sma_servers t
			full outer join (select RunningQuery = 'INSERT-dba.sma_servers') rq on 1=1;
		end

		if @execute = 1
		begin
			if not exists (select * from dbo.sma_servers s where s.server = @server)
			begin
				insert dbo.sma_servers
				(	[server], [server_port], [domain], [friendly_name], [stability], [priority], 
					[server_type], [has_hadr], [hadr_strategy], [backup_strategy], [server_owner_email], 
					[rdp_credential], [sql_credential], [is_monitoring_enabled], [is_maintenance_scheduled], 
					[is_tde_implemented], [enabled_restart_schedule], [is_decommissioned], [more_info], [is_onboarded]
				)
				select [server], [server_port], [domain], [friendly_name], [stability], [priority], 
					[server_type], [has_hadr], [hadr_strategy], [backup_strategy], [server_owner_email], 
					[rdp_credential], [sql_credential], [is_monitoring_enabled], [is_maintenance_scheduled], 
					[is_tde_implemented], [enabled_restart_schedule], [is_decommissioned], [more_info], [is_onboarded]
				from #sma_servers
			end
			else
				print quotename(@server)+' already exists in dbo.sma_servers'
		end
	end	
	
	if ('Populate-[sma_sql_server_extended_info]' = 'Populate-[sma_sql_server_extended_info]')
	begin
		if object_id('tempdb..#sma_sql_server_extended_info') is not null
			drop table #sma_sql_server_extended_info;
		select	[server] = id.sql_instance, [at_server_name] = asi.at_server_name, 
				[server_name] = asi.server_name, [server_ips_CSV] = null, 
				[alias_names] = null, [product_version] = asi.product_version, 
				[edition] = asi.edition, [has_PII_data] = 0, [total_physical_memory_kb] = asi.total_physical_memory_kb, 
				[cpu_count] = asi.cpu_count, [rpo_worst_case_minutes] = null, 
				[rto_minutes] = null, [data_center] = null, [availability_zone] = null, 
				[avg_utilization] = null, [ticket] = null, [purpose] = null, 
				[known_challenges] = null, [remarks] = null, 
				[more_info] = null
		into #sma_sql_server_extended_info
		from dbo.instance_details id
		join dbo.vw_all_server_info asi
			on asi.srv_name = id.sql_instance and asi.host_name = id.host_name
		where 1=1
		and id.is_enabled = 1
		and id.sql_instance = @server; 

		if @verbose >= 2
		begin
			select RunningQuery, t.* from  #sma_sql_server_extended_info t
			full outer join (select RunningQuery = 'INSERT-dba.sma_sql_server_extended_info') rq on 1=1;
		end

		if @execute = 1
		begin		
			if not exists (select * from dbo.sma_sql_server_extended_info where server = @server)
			begin
				insert dbo.sma_sql_server_extended_info
				(	[server], [at_server_name], [server_name], [server_ips_CSV], [alias_names], [product_version], [edition], [has_PII_data], [total_physical_memory_kb], [cpu_count], [rpo_worst_case_minutes], [rto_minutes], [data_center], [availability_zone], [avg_utilization], [ticket], [purpose], [known_challenges], [remarks], [more_info]
				)
				select [server], [at_server_name], [server_name], [server_ips_CSV], [alias_names], [product_version], [edition], [has_PII_data], [total_physical_memory_kb], [cpu_count], [rpo_worst_case_minutes], [rto_minutes], [data_center], [availability_zone], [avg_utilization], [ticket], [purpose], [known_challenges], [remarks], [more_info]
				from #sma_sql_server_extended_info;
			end
			else
				print 'Server '+quotename(@server)+' is already present in dbo.sma_sql_server_extended_info';
		end		
	end

	if ('Populate-[sma_sql_server_hosts]' = 'Populate-[sma_sql_server_hosts]')
	begin
		if OBJECT_ID('tempdb..#sma_sql_server_hosts') is not null
			drop table #sma_sql_server_hosts;
		;with cte_instance_details as (
			select *
			from dbo.instance_details id
			where id.sql_instance = @server and id.is_enabled = 1 and id.is_alias = 0
		)
		select	[server] = @server, 
				[host_name] = coalesce(id.host_name,cn.NodeName), 
				[host_ips] = null, 
				[host_distribution] = null, 
				[processor_name] = null, 
				[ram_mb] = null, 
				[cpu_count] = null, 
				[wsfc_name] = null, 
				[wsfc_ip1] = null, 
				[wsfc_ip2] = null, 
				[is_quarantined] = 0, 
				[is_decommissioned] = 0, 
				[more_info] = null
		into #sma_sql_server_hosts
		from	#dm_os_cluster_nodes cn
		full outer join cte_instance_details id
			on id.host_name = cn.NodeName
		where 1=1;
		 
		if @verbose >= 2
		begin
			select RunningQuery, t.* from  #sma_sql_server_hosts t
			full outer join (select RunningQuery = 'INSERT-dba.sma_sql_server_hosts') rq on 1=1;
		end

		if @execute = 1
		begin
			-- insert NEW host entries
			if exists (select * from #sma_sql_server_hosts t left join dbo.sma_sql_server_hosts h 
						on t.server = h.server and t.host_name = h.host_name where h.host_name is null
					)
			begin
				insert dbo.sma_sql_server_hosts
				(	[server], [host_name], [host_ips], [host_distribution], [processor_name], [ram_mb], 
					[cpu_count], [wsfc_name], [wsfc_ip1], [wsfc_ip2], [is_quarantined], [is_decommissioned], [more_info] )
				select t.[server], t.[host_name], t.[host_ips], t.[host_distribution], t.[processor_name], 
						t.[ram_mb], t.[cpu_count], t.[wsfc_name], t.[wsfc_ip1], t.[wsfc_ip2], t.[is_quarantined], 
						t.[is_decommissioned], t.[more_info]
				from #sma_sql_server_hosts t left join dbo.sma_sql_server_hosts h 
					on t.server = h.server and t.host_name = h.host_name 
				where h.host_name is null;

				set @_rows_affected = @@ROWCOUNT;

				print convert(varchar,@_rows_affected)+' hosts added for '+quotename(@server)+' server in dbo.sma_sql_server_hosts';
			end
			else
				print 'No new entries for '+quotename(@server)+' server in dbo.sma_sql_server_hosts.';

			-- Find list of hosts that are possibily decomissioned
			if OBJECT_ID('tempdb..#possible_decomissioned_hosts') is not null
				drop table #possible_decomissioned_hosts;
			select h.*
			into #possible_decomissioned_hosts
			from dbo.sma_sql_server_hosts h 
			left join #sma_sql_server_hosts t
				on t.server = h.server and t.host_name = h.host_name
			where h.server = @server
			and t.host_name is null and h.is_decommissioned = 0;

			if @verbose >= 2
			begin
				select RunningQuery, t.* from  #possible_decomissioned_hosts t
				full outer join (select RunningQuery = '#possible_decomissioned_hosts') rq on 1=1;
			end

			-- If OLD host entries, then populate wrapper table to decide later
			--if exists (select * from dbo.sma_sql_server_hosts h left join #sma_sql_server_hosts t
			--			on t.server = h.server and t.host_name = h.host_name
			--			where h.host_name is null and h.is_decommissioned = 0
			--			and h.server = @server
			--		)
			--begin
			--	insert dbo.sma_wrapper_sql_server_hosts
			--	([server], [host_name], exists_in_DMV, exists_in_SM, exists_in_INV, disabled_in_INV, collection_time)
			--	select server, [host_name], exists_in_DMV, exists_in_SM, exists_in_INV, disabled_in_INV, @_start_time
			--	from #sma_sql_server_hosts t
			--	where not ([exists_in_DMV] = 1 and [exists_in_INV] = 0);

			--	set @_rows_affected = @@ROWCOUNT;

			--	print convert(varchar,@_rows_affected)+' hosts added for '+quotename(@server)+' server in dbo.sma_wrapper_sql_server_hosts';
			--end
			--else
			--	print 'No new entries for '+quotename(@server)+' server in dbo.sma_wrapper_sql_server_hosts.';
		end
	end

	if ('Populate-[sma_hadr_ag]' = 'Populate-[sma_hadr_ag]')
	begin
		if OBJECT_ID('tempdb..#sma_hadr_ag') is not null
			drop table #sma_hadr_ag;
		select	[server] = @server, [ag_name] = ag.ag_name, 
				[ag_replicas_CSV] = STUFF((select ', ' + cast(r.replica_server_name as varchar(125)) [text()]
											from #availability_replicas r
											where r.ag_name = ag.ag_name
											FOR XML PATH(''), TYPE)
										.value('.','nvarchar(max)'),1,2,' '), 
				[preferred_role] = case when ag.is_primary_replica = 1 then 'Primary' else 'Secondary' end, 
				[current_role] = case when ag.is_primary_replica = 1 then 'Primary' else 'Secondary' end, 
				[ag_databases_CSV] = ag.dbs, 
				[ag_listener_name] = ag_listener, 
				[ag_listener_ip1] = (	select ip 
											from (	select ip = ltrim(rtrim(value)), row_id = ROW_NUMBER()over(order by value) 
													from string_split(ag.ag_listener_ips, ',') sp
												) sp 
											where sp.row_id = 1
										), 
				[ag_listener_ip2] = (	select ip 
											from (	select ip = ltrim(rtrim(value)), row_id = ROW_NUMBER()over(order by value) 
													from string_split(ag.ag_listener_ips, ',') sp
												) sp 
											where sp.row_id = 2
										),  
				[is_decommissioned] = 0, 
				[remarks] = null
		into #sma_hadr_ag
		from #availability_groups ag
		where 1=1;
		
		if @verbose >= 2
		begin
			select RunningQuery, t.* from  #sma_hadr_ag t
			full outer join (select RunningQuery = 'INSERT-dba.sma_hadr_ag') rq on 1=1;
		end

		if @execute = 1
		begin		
			if exists (select * from #sma_hadr_ag t left join dbo.sma_hadr_ag ag 
						on t.server = ag.server and t.ag_name = ag.ag_name where ag.ag_name is null)
			begin
				insert dbo.sma_hadr_ag
				([server], [ag_name], [ag_replicas_CSV], [preferred_role], [current_role], [ag_databases_CSV], 
				[ag_listener_name], [ag_listener_ip1], [ag_listener_ip2], [is_decommissioned], [remarks])
				select t.[server], t.[ag_name], t.[ag_replicas_CSV], t.[preferred_role], t.[current_role], t.[ag_databases_CSV], 
						t.[ag_listener_name], t.[ag_listener_ip1], t.[ag_listener_ip2], t.[is_decommissioned], t.[remarks]
				from #sma_hadr_ag t
				left join dbo.sma_hadr_ag ag 
				on t.server = ag.server and t.ag_name = ag.ag_name 
				where ag.ag_name is null;
			end
			else
				print quotename(@server)+' replicas already exist in table dbo.sma_hadr_ag'
		end
	end

	if ('Populate-[sma_hadr_sql_cluster]' = 'Populate-[sma_hadr_sql_cluster]')
	begin
		if OBJECT_ID('tempdb..#sma_hadr_sql_cluster') is not null
			drop table #sma_hadr_sql_cluster;
		select	[server] = @server, 
				[sql_cluster_network_name] = asi.machine_name, 
				[preferred_owner_node] = ocn.NodeName, 
				[sql_cluster_ip1] = asi.ip, 
				[sql_cluster_ip2] = null, 
				[is_decommissioned] = 0, 
				[remarks] = null
		into #sma_hadr_sql_cluster
		from #dm_os_cluster_nodes ocn
		join dbo.vw_all_server_info asi
			on asi.srv_name = @server and asi.host_name = ocn.NodeName
		where 1=1 ;

		if @verbose >= 2
		begin
			select RunningQuery, t.* from  #sma_hadr_sql_cluster t
			full outer join (select RunningQuery = 'INSERT-dba.sma_hadr_sql_cluster') rq on 1=1;
		end

		if @execute = 1
		begin
			if not exists (select * from dbo.sma_hadr_sql_cluster where server = @server)
			begin
				insert dbo.sma_hadr_sql_cluster
				([server], [sql_cluster_network_name], [preferred_owner_node], [sql_cluster_ip1], [sql_cluster_ip2], [is_decommissioned], [remarks])
				select [server], [sql_cluster_network_name], [preferred_owner_node], [sql_cluster_ip1], [sql_cluster_ip2], [is_decommissioned], [remarks]
				from #sma_hadr_sql_cluster;
			end
			else
				print quotename(@server)+' already exists in table dbo.sma_hadr_sql_cluster';
		end
	end

	if ('Update-has_hadr-flag' = 'Update-has_hadr-flag')
	begin
		if @verbose >= 1
			print 'Update [has_hadr] & [hadr_strategy] for AG servers..'
		update s set has_hadr = 1, hadr_strategy = 'ag'
		from dbo.sma_servers s
		where s.is_decommissioned = 0
		and s.server in (select ag.server from dbo.sma_hadr_ag ag where ag.is_decommissioned = 0)
		and (s.hadr_strategy is null or s.hadr_strategy <> 'ag');

		if @verbose >= 1
			print 'Update [has_hadr] & [hadr_strategy] for SQLCluster servers..'
		update s set has_hadr = 1, hadr_strategy = 'sqlcluster'
		from dbo.sma_servers s
		where s.is_decommissioned = 0
		and s.server in (select sc.server from dbo.sma_hadr_sql_cluster sc where sc.is_decommissioned = 0)
		and (s.hadr_strategy is null or s.hadr_strategy not in ('ag','sqlcluster'));
	end
END
GO


--exec dbo.usp_populate_sma_sql_instance @server = '192.168.1.5' ,@execute = 0 ,@verbose = 2;
go