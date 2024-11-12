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

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_active_requests_count')
    EXEC ('CREATE PROC dbo.usp_active_requests_count AS SELECT ''stub version, to be replaced''')
GO

ALTER PROCEDURE dbo.usp_active_requests_count
	@count smallint = -1 output
--WITH RECOMPILE, EXECUTE AS OWNER 
AS 
BEGIN

	/*
		Version:		1.0.0
		Date:			2022-07-15

		declare @active_requests_count smallint;
		exec usp_active_requests_count @count = @active_requests_count output;
		select [active_requests_count] = @active_requests_count;
	*/
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET LOCK_TIMEOUT 30000; -- 30 seconds
	
	DECLARE @passed_count smallint = @count;

	SELECT @count = COUNT(*)
	FROM	sys.dm_exec_sessions AS s
	LEFT JOIN sys.dm_exec_requests AS r ON r.session_id = s.session_id
	OUTER APPLY (select top 1 dec.most_recent_sql_handle as [sql_handle] from sys.dm_exec_connections dec where dec.most_recent_session_id = s.session_id and dec.most_recent_sql_handle is not null) AS dec
	OUTER APPLY sys.dm_exec_sql_text(COALESCE(r.sql_handle,dec.sql_handle)) AS st
	OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) AS bqp
	OUTER APPLY sys.dm_exec_text_query_plan(r.plan_handle,r.statement_start_offset, r.statement_end_offset) as sqp
	WHERE	s.session_id != @@SPID
		AND (	(CASE	WHEN	s.session_id IN (select ri.blocking_session_id from sys.dm_exec_requests as ri)
						--	Get sessions involved in blocking (including system sessions)
						THEN	1
						WHEN	r.blocking_session_id IS NOT NULL AND r.blocking_session_id <> 0
						THEN	1
						ELSE	0
				END) = 1
				OR
				(CASE	WHEN	s.session_id > 50
								AND r.session_id IS NOT NULL -- either some part of session has active request
								--AND ISNULL(open_resultset_count,0) > 0 -- some result is open
								AND s.status <> 'sleeping'
						THEN	1
						ELSE	0
				END) = 1
				OR
				(CASE	WHEN	s.session_id > 50 AND s.open_transaction_count <> 0
						THEN	1
						ELSE	0
				END) = 1
			);

	IF @passed_count = -1
		SELECT @count as active_requests_count;
END
GO

IF APP_NAME() = 'Microsoft SQL Server Management Studio - Query'
BEGIN
	declare @active_requests_count smallint;
	exec usp_active_requests_count @count = @active_requests_count output;
	select [active_requests_count] = @active_requests_count;
END
go