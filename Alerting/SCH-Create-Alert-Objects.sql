use DBA
go

/*
	Version -> 2024-08-20
	2024-08-20 - #10 - Setup Alert Engine Using Python+SQLServer
	-----------------

	https://github.com/imajaydwivedi/SQLMonitor/issues/10

	*** Self Pre Steps ***
	----------------------
	1) Python, Git needs to be installed on Inventory server
	2) Credential Manager needs to be installed on Inventory Server

	*** Steps in this Script ****
	-----------------------------
	1) Create table dbo.sma_oncall_teams
	2) Create table dbo.sma_oncall_schedule
	3) Create table dbo.sma_alert_rules
	4) Create sequence object dbo.sma_alert_sequence
	5) Create table dbo.sma_alert
	6) Create table dbo.sma_alert_history
	7) Create table dbo.sma_alert_affected_servers
	8) Create type affected_servers_type
	9) Create table dbo.sma_process_logs
	10) Add credentials in Credential Manager
	11) add DBA team entry

*/

IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

/* ***** 1) Create table dbo.sma_oncall_teams ***************************** */
	/*
		ALTER TABLE dbo.sma_oncall_teams SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table [dbo].[sma_oncall_schedule]
		go
		drop table dbo.sma_oncall_teams
		go
		drop table dbo.sma_oncall_teams_history
		go
	*/
create table [dbo].[sma_oncall_teams]
(
	[team_name] varchar(125) not null,
	[description] varchar(500) not null,
	[team_lead_email] varchar(125) not null,
	[team_email] varchar(125) not null,
	[team_lead_slack_account] varchar(125) null,	
	[team_slack_channel] varchar(125) null,
	[pagerduty_service_key] varchar(125) null,
	[alert_method] varchar(255) not null default 'slack',
	[created_by] varchar(125) not null default suser_name(),
	[created_date_utc] smalldatetime not null default getutcdate()

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,constraint pk_sma_oncall_teams primary key clustered ([team_name])
	,constraint chk_team_alert_method check ( [alert_method] in ('slack','email','pagerduty') )
	,constraint chk_slack_method check ([alert_method] <> 'slack' or ([team_slack_channel] is not null))
	,constraint chk_pagerduty_method check ([alert_method] <> 'pagerduty' or ([pagerduty_service_key] is not null))	
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.sma_oncall_teams_history))
go


/* ***** 2) Create table dbo.sma_oncall_schedule ***************************** */
-- drop table [dbo].[sma_oncall_schedule]
create table [dbo].[sma_oncall_schedule]
(
	[team_name] varchar(125) not null,
	[oncall_role] varchar(50) not null default 'primary', -- primary, secondary
	[oncall_person_name] varchar(125) null,
	[oncall_email] varchar(125) null,
	[oncall_slack_account] varchar(125) null,
	[oncall_start_time] datetime2 not null,
	[oncall_end_time] datetime2 not null,

	[created_by] varchar(125) not null default suser_name(),
	[created_date_utc] smalldatetime not null default getutcdate()

	,index ci_sma_oncall_schedule clustered ([team_name],[oncall_start_time],[oncall_end_time])

	,constraint fk_team_name foreign key ([team_name]) references [dbo].[sma_oncall_teams] ([team_name])
	,constraint chk_oncall_role check ([oncall_role] in ('primary','secondary'))
	,constraint chk_oncall_email_or_slack_provided check ([oncall_email] is not null or [oncall_slack_account] is not null)
)
go

/* ***** 3) Create table dbo.sma_alert_rules ***************************** */
	/*
		ALTER TABLE dbo.sma_alert_rules SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table dbo.sma_alert_rules
		go
		drop table dbo.sma_alert_rules_history
		go
	*/
