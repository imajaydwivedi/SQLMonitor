IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

use DBA
go

create table dbo.sm_alert
(	id bigint identity(1,1) not null,
	created_date_utc datetime2 not null default sysutcdatetime(),
	alert_key varchar(255) not null,
	email_to varchar(500) not null,
	[state] varchar(15) not null default 'Active', -- 'Active','Suppressed','Cleared'
	[severity] varchar(15) not null default 'High', -- 'Critical', 'High', 'Medium', 'Low'
    last_occurred_date_utc datetime not null default getutcdate(),
	last_notified_date_utc datetime not null default getutcdate(),
	notification_counts int not null default 1,
	suppress_start_date_utc datetime null,
	suppress_end_date_utc datetime null,
    servers_affected varchar(1000) null
)
go
alter table dbo.sm_alert add constraint pk_sm_alert primary key (id)
go
alter table dbo.sm_alert add constraint chk_sm_alert__state check ( [state] in ('Active','Suppressed','Cleared') )
go
alter table dbo.sm_alert add constraint chk_sm_alert__severity check ( [severity] in ('Critical', 'High', 'Medium', 'Low') )
go
alter table dbo.sm_alert add constraint chk_sm_alert__suppress_state 
	check ( (case	when	[state] <> 'Suppressed'
					then	1
					when	[state] = 'Suppressed'
							and ( suppress_start_date_utc is null or suppress_end_date_utc is null )
					then	0
					when	[state] = 'Suppressed'
							and ( datediff(day,suppress_start_date_utc,suppress_end_date_utc) >= 7 )
					then	0
					else	1
					end) = 1 )
go
--create index ix_sm_alert__alert_key__active on dbo.sm_alert (alert_key) where [state] in ('Active','Suppressed')
create unique index uq_sm_alert__alert_key__severity__active on dbo.sm_alert (alert_key, severity, email_to) where [state] in ('Active','Suppressed')
go
create index ix_sm_alert__created_date_utc__alert_key on dbo.sm_alert (created_date_utc, alert_key)
go
create index ix_sm_alert__state__active on dbo.sm_alert ([state]) where [state] in ('Active','Suppressed')
go
create index ix_sm_alert__servers_affected on dbo.sm_alert ([servers_affected]);
go


