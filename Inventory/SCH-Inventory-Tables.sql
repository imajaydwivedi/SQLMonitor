use DBA
go

/*
	Version -> 2024-07-08
	2024-07-08 - #01 - Initial Draft of Inventory Servers
	-----------------

	https://github.com/imajaydwivedi/SQLMonitor/issues/10

	*** Self Pre Steps ***
	----------------------
	1) Python, Git needs to be installed on Inventory server
	2) Credential Manager needs to be installed on Inventory Server
	3) SQLMonitor should be present

	*** Steps in this Script ****
	-----------------------------
	1) Create table dbo.sma_servers
	2) Create table dbo.sma_sql_server_extended_info
	3) Create table dbo.sma_sql_server_hosts
	4) Create table dbo.sma_hadr_ag
	5) Create table dbo.sma_hadr_sql_cluster
	6) Create table dbo.sma_hadr_mirroring
	7) Create table dbo.sma_hadr_log_shipping
	8) Create table dbo.sma_hadr_transaction_replication_publishers
	9) Create table dbo.sma_applications
	10) Create table dbo.sma_applications_server_xref
	11) Create table dbo.sma_applications_database_xref
	12) Create table dbo.sma_errorlog
	13) Create view dbo.sma_sql_servers	& dbo.sma_sql_servers_including_offline
	14) Create Trigger dbo.tgr_dml__fk_validation_sma_servers__server on dbo.sma_servers
	15) Create Trigger dbo.tgr_dml__sma_servers__server_owner_email__validation on dbo.sma_servers
	16) Create Trigger dbo.tgr_dml__sma_applications__email__validation on dbo.sma_applications
	17) Create table dbo.login_email_mapping
	18) Create Trigger dbo.tgr_dml__login_email_mapping__email__validation on dbo.login_email_mapping

*/

IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

/* ***** 1) Create table dbo.sma_servers ***************************** */
	/*
		ALTER TABLE dbo.sma_servers SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table dbo.sma_servers
		go
		drop table dbo.sma_servers_history
		go
	*/	
create table dbo.sma_servers
(
	[server] varchar(125) not null,
	[server_port] varchar(10) null,
	[domain] varchar(80) null,
	[friendly_name] varchar(500) null,
	[stability] varchar(20) not null default 'dev',
	[priority] tinyint not null default '2',
	[server_type] varchar(20) not null default 'SQLServer',
	[has_hadr] bit not null default 0,
	[hadr_strategy] varchar(50) null default 'standalone',
	[backup_strategy] varchar(255) null default 'Native',
	[server_owner_email] varchar(500) null,
	[rdp_credential] varchar(125) null,
	[sql_credential] varchar(125) null,
	[is_monitoring_enabled] bit not null default 0,
	[is_maintenance_scheduled] bit not null default 0,
	[is_tde_implemented] bit not null default 0,
	[enabled_restart_schedule] bit not null default 0, /* Remove in General */
	[is_onboarded] bit not null default 1,
	[is_decommissioned] bit not null default 0,
	[more_info] varchar(2000) null,
	[created_date_utc] datetime2 not null default getutcdate(),
	[updated_date_utc] datetime2 not null default getutcdate(),
	[updated_by] varchar(255) not null default suser_name()

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,constraint [pk_sma_servers] primary key clustered ([server])
	,constraint [chk_stability] check ( [stability] in ('dev', 'uat', 'qa', 'stg', 'prod') )
	,constraint [chk_priority] check ([priority] in (0,1,2,3,4,5))
	,constraint [chk_server_type] check ([server_type] in ('SQLServer','PostgreSQL'))
	,constraint [chk_hadr_strategy] check ([hadr_strategy] in ('standalone','mirroring','logshipping','sqlcluster','ag'))
	,constraint [chk_backup_strategy] check ([backup_strategy] in ('Native','CommVault','Rubrik','Redgate','VSS'))
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.sma_servers_history));
go

/* ***** 2) Create table dbo.sma_sql_server_extended_info ***************************** */
	/*
		ALTER TABLE dbo.sma_sql_server_extended_info SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table dbo.sma_sql_server_extended_info
		go
		drop table dbo.sma_sql_server_extended_info_history
		go
	*/
