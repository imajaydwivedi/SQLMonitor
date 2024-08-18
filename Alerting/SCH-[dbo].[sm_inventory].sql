IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

use DBA
go

/*
ALTER TABLE dbo.sm_inventory SET ( SYSTEM_VERSIONING = OFF)
go
drop table dbo.sm_inventory
go
drop table dbo.sm_inventory_history
go
*/
create table dbo.sm_inventory
( 	server varchar(500) not null, 
	friendly_name varchar(255) not null,
	sql_instance varchar(255) not null,
    host_name varchar(125) null,
	ipv4 varchar(15) null, 
	stability varchar(20) default 'DEV',
	[priority] tinyint not null default 4,
	product_version varchar(30) null,
	has_hadr bit not null default 0,
	hadr_strategy varchar(30) null,
	hadr_preferred_role varchar(50) null,
	hadr_current_role varchar(50) null,
	hadr_partner_friendly_name varchar(255) null,
	hadr_partner_sql_instance varchar(500) null,
	hadr_partner_ipv4 varchar(15) null,
	server_owner varchar(500) null,
    availability_zone varchar(125) null,
	[application] varchar(500) null,
	is_active bit default 1, 
	monitoring_enabled bit default 1,
	other_details varchar(500) null,
	[rdp_credential] varchar(125) null,
	[sql_credential] varchar(125) null
	
	,valid_from DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,valid_to DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME (valid_from,valid_to)

	,constraint pk_sm_inventory primary key clustered (friendly_name)
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.sdt_server_inventory_history))
go
create unique index uq_sm_inventory__server__sql_instance on dbo.sm_inventory (server, sql_instance);
go
create unique index uq_sm_inventory__sql_instance on dbo.sm_inventory (sql_instance);
go
create index ix_sm_inventory__is_active__monitoring_enabled on dbo.sm_inventory (is_active, monitoring_enabled);
go
alter table dbo.sm_inventory add constraint chk_sm_inventory__stability check ( [stability] in ('DEV', 'UAT', 'QA', 'STG', 'PROD', 'PRODDR', 'STGDR','QADR', 'UATDR', 'DEVDR') )
go

