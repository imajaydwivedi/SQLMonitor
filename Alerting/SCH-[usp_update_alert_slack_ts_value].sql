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

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_update_alert_slack_ts_value')
    EXEC ('CREATE PROC dbo.usp_update_alert_slack_ts_value AS SELECT ''stub version, to be replaced''')
GO

ALTER PROCEDURE dbo.usp_update_alert_slack_ts_value
	@alert_id bigint,
	@slack_ts_value varchar(125),
	@verbose tinyint = 0
AS 
BEGIN
/*
	Version:		1.0.0
	Date:			2024-Oct-10

declare @_rows_affected int; 
exec @_rows_affected = dbo.usp_update_alert_slack_ts_value @alert_id = 2, @slack_ts_value = '34567890.45678';
select [is_found] = @_rows_affected
*/
	SET NOCOUNT ON;

	declare @_rows_affected int = 0;

	update a set slack_ts_value = @slack_ts_value
	from dbo.sma_alert a 
	where 1=1
	and (a.id = @alert_id and a.id_part_no = @alert_id%10)
	and a.slack_ts_value is null;

	set @_rows_affected = @@ROWCOUNT;

	return @_rows_affected;
END
GO

/*
declare @_rows_affected int; 
exec @_rows_affected = dbo.usp_update_alert_slack_ts_value @alert_id = 2;
select [is_found] = @_rows_affected
*/

/*
select * from dbo.sma_alert
select * from dbo.sma_alert_history
select * from dbo.sma_alert_affected_servers


truncate table dbo.sma_alert
truncate table dbo.sma_alert_history
truncate table dbo.sma_alert_affected_servers
*/