create table dbo.sma_sql_server_extended_info
(
	[server] varchar(125) not null,
	[at_server_name] varchar(125) null,
	[server_name] varchar(125) not null,
	[server_ips_CSV] varchar(125) null,
	[alias_names] varchar(100) null,
	[product_version] varchar(30) not null,
	[edition] varchar(50) not null,
	[has_PII_data] bit not null default 0,
	[total_physical_memory_kb] bigint null,
	[cpu_count] smallint not null,
	[rpo_worst_case_minutes] int null,
	[rto_minutes] int null,
	[data_center] varchar(125) null,
	[availability_zone] varchar(125) null,
	[avg_utilization] varchar(2000) null,
	[ticket] varchar(2000) null,
	[purpose] varchar(2000) null,
	[known_challenges] varchar(2000) null,
	[remarks] varchar(2000) null,
	[more_info] varchar(2000) null

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,constraint [pk_sma_sql_server_extended_info] primary key clustered ([server])
	--,index [uq_at_server_name] unique ([at_server_name])
	--,index [uq_server_name] unique ([server_name])
	,constraint [fk_sma_sql_server_extended_info__server] foreign key ([server]) references dbo.sma_servers ([server])
)
with (system_versioning = on (history_table = dbo.sma_sql_server_extended_info_history));
go

alter table dbo.sma_sql_server_extended_info
	add constraint chk_data_center check ([data_center] in ('Hyd','Blr'))
go

/* ***** 3) Create table dbo.sma_sql_server_hosts ***************************** */
	/*
		ALTER TABLE dbo.sma_sql_server_hosts SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table dbo.sma_sql_server_hosts
		go
		drop table dbo.sma_sql_server_hosts_history
		go
	*/
create table dbo.sma_sql_server_hosts
(
	[server] varchar(125) not null,
	[host_name] varchar(125) not null,
	[host_ips] varchar(80) null,
	[host_distribution] varchar(200) null,
	[processor_name] varchar(200) null,
	[ram_mb] bigint null,
	[cpu_count] smallint null,
	[wsfc_name] varchar(125) null,
	[wsfc_ip1] varchar(15) null,
	[wsfc_ip2] varchar(15) null,
	[is_quarantined] bit not null default 0,
	[is_decommissioned] bit not null default 0,
	[more_info] varchar(2000) null

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,constraint [pk_sma_sql_server_hosts] primary key clustered ([server],[host_name])
	,constraint [fk_sma_sql_server_hosts__server] foreign key ([server]) references dbo.sma_servers ([server])
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.sma_sql_server_hosts_history));
go


/* ***** 4) Create table dbo.sma_hadr_ag ***************************** */
	/*
		ALTER TABLE dbo.sma_hadr_ag SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table dbo.sma_hadr_ag
		go
		drop table dbo.sma_hadr_ag_history
		go
	*/
create table dbo.sma_hadr_ag
(
	[server] varchar(125) not null,
	[ag_name] varchar(125) not null,
	[ag_replicas_CSV] varchar(2000) not null,
	[preferred_role] varchar(50) not null default 'Secondary',
	[current_role] varchar(50) not null default 'Secondary',
	[ag_databases_CSV] varchar(max) null,
	[ag_listener_name] varchar(125) null,
	[ag_listener_ip1] varchar(15) null,
	[ag_listener_ip2] varchar(15) null,
	[backup_preference] varchar(125) null,
	[backup_replica] varchar(125) null,
	[is_decommissioned] bit not null default 0,
	[remarks] varchar(2000) null

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,constraint [pk_sma_hadr_ag] primary key clustered ([server],[ag_name])
	,index [ag_listener_ip1] nonclustered ([ag_listener_ip1])
	,index [ag_listener_ip2] nonclustered ([ag_listener_ip2])
	,constraint [fk_sma_hadr_ag__server] foreign key ([server]) references dbo.sma_servers ([server])
	,constraint [chk_preferred_role] check ( [preferred_role] in ('Primary', 'Secondary') )
	,constraint [chk_current_role] check ( [current_role] in ('Primary', 'Secondary') )
	,constraint [chk_backup_preference] check ( [backup_preference] in ('Prefer Secondary','Secondary only','Primary','Any Replica') )
)
with (system_versioning = on (history_table = dbo.sma_hadr_ag_history));
go