create table dbo.sma_alert_rules
(	[alert_key] varchar(255) not null,	
	[sql_instance] varchar(125) not null, -- Use '*' when no server needed
	[host_name] varchar(125) null,
	[database_name] varchar(125) null,
	client_app_name varchar(255) null,
	login_name varchar(125) null,
	client_host_name varchar(125) null,
	severity varchar(15) null,
	severity_low_threshold decimal(5,2) null,
	severity_medium_threshold decimal(5,2) null,
	severity_high_threshold decimal(5,2) null,
	severity_critical_threshold decimal(5,2) null,
	alert_owner_team varchar(125) not null, /* Alert Owner */
	delay_minutes smallint null,
	compute_duration_minutes smallint null,
	[start_date_utc] date null,
	[start_time_utc] time null,
	[end_date_utc] date null,
	[end_time_utc] time null,
	copy_dba bit not null default 1,
	created_by varchar(125) not null default suser_name(),
	created_date_utc datetime not null default getutcdate(),
	reference_request varchar(125) not null,
    is_active bit not null default 1
	
	,valid_from DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,valid_to DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME (valid_from,valid_to)

	,constraint pk_sma_alert_rules primary key clustered ([alert_key],[sql_instance])
	,constraint chk_sma_alert_rules__severity check ( [severity] in ('Critical', 'High', 'Medium', 'Low') )

)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.sma_alert_rules_history));
go

/* ***** 4) Create sequence object dbo.sma_alert_sequence ***************************** */
-- drop sequence dbo.sma_alert_sequence  
create sequence dbo.sma_alert_sequence  
    AS bigint start with 1 increment by 1 cycle cache 500;
go


/* ***** 5) Create table dbo.sma_alert ***************************** */
-- drop table [dbo].[sma_alert]
create table [dbo].[sma_alert]
(	[id] bigint not null constraint DF__sma_alert__id default next value for dbo.sma_alert_sequence,
	[created_date_utc] datetime2 not null default sysutcdatetime(),
	[alert_key] varchar(255) not null,
	[alert_owner_team] varchar(125) not null, -- 'DBA'
	[state] varchar(15) not null default 'Active', -- 'Active', 'Acknowledged', 'Suppressed', 'Cleared', 'Resolved'
	[severity] varchar(15) not null default 'High', -- 'Critical', 'High', 'Warning', 'Medium', 'Low'
	[slack_ts_value] varchar(125) null, -- Used for slack converstation in threads
	[frequency_minutes] int not null, -- Time interval for re-evaluation of alert
	[suppress_start_date_utc] datetime null,
	[suppress_end_date_utc] datetime null

	,id_part_no as [id] % 10 persisted

	,constraint pk_sma_alert primary key (id, id_part_no) on ps_dba_bigint_10part (id_part_no)
	,constraint chk_sma_alert__state check ( [state] in ('Active','Acknowledged','Suppressed','Cleared','Resolved') )
	,constraint chk_sma_alert__severity check ( [severity] in ('Critical', 'High', 'Warning', 'Medium', 'Low') )
	,constraint chk_sma_alert__suppress_state check ([state] in ('Active','Acknowledged','Cleared','Resolved') 
								or (	[state] = 'Suppressed' and suppress_start_date_utc is not null and suppress_end_date_utc is not null and  suppress_start_date_utc < suppress_end_date_utc)
								)

	--,index uq_sma_alert__alert_key__severity__active unique (alert_key, severity, alert_owner_team) where [state] in ('Active','Suppressed')
	--,index ix_sma_alert__created_date_utc__alert_key (created_date_utc, alert_key)
	--,index ix_sma_alert__state__active ([state]) where [state] in ('Active','Suppressed')
) on ps_dba_bigint_10part (id_part_no)
go

--drop index ix_sma_alert__alert_key__active on [dbo].[sma_alert]
create unique index ix_sma_alert__alert_key__active on [dbo].[sma_alert]
	(alert_key, id, id_part_no) 
	include ([state]) 
	where [state] in ('Active','Acknowledged','Suppressed','Cleared')
go

