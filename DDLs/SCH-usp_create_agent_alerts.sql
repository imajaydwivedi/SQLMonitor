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

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_create_agent_alerts')
    EXEC ('CREATE PROC dbo.usp_create_agent_alerts AS SELECT ''stub version, to be replaced''')
GO

ALTER PROCEDURE dbo.usp_create_agent_alerts
(	@drop_create_alert bit = 0, /* When enabled, drop the alert, and recreate */
	@verbose tinyint = 0, /* 0 - no messages, 1 - debug messages, 2 = debug messages + table results */
	@alert_operator_name varchar(255) = null
)
AS 
BEGIN

	/*
		https://learn.microsoft.com/en-us/sql/ssms/agent/use-tokens-in-job-steps?view=sql-server-ver16
		Pre-requisites:	dbo.alert_categories, dbo.alert_history, dbo.usp_capture_alert_messages, job [(dba) Capture-AlertMessages]

		Version -> 2026-06-30
		2026-06-04 - #60 - Add Support for SQLServer on Linux
		2026-01-31 - #3 - Infra to Track Server and Database Configuration Changes
		2024-05-23 - Updated to include Sev 19-25

		EXEC dbo.usp_create_agent_alerts
	*/
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET LOCK_TIMEOUT 60000; -- 60 seconds

	-- Local Variables
	DECLARE @_sql NVARCHAR(MAX);
	DECLARE @_collection_time datetime = GETDATE();
	DECLARE @_job_name nvarchar(500);
	DECLARE @_version_string nvarchar(500);
	DECLARE @c_alert_name varchar(255);
	DECLARE @c_alert_error_number int;
	DECLARE @c_error_severity int;
	DECLARE @c_row_id_string varchar(15);

	-- Variables for Try/Catch Block
	DECLARE	@_errorNumber int,
			@_errorSeverity int,
			@_errorState int,
			@_errorLine int,
			@_errorMessage nvarchar(4000);

	BEGIN TRY

		IF @verbose > 0
			PRINT 'Start Try Block..';

		SET @_version_string = CONVERT(NVARCHAR(500),@@VERSION);

		IF @_version_string like '% on Windows%'
		BEGIN
			if @verbose > 0
				print 'Enable Replace Token in SQLAgent Jobs on Windows based SQLServer.'
			EXEC msdb.dbo.sp_set_sqlagent_properties @alert_replace_runtime_tokens=1;
		END
		ELSE
		BEGIN
			if @verbose > 0
				print 'Skipped - Enable Replace Token in SQLAgent Jobs on Non-Windows based SQLServer.'
		END

		if not (@alert_operator_name is not null and exists (select * from msdb.dbo.sysoperators where name = @alert_operator_name))
		begin
			set @alert_operator_name = null;
			print 'Since operator ['+@alert_operator_name+'] is not found. Neglecting same.';
		end

		DECLARE cur_ForEachErrorNumber CURSOR LOCAL FAST_FORWARD FOR
			with alertCategories as (
				SELECT ac.error_number, ac.error_severity, ac.alert_name, 
						row_id = ROW_NUMBER() over (order by 1/0)
				FROM dbo.alert_categories ac
			)
			select ac.error_number, ac.error_severity, ac.alert_name, s.row_id_string
			from alertCategories ac
			cross apply (select row_id_string = convert(varchar(2), ac.row_id)+'/'+(select convert(char(2),count(*)) from alertCategories)) s;

		OPEN cur_ForEachErrorNumber;
		FETCH NEXT FROM cur_ForEachErrorNumber INTO @c_alert_error_number, @c_error_severity, @c_alert_name, @c_row_id_string;

		WHILE @@fetch_status = 0
		BEGIN
			IF ( @drop_create_alert = 1 
				OR EXISTS ( SELECT 1/0 FROM msdb.dbo.sysalerts WHERE name = @c_alert_name
							AND job_id = '00000000-0000-0000-0000-000000000000' )
			)
			BEGIN
				EXECUTE msdb.dbo.sp_delete_alert @name = @c_alert_name;			
			END

			IF NOT EXISTS ( SELECT 1/0 FROM msdb.dbo.sysalerts WHERE name = @c_alert_name )
			BEGIN
				EXECUTE msdb.dbo.sp_add_alert @name = @c_alert_name, @message_id = @c_alert_error_number, @severity = @c_error_severity, @enabled = 1, @delay_between_responses = 0, @include_event_description_in = 1, @job_name = N'(dba) Capture-AlertMessages';

				if @alert_operator_name is  not null
					EXECUTE msdb.dbo.sp_add_notification @alert_name = @c_alert_name, @operator_name = @alert_operator_name, @notification_method = 1;

				print 'Alert ['+@c_alert_name+'] created.';
			END
			ELSE
				print 'Alert ['+@c_alert_name+'] already exists.';

			print 'Processed '+@c_row_id_string+' => Alert Name: ['+@c_alert_name+'], Error Number: ['+convert(varchar, @c_alert_error_number)+'], Severity: ['+convert(varchar, @c_error_severity)+']';
			FETCH NEXT FROM cur_ForEachErrorNumber INTO @c_alert_error_number, @c_error_severity, @c_alert_name, @c_row_id_string;
		END

		--==== Close/Deallocate cursor
		CLOSE cur_ForEachErrorNumber;
		DEALLOCATE cur_ForEachErrorNumber;

		IF @verbose > 0
			PRINT 'End Try Block..';

	END TRY  -- Perform main logic inside Try/Catch
	BEGIN CATCH
		IF @verbose > 0
			PRINT 'Start Catch Block.'

		print  '	ErrorNumber => '+convert(varchar,ERROR_NUMBER());
		print  '	ErrorSeverity => '+convert(varchar,ERROR_SEVERITY());
		print  '	ErrorState => '+convert(varchar,ERROR_STATE());
		--print  '	ErrorProcedure => '+ERROR_PROCEDURE();
		print  '	ErrorLine => '+convert(varchar,ERROR_LINE());
		print  '	ErrorMessage => '+ERROR_MESSAGE();
	END CATCH
END
GO