--use tempdb;
----drop table dbo.sma_hadr_ag
--select * into tempdb.dbo.sma_hadr_ag from DBA_Admin.dbo.sma_hadr_ag


/* ***** 5) Create table dbo.sma_hadr_sql_cluster ***************************** */
	/*
		ALTER TABLE dbo.sma_hadr_sql_cluster SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table dbo.sma_hadr_sql_cluster
		go
		drop table dbo.sma_hadr_sql_cluster_history
		go
	*/
create table dbo.sma_hadr_sql_cluster
(
	[server] varchar(125) not null,
	[sql_cluster_network_name] varchar(125) not null,
	[preferred_owner_node] varchar(50) null,
	[sql_cluster_ip1] varchar(15) null,
	[sql_cluster_ip2] varchar(15) null,
	[is_decommissioned] bit not null default 0,
	[remarks] varchar(2000) null

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,constraint [pk_sma_hadr_sql_cluster] primary key clustered ([server])
	,index [sql_cluster_network_name] nonclustered ([sql_cluster_network_name])
	,index [sql_cluster_ip1] nonclustered ([sql_cluster_ip1])
	,index [sql_cluster_ip2] nonclustered ([sql_cluster_ip2])
	,constraint [fk_sma_hadr_sql_cluster__server] foreign key ([server]) references dbo.sma_servers ([server])
)
with (system_versioning = on (history_table = dbo.sma_hadr_sql_cluster_history));
go


/* ***** 6) Create table dbo.sma_hadr_mirroring ***************************** */
	/*
		ALTER TABLE dbo.sma_hadr_mirroring SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table dbo.sma_hadr_mirroring
		go
		drop table dbo.sma_hadr_mirroring_history
		go
	*/
create table dbo.sma_hadr_mirroring
(
	[server] varchar(125) not null,
	[preferred_role] varchar(125) not null default 'Principal',
	[mirroring_partner_server] varchar(125) not null,
	[witness_server] varchar(125) null,
	[is_decommissioned] bit not null default 0,
	[remarks] varchar(2000) null

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,constraint [pk_sma_hadr_mirroring] primary key clustered ([server])
	,constraint [fk_sma_hadr_mirroring__server] foreign key ([server]) references dbo.sma_servers ([server])
)
with (system_versioning = on (history_table = dbo.sma_hadr_mirroring_history));
go


/* ***** 7) Create table dbo.sma_hadr_log_shipping ***************************** */
	/*
		ALTER TABLE dbo.sma_hadr_log_shipping SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table dbo.sma_hadr_log_shipping
		go
		drop table dbo.sma_hadr_log_shipping_history
		go
	*/
create table dbo.sma_hadr_log_shipping
(
	[server] varchar(125) not null,
	[databases_CSV] varchar(2000) not null,
	[source_server] varchar(125) not null,
	[is_decommissioned] bit not null default 0,
	[remarks] varchar(2000) null

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,constraint [pk_sma_hadr_log_shipping] primary key clustered ([server],[source_server])
	,constraint [fk_sma_hadr_log_shipping__server] foreign key ([server]) references dbo.sma_servers ([server])
)
with (system_versioning = on (history_table = dbo.sma_hadr_log_shipping_history));
go


/* ***** 8) Create table dbo.sma_hadr_transaction_replication_publishers ***************************** */
	/*
		ALTER TABLE dbo.sma_hadr_transaction_replication_publishers SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table dbo.sma_hadr_transaction_replication_publishers
		go
		drop table dbo.sma_hadr_transaction_replication_publishers_history
		go
	*/
create table dbo.sma_hadr_transaction_replication_publishers
(
	[server] varchar(125) not null,
	[distributor_server] varchar(125) not null,
	[subscribers_CSV] varchar(2000) not null,
	[published_databases_CSV] varchar(2000) not null,
	[is_decommissioned] bit not null default 0,
	[remarks] varchar(2000) null

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,constraint [pk_sma_hadr_transaction_replication_publishers] primary key clustered ([server])
	,constraint [fk_sma_hadr_transaction_replication_publishers__server] foreign key ([server]) references dbo.sma_servers ([server])
)
with (system_versioning = on (history_table = dbo.sma_hadr_transaction_replication_publishers_history));
go


