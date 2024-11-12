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

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_get_alert_by_id')
    EXEC ('CREATE PROC dbo.usp_get_alert_by_id AS SELECT ''stub version, to be replaced''')
GO

ALTER PROCEDURE dbo.usp_get_alert_by_id
	@alert_id bigint,
	@verbose tinyint = 0
AS 
BEGIN
/*
	Version:		1.0.0
	Date:			2024-Oct-10

declare @_rows_affected int; 
exec @_rows_affected = dbo.usp_get_alert_by_id @alert_id = 2;
select [rows_affected] = isnull(@_rows_affected,0);
*/
	SET NOCOUNT ON;

	declare @_rows_affected int = 0;

	select id, created_date_utc, alert_key, frequency_minutes, alert_owner_team, state, severity,
			slack_ts_value, suppress_start_date_utc, suppress_end_date_utc, id_part_no
	from dbo.sma_alert a 
	where 1=1
	and (a.id = @alert_id and a.id_part_no = @alert_id%10);

	set @_rows_affected = @@ROWCOUNT;

	return @_rows_affected;
END
GO

/*
declare @_rows_affected int; 
exec @_rows_affected = dbo.usp_get_alert_by_id @alert_id = 53;
select [rows_affected] = isnull(@_rows_affected,0);
*/

/*
select * from dbo.sma_alert
select * from dbo.sma_alert_history
select * from dbo.sma_alert_affected_servers


truncate table dbo.sma_alert
truncate table dbo.sma_alert_history
truncate table dbo.sma_alert_affected_servers
*/