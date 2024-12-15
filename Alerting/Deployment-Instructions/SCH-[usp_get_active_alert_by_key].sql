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

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_get_active_alert_by_key')
    EXEC ('CREATE PROC dbo.usp_get_active_alert_by_key AS SELECT ''stub version, to be replaced''')
GO

ALTER PROCEDURE dbo.usp_get_active_alert_by_key
	@alert_key varchar(255),
	@verbose tinyint = 0
AS 
BEGIN
/*
	Version:		1.0.0
	Date:			2024-Oct-10

declare @_rows_affected int; 
exec @_rows_affected = dbo.usp_get_active_alert_by_key @alert_key = 'Alert-DiskSpace - [21L-LTPABL-1187]';
select [is_found] = isnull(@_rows_affected,0);
*/
	SET NOCOUNT ON;

	declare @_rows_affected int = 0;

	select	id, a.created_date_utc, alert_key, frequency_minutes, alert_owner_team, t.alert_method,
			state, severity, slack_ts_value, suppress_start_date_utc, suppress_end_date_utc, id_part_no
	from dbo.sma_alert a join dbo.sma_oncall_teams t
		on t.team_name = a.alert_owner_team
	where 1=1
	and a.alert_key = @alert_key
	and a.state in ('Active','Acknowledged','Suppressed','Cleared');

	set @_rows_affected = @@ROWCOUNT;

	return @_rows_affected;
END
GO

/*
declare @_rows_affected int; 
exec @_rows_affected = dbo.usp_get_active_alert_by_key @alert_key = 'Alert-DiskSpace';
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