/* ***** 9) Create table dbo.sma_applications ***************************** */
	/*
		ALTER TABLE dbo.sma_applications SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table dbo.sma_applications
		go
		drop table dbo.sma_applications_history
		go
	*/
create table dbo.sma_applications
(
	[application_name] varchar(125) not null,
	[application_owner_email] varchar(125) not null,
	[app_team_email] varchar(125) null,
	[primary_contact_email] varchar(125) null,
	[is_decommissioned] bit not null default 0,
	[more_info] varchar(2000) null,
	[remarks] varchar(2000) null

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,constraint [pk_sma_applications] primary key clustered ([application_name])
)
with (system_versioning = on (history_table = dbo.sma_applications_history));
go

/* ***** 10) Create table dbo.sma_applications_server_xref ***************************** */
	/*
		ALTER TABLE dbo.sma_applications_server_xref SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table dbo.sma_applications_server_xref
		go
		drop table dbo.sma_applications_server_xref_history
		go
	*/
create table dbo.sma_applications_server_xref
(
	[server] varchar(125) not null,
	[application_name] varchar(125) not null,
	[is_valid] bit not null default 0,
	[more_info] varchar(2000) null,
	[remarks] varchar(2000) null

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,constraint [pk_sma_applications_server_xref] primary key clustered ([server],[application_name])
	,index [application_name] nonclustered ([application_name])
	,constraint [fk_sma_applications_server_xref__server] foreign key ([server]) references dbo.sma_servers ([server])
	,constraint [fk_sma_applications_server_xref__application_name] foreign key ([application_name]) references dbo.sma_applications ([application_name])
)
with (system_versioning = on (history_table = dbo.sma_applications_server_xref_history));
go


/* ***** 11) Create table dbo.sma_applications_database_xref ***************************** */
	/*
		ALTER TABLE dbo.sma_applications_database_xref SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table dbo.sma_applications_database_xref
		go
		drop table dbo.sma_applications_database_xref_history
		go
	*/
create table dbo.sma_applications_database_xref
(
	[server] varchar(125) not null,
	[database_name] varchar(125) not null,
	[application_name] varchar(125) not null,
	[is_valid] bit not null default 0,
	[more_info] varchar(2000) null,
	[remarks] varchar(2000) null

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,constraint [pk_sma_applications_database_xref] primary key clustered ([server],[database_name])
	,index [application_name] nonclustered ([application_name])
	,constraint [fk_sma_applications_database_xref__server] foreign key ([server]) references dbo.sma_servers ([server])
	,constraint [fk_sma_applications_database_xref__application_name] foreign key ([application_name]) references dbo.sma_applications ([application_name])
)
with (system_versioning = on (history_table = dbo.sma_applications_database_xref_history));
go



/* ***** 12) Create table dbo.sma_errorlog ***************************** */
-- drop table [dbo].[sma_errorlog]
create table [dbo].[sma_errorlog]
( 	[collection_time] datetime2 not null default sysdatetime(), 
    [function_name] varchar(125) not null, 
	[function_call_arguments] varchar(1000) null, 
	[server] varchar(125) null,
	[error] varchar(1000) not null, 
	[is_resolved] bit not null default 0,
    [remark] varchar(1000) null,
	[executed_by] varchar(125) not null default SUSER_NAME(),
	[executor_program_name] varchar(125) not null default program_name()

	,index [ci_sma_errorlog] clustered ([collection_time])
)
go



