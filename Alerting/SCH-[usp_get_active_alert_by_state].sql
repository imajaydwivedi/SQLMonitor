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

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_get_active_alert_by_state_severity')
    EXEC ('CREATE PROC dbo.usp_get_active_alert_by_state_severity AS SELECT ''stub version, to be replaced''')
GO

ALTER PROCEDURE dbo.usp_get_active_alert_by_state_severity
	@state varchar(15) = null,
	@severity varchar(15) = null,
	@verbose tinyint = 0
AS 
BEGIN
/*
	Version:		1.0.0
	Date:			2024-Oct-17

declare @_rows_affected int; 
exec @_rows_affected = dbo.usp_get_active_alert_by_state_severity --@state = 'Cleared', @severity = 'Critical';
select [is_found] = isnull(@_rows_affected,0);
*/
	SET NOCOUNT ON;

	declare @_rows_affected int = 0;
	declare @_sql nvarchar(max);
	declare @_params nvarchar(max);

	set @_params = N'@state varchar(15), @severity varchar(15)';
	set @_sql = N'
	select	/* dbo.usp_get_active_alert_by_state */ 
			id, a.created_date_utc, alert_key, frequency_minutes, alert_owner_team, t.alert_method,
			state, severity, slack_ts_value, suppress_start_date_utc, suppress_end_date_utc, id_part_no,
			ah.latest_log_time_utc
			,minutes_since_last_log = case when a.state = ''Cleared'' then datediff(minute,ah.latest_log_time_utc,getutcdate()) else null end
	from dbo.sma_alert a join dbo.sma_oncall_teams t
		on t.team_name = a.alert_owner_team
	outer apply (select latest_log_time_utc = max(log_time_utc) from dbo.sma_alert_history ah where ah.alert_id = a.id) ah
	where 1=1
	and a.state in (''Active'',''Acknowledged'',''Suppressed'',''Cleared'')
	'+(case when @state is null then '--' else '' end)+'and a.state = @state
	'+(case when @severity is null then '--' else '' end)+'and a.severity = @severity
	';

	if @verbose > 0
		print (@_sql);
	exec sp_executesql @_sql, @_params, @state, @severity;

	set @_rows_affected = @@ROWCOUNT;

	return @_rows_affected;
END
GO

/*
declare @_rows_affected int; 
exec @_rows_affected = dbo.usp_get_active_alert_by_state_severity --@state = 'Cleared', @severity = 'Critical';
select [is_found] = isnull(@_rows_affected,0);
*/

/*
select * from dbo.sma_alert
select * from dbo.sma_alert_history
select * from dbo.sma_alert_affected_servers


truncate table dbo.sma_alert
truncate table dbo.sma_alert_history
truncate table dbo.sma_alert_affected_servers
*/