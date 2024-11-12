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

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_run_WhoIsActive')
    EXEC ('CREATE PROC dbo.usp_run_WhoIsActive AS SELECT ''stub version, to be replaced''')
GO

ALTER PROCEDURE dbo.usp_run_WhoIsActive
(	@drop_recreate bit = 0, /* Drop and recreate table */
	@destination_table VARCHAR(4000) = 'dbo.WhoIsActive', /* Destination table Name */
	@send_error_mail bit = 1, /* Send mail on failure */
	@threshold_continous_failure tinyint = 3, /* Send mail only when failure is x times continously */
	@notification_delay_minutes tinyint = 15, /* Send mail only after a gap of x minutes from last mail */ 
	@is_test_alert bit = 0, /* enable for alert testing */
	@verbose tinyint = 0, /* 0 - no messages, 1 - debug messages, 2 = debug messages + table results */
	@recipients varchar(500) = 'dba_team@gmail.com', /* Folks who receive the failure mail */
	@alert_key varchar(100) = 'Run-WhoIsActive', /* Subject of Failure Mail */
	@retention_day int = 15, /* No of days for data retention */
	@purge_flag bit = 1 /* When enabled, then based on @retention_day, old data would be purged */
)
AS 
BEGIN

	/*
		Version:		1.2.1
		Update:			2022-10-12 - Removed Staging Table Logic. Also removed computed columns to avoid single threaded search.
						2022-12-12 - Add @format_output = 0 to get numeric values instead of Human readable format

		EXEC dbo.usp_run_WhoIsActive @recipients = 'dba_team@gmail.com'
		EXEC dbo.usp_run_WhoIsActive @recipients = 'dba_team@gmail.com', @verbose = 2 ,@drop_recreate = 1
	
		Additional Requirements
		1) Default Global Mail Profile
			-> SqlInstance -> Management -> Right click "Database Mail" -> Configure Database Mail -> Select option "Manage profile security" -> Check Public checkbox, and Select "Yes" for Default for profile that should be set a global default
		2) Make sure context database is set to correct dba database
	*/
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET LOCK_TIMEOUT 60000; -- 60 seconds

	/* Derived Parameters */
	--DECLARE @staging_table VARCHAR(4000) = @destination_table+'_Staging';

	IF (@recipients IS NULL OR @recipients = 'dba_team@gmail.com') AND @verbose = 0
		raiserror ('@recipients is mandatory parameter', 20, -1) with log;

	DECLARE @_output VARCHAR(8000);
	SET @_output = 'Declare local variables'+CHAR(10);
	-- Local Variables
	DECLARE @_rows_affected int = 0;
	DECLARE @_sqlString NVARCHAR(MAX);
	DECLARE @_collection_time datetime = GETDATE();
	DECLARE @_columns VARCHAR(8000);
	DECLARE @_cpu_system int;
	DECLARE @_cpu_sql int;
	DECLARE @_last_sent_failed_active datetime;
	DECLARE @_last_sent_failed_cleared datetime;
	DECLARE @_mail_body_html  NVARCHAR(MAX);  
	DECLARE @_subject nvarchar(1000);
	DECLARE @_job_name nvarchar(500);
	DECLARE @_continous_failures tinyint = 0;
	DECLARE @_send_mail bit = 0;
	DECLARE @_output_column_list VARCHAR(8000);
	DECLARE @_crlf nchar(2);
	DECLARE @_tab nchar(1);

	SET @_crlf = NCHAR(13)+NCHAR(10);
	SET @_tab = NCHAR(9);

	SET @_output_column_list = '[collection_time][dd hh:mm:ss.mss][session_id][program_name][login_name][database_name]
							[CPU][used_memory][open_tran_count][status][wait_info][sql_command]
							[blocked_session_count][blocking_session_id][sql_text][%]';

	IF @verbose > 0
		PRINT 'Dynamically fetch @_job_name ..'
	SET @_job_name = '(dba) '+@alert_key;

	IF @verbose > 0
	BEGIN
		PRINT '@destination_table => '+@destination_table;
		--PRINT '@staging_table => '+@staging_table;
	END

	-- Variables for Try/Catch Block
	DECLARE @_profile_name varchar(200);
	DECLARE	@_errorNumber int,
			@_errorSeverity int,
			@_errorState int,
			@_errorLine int,
			@_errorMessage nvarchar(4000);

	BEGIN TRY
		SET @_output += '<br>Start Try Block..'+CHAR(10);
		IF @verbose > 0
			PRINT 'Start Try Block..';

		-- Step 01: Create WhoIsActive table if not exists
		IF @verbose > 0
			PRINT 'Start Step 01: Create WhoIsActive table if not exists..';
		IF ( (OBJECT_ID(@destination_table) IS NULL) OR (@drop_recreate = 1))
		BEGIN
			SET @_output += '<br>Inside Step 01: Create WhoIsActive table if not exists..'+CHAR(10);
		
			IF (@drop_recreate = 1)
			BEGIN
				IF @verbose > 0
					PRINT @_tab+'Inside Step 01: Drop WhoIsActive table if exists..';
				SET @_sqlString = 'if object_id('''+@destination_table+''') is not null drop table '+@destination_table;
				IF @verbose > 1
					PRINT @_tab+@_sqlString;
				EXEC(@_sqlString)
			END

			IF @verbose > 0
				PRINT @_tab+'Inside Step 01: Create WhoIsActive table with @_output_column_list..';
			EXEC dbo.sp_WhoIsActive @get_outer_command=1, @get_task_info=2, @find_block_leaders=1, @get_plans=1, @get_avg_time=1, 
									@get_additional_info=1, @get_transaction_info=1, @get_memory_info = 1, @format_output = 0
									,@output_column_list = @_output_column_list
									,@return_schema = 1, @schema = @_sqlString OUTPUT; 
			SET @_sqlString = REPLACE(@_sqlString, '<table_name>', @destination_table) 
			IF @verbose > 1
				PRINT @_tab+@_sqlString;
			EXEC(@_sqlString)
		END
		ELSE
		BEGIN
			IF @verbose > 1
				PRINT @_tab+'Table '+@destination_table+' already exists.';
		END
		IF @verbose > 0
			PRINT 'End Step 01: Create WhoIsActive table if not exists..'+char(10);

		--	Step 02: Add Indexes& computed Columns
		IF @verbose > 0
			PRINT 'Start Step 02: Add Indexes & computed Columns..';
		IF NOT EXISTS (select * from sys.indexes i where i.type_desc = 'CLUSTERED' and i.object_id = OBJECT_ID(@destination_table))
		BEGIN
			SET @_output += '<br>Inside Step 02: Add Indexes & computed Columns..'+CHAR(10);

			IF @verbose > 0
				PRINT @_tab+'Inside Step 02: Add clustered index..';
			SET @_sqlString = 'CREATE CLUSTERED INDEX ci_'+SUBSTRING(@destination_table,CHARINDEX('.',@destination_table)+1,LEN(@destination_table))+' ON '+@destination_table+' ( [collection_time] ASC )';
			IF @verbose > 1
				PRINT @_tab+@_sqlString;
			EXEC (@_sqlString);
		END

		IF @verbose > 0
			PRINT 'End Step 02: Add Indexes & computed Columns..'+char(10);

		-- Step 03: Purge Old data
		IF @purge_flag = 1
		BEGIN
			IF @verbose > 0
				PRINT 'Start Step 03: Purge Old data..';
			SET @_output += '<br>Execute Step 03: Purge Old data..'+CHAR(10);
			SET @_sqlString = 'DELETE FROM '+@destination_table+' where collection_time < DATEADD(day,-'+cast(@retention_day as varchar)+',getdate());'
			IF @verbose > 1
				PRINT @_tab+@_sqlString;
			EXEC(@_sqlString);
			IF @verbose > 0
				PRINT 'End Step 03: Purge Old data..'+char(10);
		END

		-- Step 04: Populate WhoIsActive table
		IF @verbose > 0
			PRINT 'Start Step 04: Populate WhoIsActive table..';
		SET @_output += '<br>Execute Step 04: Populate WhoIsActive table..'+CHAR(10);
		EXEC dbo.sp_WhoIsActive @get_outer_command=1, @get_task_info=2, @find_block_leaders=1, @get_plans=1, @get_avg_time=1, 
								@get_additional_info=1, @get_transaction_info=1, @get_memory_info = 1, @format_output = 0
								,@output_column_list = @_output_column_list
								,@destination_table = @destination_table;
		SET @_rows_affected = ISNULL(@@ROWCOUNT,0);
		SET @_output += '<br>@_rows_affected is set from @@ROWCOUNT.'+CHAR(10);
		IF @verbose > 0
			PRINT 'End Step 04: Populate WhoIsActive table..'+char(10);
	
		-- Step 05: Return rows affected
		SET @_output += '<br>Execute Step 05: Return rows affected..'+CHAR(10);
		PRINT '[rows_affected] = '+CONVERT(varchar,ISNULL(@_rows_affected,0));
		SET @_output += '<br>FINISH. Script executed without error.'+CHAR(10);
		IF @verbose > 0
			PRINT 'End Step 05: Return rows affected. Script completed without error'
	END TRY  -- Perform main logic inside Try/Catch
	BEGIN CATCH
		IF @verbose > 0
			PRINT 'Start Catch Block.'

		SELECT @_errorNumber	 = Error_Number()
				,@_errorSeverity = Error_Severity()
				,@_errorState	 = Error_State()
				,@_errorLine	 = Error_Line()
				,@_errorMessage	 = Error_Message();

    declare @_product_version tinyint;
	  select @_product_version = CONVERT(tinyint,SERVERPROPERTY('ProductMajorVersion'));

		IF OBJECT_ID('tempdb..#CommandLog') IS NOT NULL
			TRUNCATE TABLE #CommandLog;
		ELSE
			CREATE TABLE #CommandLog(collection_time datetime2 not null, status varchar(30) not null);

		IF @verbose > 0
			PRINT @_tab+'Inside Catch Block. Get recent '+cast(@threshold_continous_failure as varchar)+' execution entries from logs..'
		IF @_product_version IS NOT NULL
		BEGIN
			SET @_sqlString = N'
			DECLARE @threshold_continous_failure tinyint = @_threshold_continous_failure;
			SET @threshold_continous_failure -= 1;
			SELECT	[run_date_time] = msdb.dbo.agent_datetime(run_date, run_time),
					[status] = case when run_status = 1 then ''Success'' else ''Failure'' end
			FROM msdb.dbo.sysjobs jobs
			INNER JOIN msdb.dbo.sysjobhistory history ON jobs.job_id = history.job_id
			WHERE jobs.enabled = 1 AND jobs.name = @_job_name AND step_id = 0 AND run_status NOT IN (2,4) -- not retry/inprogress
			ORDER BY run_date_time DESC OFFSET 0 ROWS FETCH FIRST @threshold_continous_failure ROWS ONLY;' + char(10);
		END
		ELSE
		BEGIN
			SET @_sqlString = N'
			DECLARE @threshold_continous_failure tinyint = @_threshold_continous_failure;
			SET @threshold_continous_failure -= 1;

			SELECT [run_date_time], [status]
			FROM (
				SELECT	[run_date_time] = msdb.dbo.agent_datetime(run_date, run_time),
						[status] = case when run_status = 1 then ''Success'' else ''Failure'' end,
						[seq] = ROW_NUMBER() OVER (ORDER BY msdb.dbo.agent_datetime(run_date, run_time) DESC)
				FROM msdb.dbo.sysjobs jobs
				INNER JOIN msdb.dbo.sysjobhistory history ON jobs.job_id = history.job_id
				WHERE jobs.enabled = 1 AND jobs.name = @_job_name AND step_id = 0 AND run_status NOT IN (2,4) -- not retry/inprogress
			) t
			WHERE [seq] BETWEEN 1 and @threshold_continous_failure
			' + char(10);
		END
		IF @verbose > 1
			PRINT @_tab+@_sqlString;
		INSERT #CommandLog
		EXEC sp_executesql @_sqlString, N'@_job_name varchar(500), @_threshold_continous_failure tinyint', @_job_name = @_job_name, @_threshold_continous_failure = @threshold_continous_failure;

		SELECT @_continous_failures = COUNT(*)+1 FROM #CommandLog WHERE [status] = 'Failure';

		IF @verbose > 0
			PRINT @_tab+'@_continous_failures => '+cast(@_continous_failures as varchar);
		IF @verbose > 1
		BEGIN
			PRINT @_tab+'SELECT [RunningQuery] = ''Previous Run Status from #CommandLog'', * FROM #CommandLog;'
			SELECT [RunningQuery], cl.* 
			FROM #CommandLog cl
			FULL OUTER JOIN (VALUES ('Previous Run Status from #CommandLog')) rq (RunningQuery)
			ON 1 = 1;
		END

		IF @verbose > 0
			PRINT 'End Catch Block.'
	END CATCH	

	/* 
	Check if Any Error, then based on Continous Threshold & Delay, send mail
	Check if No Error, then clear the alert if active,
	*/

	IF @verbose > 0
		PRINT 'Get Last @last_sent_failed &  @last_sent_cleared..';
	SELECT @_last_sent_failed_active = MAX(si.sent_date) FROM msdb..sysmail_sentitems si WHERE si.subject LIKE ('% - Job !['+@_job_name+'!] - ![FAILED!] - ![ACTIVE!]') ESCAPE '!';
	SELECT @_last_sent_failed_cleared = MAX(si.sent_date) FROM msdb..sysmail_sentitems si WHERE si.subject LIKE ('% - Job !['+@_job_name+'!] - ![FAILED!] - ![CLEARED!]') ESCAPE '!';

	IF @verbose > 0
	BEGIN
		PRINT '@_last_sent_failed_active => '+CONVERT(nvarchar(30),@_last_sent_failed_active,121);
		PRINT '@_last_sent_failed_cleared => '+ISNULL(CONVERT(nvarchar(30),@_last_sent_failed_cleared,121),'');
	END

	-- Check if Failed, @threshold_continous_failure is breached, and crossed @notification_delay_minutes
	IF		(@send_error_mail = 1) 
		AND (@_continous_failures >= @threshold_continous_failure) 
		AND ( (@_last_sent_failed_active IS NULL) OR (DATEDIFF(MINUTE,@_last_sent_failed_active,GETDATE()) >= @notification_delay_minutes) )
	BEGIN
		IF @verbose > 0
			PRINT 'Setting Mail variable values for Job FAILED ACTIVE notification..'
		SET @_subject = QUOTENAME(@@SERVERNAME)+' - Job ['+@_job_name+'] - [FAILED] - [ACTIVE]';
		SET @_mail_body_html =
				N'Sql Agent job '''+@_job_name+''' has failed @'+ CONVERT(nvarchar(30),getdate(),121) +'.'+
				N'<br><br>Error Number: ' + convert(varchar, @_errorNumber) + 
				N'<br>Line Number: ' + convert(varchar, @_errorLine) +
				N'<br>Error Message: <br>"' + @_errorMessage +
				N'<br><br>Kindly resolve the job failure based on above error message.'+
				N'<br><br>Below is Job Output till now -><br><br>'+@_output+
				N'<br><br>Regards,'+
				N'<br>Job ['+@_job_name+']' +
				N'<br><br>--> Continous Failure Threshold -> ' + CONVERT(varchar,@threshold_continous_failure) +
				N'<br>--> Notification Delay (Minutes) -> ' + CONVERT(varchar,@notification_delay_minutes)
		SET @_send_mail = 1;
	END
	ELSE
		PRINT 'IMPORTANT => Failure "Active" mail notification checks not satisfied. '+char(10)+@_tab+'((@send_error_mail = 1) AND (@_continous_failures >= @threshold_continous_failure) AND ( (@last_sent_failed IS NULL) OR (DATEDIFF(MINUTE,@last_sent_failed,GETDATE()) >= @notification_delay_minutes) ))';

	-- Check if No error, then clear active alert if any.
	IF (@send_error_mail = 1) AND (@_errorMessage IS NULL) AND (@_last_sent_failed_active >= ISNULL(@_last_sent_failed_cleared,@_last_sent_failed_active))
	BEGIN
		IF @verbose > 0
			PRINT 'Setting Mail variable values for Job FAILED CLEARED notification..'
		SET @_subject = QUOTENAME(@@SERVERNAME)+' - Job ['+@_job_name+'] - [FAILED] - [CLEARED]';
		SET @_mail_body_html =
				N'Sql Agent job '''+@_job_name+''' has completed successfully. So clearing alert @'+ CONVERT(nvarchar(30),getdate(),121) +'.'+
				N'<br><br>Regards,'+
				N'<br>Job ['+@_job_name+']' +
				N'<br><br>--> Continous Failure Threshold -> ' + CONVERT(varchar,@threshold_continous_failure) +
				N'<br>--> Notification Delay (Minutes) -> ' + CONVERT(varchar,@notification_delay_minutes)
		SET @_send_mail = 1;
	END
	ELSE
		PRINT 'IMPORTANT => Failure "Clearing" mail notification checks not satisfied. '+char(10)+@_tab+'(@send_error_mail = 1) AND (@_errorMessage IS NULL) AND (@_last_sent_failed_active > @_last_sent_failed_cleared)';

	IF @is_test_alert = 1
		SET @_subject = 'TestAlert - '+@_subject;

	IF @_send_mail = 1
	BEGIN
		SELECT @_profile_name = p.name
		FROM msdb.dbo.sysmail_profile p 
		JOIN msdb.dbo.sysmail_principalprofile pp ON pp.profile_id = p.profile_id AND pp.is_default = 1
		JOIN msdb.dbo.sysmail_profileaccount pa ON p.profile_id = pa.profile_id 
		JOIN msdb.dbo.sysmail_account a ON pa.account_id = a.account_id 
		JOIN msdb.dbo.sysmail_server s ON a.account_id = s.account_id;

		EXEC msdb.dbo.sp_send_dbmail
				@recipients = @recipients,
				@profile_name = @_profile_name,
				@subject = @_subject,
				@body = @_mail_body_html,
				@body_format = 'HTML';
	END

	IF @_errorMessage IS NOT NULL --AND @send_error_mail = 0
    raiserror (@_errorMessage, 20, -1) with log;
END
GO