/*	***** 13) Create view dbo.sma_sql_servers & dbo.sma_sql_servers_including_offline **************************** */
create or alter view dbo.sma_sql_servers
as
select	server = case when s.server = 'ATPR0SVDNTRY160' then '10.253.33.160' else s.server end, 
		server_port = coalesce(id.sql_instance_port, s.server_port), s.domain, s.friendly_name, 
		s.stability, s.hadr_strategy, hosts = hosts.hosts, s.backup_strategy,
		s.server_owner_email, 
		at_server_name = coalesce(asi.at_server_name,ei.at_server_name), 
		server_name = coalesce(asi.server_name,ei.server_name), 
		asi.machine_name, [current_host_name] = asi.host_name,
		--ag.ag_replicas_CSV, ag.ag_listener_name, ag.ag_listener_ip1, ag.ag_listener_ip2,
		agr.ag_replicas, agr.ag_listeners,
		sc.sql_cluster_network_name,
		product_version = coalesce(asi.product_version,ei.product_version),
		edition = coalesce(asi.edition, ei.edition),
		ei.has_PII_data,
		total_physical_memory_kb = coalesce(asi.total_physical_memory_kb, ei.total_physical_memory_kb),
		cpu_count = coalesce(asi.cpu_count, ei.cpu_count),
		ei.data_center,		
		[server_purpose] = ei.purpose,
		ei.known_challenges,		
		s.is_onboarded,
		s.is_decommissioned,
		[server_more_info] = s.more_info,
		[sql_server_remarks] = ei.remarks
from dbo.sma_servers s
left join dbo.sma_sql_server_extended_info ei
	on ei.server = s.server
left join dbo.vw_all_server_info asi
	on asi.srv_name = s.server
outer apply (
		select top 1 id.sql_instance_port, id.sql_instance
		from dbo.instance_details id
		where id.is_enabled = 1
		and id.sql_instance = s.server
		and id.is_alias = 0
	) id
outer apply (
	select STUFF(
         (SELECT ', ' + h.host_name+'('+h.host_ips+')'
          FROM dbo.sma_sql_server_hosts h
          where 1=1
		  and h.server = s.server
		  and h.is_decommissioned = 0
          FOR XML PATH (''))
          , 1, 1, '')  AS hosts
	) hosts
outer apply (
	select STUFF((	SELECT ', ' + [ag_replica]
					from (
							select distinct [ag_replica] = ltrim(rtrim(r.value))
							from dbo.sma_hadr_ag ag
							outer apply string_split(ag.ag_replicas_CSV,',') r
							where 1=1
							and ag.is_decommissioned = 0
							and ag.server = s.server
						) agr
					FOR XML PATH (''))
			, 1, 1, '')  AS ag_replicas,

			STUFF((	SELECT ', ' + ag.ag_listener_name+'('+ag.ag_listener_ip1+coalesce(','+ag.ag_listener_ip2,'')+')'
					from dbo.sma_hadr_ag ag
					where 1=1
					and ag.is_decommissioned = 0
					and ag.server = s.server
					FOR XML PATH (''))
			, 1, 1, '')  AS ag_listeners
	) agr
left join dbo.sma_hadr_sql_cluster sc
	on sc.server = s.server
	and sc.is_decommissioned = 0
where 1=1
and s.is_decommissioned = 0
--and s.server in ('10.253.33.157','10.253.80.100')
go

create or alter view dbo.sma_sql_servers_including_offline
as
select	server = case when s.server = 'ATPR0SVDNTRY160' then '10.253.33.160' else s.server end, 
		server_port = coalesce(id.sql_instance_port, s.server_port), s.domain, s.friendly_name, 
		s.stability, s.hadr_strategy, hosts = hosts.hosts, s.backup_strategy,
		s.server_owner_email, 
		at_server_name = coalesce(asi.at_server_name,ei.at_server_name), 
		server_name = coalesce(asi.server_name,ei.server_name), 
		asi.machine_name, [current_host_name] = asi.host_name,
		--ag.ag_replicas_CSV, ag.ag_listener_name, ag.ag_listener_ip1, ag.ag_listener_ip2,
		agr.ag_replicas, agr.ag_listeners,
		sc.sql_cluster_network_name,
		product_version = coalesce(asi.product_version,ei.product_version),
		edition = coalesce(asi.edition, ei.edition),
		ei.has_PII_data,
		total_physical_memory_kb = coalesce(asi.total_physical_memory_kb, ei.total_physical_memory_kb),
		cpu_count = coalesce(asi.cpu_count, ei.cpu_count),
		ei.data_center,		
		[server_purpose] = ei.purpose,
		ei.known_challenges,		
		s.is_onboarded,
		s.is_decommissioned,
		[server_more_info] = s.more_info,
		[sql_server_remarks] = ei.remarks
from dbo.sma_servers s
left join dbo.sma_sql_server_extended_info ei
	on ei.server = s.server