/* ***** 6) Create table dbo.sma_alert_history ***************************** */
-- drop table [dbo].[sma_alert_history]
create table [dbo].[sma_alert_history]
(	[log_time_utc] datetime2 not null default sysutcdatetime(),
	[alert_id] bigint not null,
	--[alert_id_part_no] bigint not null,
	[alert_id_part_no] as [alert_id] % 10 persisted,
	[logged_by] varchar(125) not null,
	[header] varchar(500) not null,
	[description] nvarchar(max) null

	,index ci_sma_alert_history clustered ([log_time_utc]) on ps_dba_datetime2_daily ([log_time_utc])
	,index [alert_id__log_time] ([alert_id], [log_time_utc]) on ps_dba_datetime2_daily ([log_time_utc])
	
	--,constraint fk_alert_id foreign key ([alert_id],[alert_id_part_no]) references [dbo].[sma_alert] (id, id_part_no)
) 
on ps_dba_datetime2_daily ([log_time_utc])
go


/* ***** 7) Create table dbo.sma_alert_affected_servers ***************************** */
-- drop table dbo.sma_alert_affected_servers
create table [dbo].[sma_alert_affected_servers]
(
	[alert_id] bigint not null,
	[sql_instance] varchar(125) null,
	[host_name] varchar(125) null,
	[collection_time] datetime2 not null default getdate()

	,index ci_sma_alert_affected_servers clustered ([alert_id])
)
go

/* ***** 8) Create type affected_servers_type ***************************** */
-- drop type affected_servers_type
create type affected_servers_type as table
	( [sql_instance] varchar(125) null, [host_name] varchar(125) null );
GO


/* ***** 9) Create table dbo.sma_process_logs ***************************** */
-- drop table dbo.sma_process_logs
create table [dbo].[sma_process_logs]
(
	[process_start_time_utc] datetime2 not null default sysutcdatetime(),
	[process_name] varchar(255) not null, 
	[process_call_arguments] varchar(1000) null, 
	[process_unique_key] varchar(255) null,
	[server] varchar(125) null,
    [remark] varchar(1000) null,
	[executed_by] varchar(125) not null default SUSER_NAME(),
	[executor_program_name] varchar(125) not null default program_name(),
	[process_end_time_utc] datetime2

	,index [ci_sma_process_logs] clustered ([process_start_time_utc])
	,index [process_name] nonclustered ([process_name],[process_start_time_utc])
)
go


/* ***** 10) Add credentials in Credential Manager ***************************** */
exec dbo.usp_add_credential @server_ip = '*', @user_name = 'sa', @password_string = 'SomeStringPassword', @remarks = 'sa Credential';
go
exec dbo.usp_add_credential @server_ip = '*', @user_name = 'dba_slack_bot_token', @password_string = 'sbot-123456789-0123456789-Id0ntkn0wAny$!@ckT0ken', @remarks = 'DBA Slack Bot User OAuth Token';
go
exec dbo.usp_add_credential @server_ip = '*', @user_name = 'dba_pagerduty_service_key', @password_string = 'some-kind-of-pagerduty-service-key', @remarks = 'DBA Group Pager Duty Service Key';
go
exec dbo.usp_add_credential @server_ip = '*', @user_name = 'smtp_account_password', @password_string = 'SomeStringPassword', @remarks = 'SMTP Account Password';
go
exec dbo.usp_add_credential @server_ip = '*', @user_name = 'dba_slack_bot_signing_secret', @password_string = 'SomeStringPassword', @remarks = 'DBA Slack Bot Signing Secret';
go


/* **** 11) add DBA team entry ********************************************* */
-- add DBA team entry
insert dbo.sma_oncall_teams
(team_name, description, team_lead_email, team_lead_slack_account, team_email, team_slack_channel)
select	team_name = 'DBA', description = 'DBA Team', team_lead_email = m.param_value, 
		team_lead_slack_account = '@Ajay Dwivedi', 
		team_email = t.param_value, 
		team_slack_channel = s.param_value
from dbo.sma_params s
outer apply (select m.param_value from dbo.sma_params m where m.param_key = 'dba_manager_email_id') m
outer apply (select t.param_value from dbo.sma_params t where t.param_key = 'dba_team_email_id') t
where 1=1
and s.param_key = 'dba_slack_channel_id'
go
