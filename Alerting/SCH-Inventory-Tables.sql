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

	*** Steps in this Script ****
	-----------------------------
	1) Create table dbo.sma_inventory
	2) Create table dbo.sma_oncall_teams
	3) Create table dbo.sma_oncall_schedule
	4) Create table dbo.sma_errorlog
	5) Create table dbo.sma_alert_rules
	6) Create sequence object dbo.sma_alert_sequence
	7) Create table dbo.sma_alert	
	8) Create table dbo.sma_alert_history
	9) Create table dbo.sma_alert_affected_servers
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
	[backup_strategy] varchar(255) not null default 'native-backup',
	[server_owner_email] varchar(500) null,
	[rdp_credential] varchar(125) null,
	[sql_credential] varchar(125) null,
	[is_monitoring_enabled] bit not null default 0,
	[is_decommissioned] bit not null default 0,
	[more_info_JSON] varchar(2000) null,
	[created_date_utc] datetime2 not null default getutcdate(),
	[updated_date_utc] datetime2 not null default getutcdate(),
	[updated_by] varchar(255) not null default suser_name()

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,index [uq_server] unique clustered ([server])
	,constraint [chk_sma_inventory__stability] check ( [stability] in ('dev', 'uat', 'qa', 'stg', 'prod') )
	,constraint [chk_priority] check ([priority] in (1,2,3,4,5))
	,constraint [chk_server_type] check ([server_type] in ('SQLServer','PostgreSQL'))
	,constraint [chk_hadr_strategy] check ([hadr_strategy] in ('standalone','mirroring','logshipping','sqlcluster','ag'))
	,constraint [chk_backup_strategy] check ([backup_strategy] in ('native-backup','commvault','rubrik','redgate','vss'))
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
	[at_server_name] varchar(125) not null,
	[server_name] varchar(125) not null,
	[server_ips] varchar(15) null,
	[alias_names] varchar(100) null,
	[product_version] varchar(30) not null,
	[edition] varchar(50) not null,
	[total_physical_memory_kb] bigint null,
	[cpu_count] smallint not null,
	[rpo_worst_case_minutes] int null,
	[rto_minutes] int null,
	[data_center] varchar(125) null,
	[availability_zone] varchar(125) null,
	[avg_utilization_JSON] varchar(2000) null,
	[ticket] varchar(2000) null,
	[purpose] varchar(2000) null,
	[known_challenges] varchar(2000) null,
	[remarks] varchar(2000) null,
	[more_info_JSON] varchar(2000) null

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,index [uq_server] unique clustered ([server])
	,index [uq_at_server_name] unique ([at_server_name])
	,index [uq_server_name] unique ([server_name])
	,
)
with (system_versioning = on (history_table = dbo.sma_sql_server_extended_info_history));
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
	[host_ips] varchar(80) not null,
	[host_distribution] varchar(200) null,
	[processor_name] varchar(200) null,
	[ram_mb] bigint null,
	[cpu_count] smallint null,
	[more_info_JSON] varchar(2000) null

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,index [uq_server__host_name] unique clustered ([server],[host_name])
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.sma_sql_server_hosts_history));
go

/* ***** 4) Create table dbo.sma_applications ***************************** */
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
	[more_app_info] varchar(2000) null

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,index [uq_application_name] unique clustered ([application_name])
)
with (system_versioning = on (history_table = dbo.sma_applications_history));
go

/* ***** 5) Create table dbo.sma_applications_server_xref ***************************** */
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
	[application_name] varchar(125) not null

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,index [cx_sma_applications_server_xref] clustered ([server])
	,index [application_name] nonclustered ([application_name])
)
with (system_versioning = on (history_table = dbo.sma_applications_server_xref_history));
go

/* ***** 6) Create table dbo.sma_applications_database_xref ***************************** */
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
	[application_name] varchar(125) not null

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,index [cx_sma_applications_server_xref] clustered ([server],[database_name])
	,index [application_name] nonclustered ([application_name])
)
with (system_versioning = on (history_table = dbo.sma_applications_database_xref_history));
go

/*	***** 7) Create view dbo.vw_sma_server **************************** */
create or alter view dbo.sma_sql_servers
as
select 1 as [dummy]
go