left join dbo.vw_all_server_info asi
	on asi.srv_name = s.server
outer apply (
		select top 1 id.sql_instance_port, id.sql_instance, id.host_name
		from dbo.instance_details id
		where id.is_enabled = 1
		and id.sql_instance = s.server
		and id.is_alias = 0
	) id
outer apply (
	select STUFF(
         (SELECT ', ' + h.host_name+'('+h.host_ips+')'
          FROM dbo.sma_sql_server_hosts h
          where 1=1
		  and h.server = s.server
		  --and h.is_decommissioned = 0
          FOR XML PATH (''))
          , 1, 1, '')  AS hosts
	) hosts
outer apply (
	select STUFF((	SELECT ', ' + [ag_replica]
					from (
							select distinct [ag_replica] = ltrim(rtrim(r.value))
							from dbo.sma_hadr_ag ag
							outer apply string_split(ag.ag_replicas_CSV,',') r
							where 1=1
							--and ag.is_decommissioned = 0
							and ag.server = s.server
						) agr
					FOR XML PATH (''))
			, 1, 1, '')  AS ag_replicas,

			STUFF((	SELECT ', ' + ag.ag_listener_name+'('+ag.ag_listener_ip1+coalesce(','+ag.ag_listener_ip2,'')+')'
					from dbo.sma_hadr_ag ag
					where 1=1
					--and ag.is_decommissioned = 0
					and ag.server = s.server
					FOR XML PATH (''))
			, 1, 1, '')  AS ag_listeners
	) agr
left join dbo.sma_hadr_sql_cluster sc
	on sc.server = s.server
	--and sc.is_decommissioned = 0
where 1=1
--and s.is_decommissioned = 0
go


/* ***** 14) Create Trigger dbo.tgr_dml__fk_validation_sma_servers__server on dbo.sma_servers ***************************** */
-- drop trigger dbo.tgr_dml__fk_validation_sma_servers__server;
create or alter trigger dbo.tgr_dml__fk_validation_sma_servers__server
	on dbo.sma_servers
	for insert, update
as 
begin
	--select RunningQuery = 'sma_servers..tgr_dml__fk_validation_sma_servers__server', i.* 
	--from dbo.instance_details id join inserted i on i.server = id.sql_instance and id.is_alias = 0;

	if exists (select * from inserted)
		and not exists (	select 1/0 from dbo.instance_details id join inserted i on i.server = id.sql_instance and id.is_alias = 0 )
	begin
		RAISERROR ('Server entry should exist in [dbo].[instance_details] prior to adding in Inventory table [dbo].[sma_servers].', 16, 1);  
		ROLLBACK TRANSACTION; 
	end
end
go

/* ***** 15) Create Trigger dbo.tgr_dml__sma_servers__server_owner_email__validation on dbo.sma_servers ***************************** */
create or alter trigger dbo.tgr_dml__sma_servers__server_owner_email__validation
	on dbo.sma_servers
	for insert, update
as 
begin
	declare @count int = 0;
	;with t_chk_emails as (
		select s.server_owner_email, emails.email_address
				,is_valid_email = case when emails.email_address LIKE '%_@__%.__%' AND PATINDEX('%[^a-z,0-9,@,.,_,\-]%', emails.email_address) = 0 
									then 1 else 0 end
		from inserted s
		cross apply (select email_address = ltrim(rtrim(value)) from string_split(s.server_owner_email,';')) emails
		where 1=1
		and s.server_owner_email is not null
		and	emails.email_address <> ''
	)
	select @count = COUNT(*)
	from t_chk_emails e
	where e.is_valid_email = 0;

	if @count > 0
	begin
		RAISERROR ('Provided email address(s) is invalid. Kindly ensure to provide semicolon(;) separated emails if multiple emails are provided.', 16, 1);  
		ROLLBACK TRANSACTION; 
	end
end
go


/* ***** 16) Create Trigger dbo.tgr_dml__sma_applications__email__validation on dbo.sma_applications ***************************** */
create or alter trigger dbo.tgr_dml__sma_applications__email__validation
	on dbo.sma_applications
	for insert, update
