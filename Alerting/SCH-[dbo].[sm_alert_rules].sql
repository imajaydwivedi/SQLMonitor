IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

use DBA
go

/*
ALTER TABLE dbo.sm_alert_rules SET ( SYSTEM_VERSIONING = OFF)
go
drop table dbo.sm_alert_rules
go
drop table dbo.sm_alert_rules_history
go
*/
create table dbo.sm_alert_rules
(	rule_id bigint identity(1,1) not null,
	alert_key varchar(255) not null,
	server_friendly_name varchar(255) null,
	--server_owner varchar(500) null,
	[database_name] varchar(255) null,
	client_app_name varchar(255) null,
	login_name varchar(125) null,
	client_host_name varchar(255) null,
	severity varchar(15) null,
	severity_low_threshold decimal(5,2) null,
	severity_medium_threshold decimal(5,2) null,
	severity_high_threshold decimal(5,2) null,
	severity_critical_threshold decimal(5,2) null,
	alert_receiver varchar(500) not null,
	alert_receiver_name varchar(120) not null,
	delay_minutes smallint null,
	compute_duration_minutes smallint null,
	[start_date] date null,
	[start_time] time null,
	[end_date] date null,
	[end_time] time null,
	copy_dba bit not null default 1,
	created_by varchar(125) not null default suser_name(),
	created_date_utc datetime not null default getutcdate(),
	reference_request varchar(125) not null,
    is_active bit not null default 1
	
	,valid_from DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,valid_to DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME (valid_from,valid_to)

	,constraint pk_sm_alert_rules__rule_id primary key clustered (rule_id)
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.sm_alert_rules_history));
go
create unique nonclustered index nci_uq_sm_alert_rules__alert_key__plus on dbo.sm_alert_rules 
    (alert_key, server_friendly_name, [database_name], client_app_name, login_name, client_host_name, severity) where is_active = 1;
go
alter table dbo.sm_alert_rules add constraint chk_sm_alert_rules__severity check ( [severity] in ('Critical', 'High', 'Medium', 'Low') )
go
--alter table dbo.sm_alert_rules add constraint chk_sm_alert_rules__group_by check ( server_friendly_name is null or server_owner is null )
--go
