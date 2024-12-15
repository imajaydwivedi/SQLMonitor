use DBA
go

select *
from dbo.sma_params p
go

update p set param_value = 'C0123456789'
--select *
from dbo.sma_params p
where param_key = 'dba_slack_channel_id'
go


select *
from dbo.sma_oncall_teams
go

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

select *
from dbo.sma_alert_rules
go

insert dbo.sma_alert_rules
(alert_key, sql_instance, host_name, database_name, client_app_name, login_name, client_host_name, severity, severity_low_threshold, severity_medium_threshold, severity_high_threshold, severity_critical_threshold, alert_owner_team, delay_minutes, compute_duration_minutes, start_date_utc, start_time_utc, end_date_utc, end_time_utc, copy_dba, reference_request, is_active)
select alert_key = 'Raise-CPUAlert', sql_instance = '*', host_name = NULL, database_name = NULL, client_app_name = NULL, login_name = NULL, client_host_name = NULL, severity = NULL, severity_low_threshold = 30, severity_medium_threshold = 50, severity_high_threshold = 70, severity_critical_threshold = 85, alert_owner_team = 'DBA', delay_minutes = NULL, compute_duration_minutes = NULL, start_date_utc = NULL, start_time_utc = NULL, end_date_utc = NULL, end_time_utc = NULL, copy_dba = 0, reference_request = 'dba#123', is_active = 1;
go

-- PK,CX -> alert_key, sql_instance