as 
begin
	declare @count int = 0;

	;with t_emails as (
		select emails_concatenated = coalesce(application_owner_email+';','')+coalesce(app_team_email+';','')+coalesce(primary_contact_email+';','')
		from inserted 
		where 1=1
		and (application_owner_email is not null or app_team_email is not null or primary_contact_email is not null)
	)
	,t_chk_emails as (
		select s.emails_concatenated, emails.email_address
				,is_valid_email = case when emails.email_address LIKE '%_@__%.__%' AND PATINDEX('%[^a-z,0-9,@,.,_,\-]%', emails.email_address) = 0 
									then 1 else 0 end
		from t_emails s
		cross apply (select email_address = ltrim(rtrim(value)) from string_split(s.emails_concatenated,';')) emails
		where 1=1
		and s.emails_concatenated is not null
		and	emails.email_address <> ''
	)
	select @count = COUNT(*)
	from t_chk_emails e
	where e.is_valid_email = 0;

	if @count > 0
	begin
		RAISERROR ('Provided email address(s) is invalid. Kindly ensure to provide semicolon(;) separated emails if multiple emails are provided.', 16, 1);  
		ROLLBACK TRANSACTION; 
	end
end
go


/* ***** 17) Create table dbo.login_email_mapping ***************************** */
-- drop table [dbo].[login_email_mapping]
create table dbo.login_email_mapping
(
	sql_instance_ip		varchar(20) not null,	-- should match with link server name
	sql_instance_name	varchar(125) null,	-- serverproprty(servername)
	server_alias_name	varchar(125) null,
	at_server_name		varchar(125) null,
	[host_name]			varchar(125) null,
	login_name			varchar(125) not null,
	owner_group_email	varchar(2000) not null,
	created_date		datetime not null default getdate(),
	created_by			varchar(125) not null default suser_name(),
	is_deleted			bit not null default 0,
	remarks				text null,
	mapping_id			bigint null

	,index CI_login_email_mapping unique clustered (sql_instance_ip, login_name)
);
go

/* ***** 18) Create Trigger dbo.tgr_dml__login_email_mapping__email__validation on dbo.login_email_mapping ***************************** */
create or alter trigger dbo.tgr_dml__login_email_mapping__email__validation
	on dbo.login_email_mapping
	for insert, update
as 
begin
	declare @count int = 0;
	;with t_chk_emails as (
		select s.owner_group_email, emails.email_address
				,is_valid_email = case when emails.email_address LIKE '%_@__%.__%' AND PATINDEX('%[^a-z,0-9,@,.,_,\-]%', emails.email_address) = 0 
									then 1 else 0 end
		from inserted s
		cross apply (select email_address = ltrim(rtrim(value)) from string_split(s.owner_group_email,';')) emails
		where 1=1
		and s.owner_group_email is not null
		and	emails.email_address <> ''
	)
	select @count = COUNT(*)
	from t_chk_emails e
	where e.is_valid_email = 0;

	if @count > 0
	begin
		RAISERROR ('Provided email address(s) is invalid. Kindly ensure to provide semicolon(;) separated emails if multiple emails are provided.', 16, 1);  
		ROLLBACK TRANSACTION; 
	end
end
go

/*
-- SQLMonitor core table
select * from dbo.instance_details

select * from dbo.sma_servers
select * from dbo.sma_sql_server_extended_info
select * from dbo.sma_sql_server_hosts
select * from dbo.sma_hadr_ag
select * from dbo.sma_hadr_sql_cluster
select * from dbo.sma_hadr_mirroring
select * from dbo.sma_hadr_log_shipping
select * from dbo.sma_hadr_transaction_replication_publishers
select * from dbo.sma_applications
select * from dbo.sma_applications_server_xref
select * from dbo.sma_applications_database_xref
select * from dbo.instance_details_history

select * from dbo.sma_errorlog

select * from dbo.login_email_mapping -- login owner mapping
select * from dbo.all_server_login_expiry_info_dashboard
dbo.usp_collect_all_server_login_expiration_info -> collect login info data from all servers
dbo.usp_send_login_expiry_emails -> send mail notifications for login expiry

-- Populate Inventory Table
exec dbo.usp_populate_sma_sql_instance @server = '192.168.1.2' ,@execute = 1 ,@verbose = 2;

go
*/
