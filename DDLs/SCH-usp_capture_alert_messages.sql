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

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_capture_alert_messages')
    EXEC ('CREATE PROC dbo.usp_capture_alert_messages AS SELECT ''stub version, to be replaced''')
GO

ALTER PROCEDURE dbo.usp_capture_alert_messages
(	@server_name nvarchar(128) = null, /* Alert Server Name */
	@database_name nvarchar(128) = null, /* Alert database */
	@error_number int = 0, /* Alert Error Number */
	@error_severity tinyint = 0, /* Alert Error Severity */
	@error_message nvarchar(510) = null, /* Alert Error Message */
	@host_instance nvarchar(128) = null, /* Name of the computer running SQL Server. If the SQL Server instance is a named instance, this includes the instance name.  */
	@threshold_continous_failure tinyint = 3, /* Send mail only when failure is x times continously */
	@notification_delay_minutes tinyint = 10, /* Send mail only after a gap of x minutes from last mail */ 
	@is_test_alert bit = 0, /* enable for alert testing */
	@verbose tinyint = 0, /* 0 - no messages, 1 - debug messages, 2 = debug messages + table results */
	@recipients varchar(500) = 'dba_team@gmail.com', /* Folks who receive the failure mail */
	@alert_key varchar(100) = 'Capture-AlertMessages', /* Subject of Failure Mail */
	@send_error_mail bit = 1 /* Send mail on failure */
)
AS 
BEGIN

	/*
		https://learn.microsoft.com/en-us/sql/ssms/agent/use-tokens-in-job-steps?view=sql-server-ver16
		Version:		1.0.0
		Date:			2024-04-26 - Initial Draft

		EXEC dbo.usp_capture_alert_messages
				@server_name = '$(ESCAPE_SQUOTE(A-SVR))',
				@database_name = '$(ESCAPE_SQUOTE(A-DBN))', 
				@error_number = $(ESCAPE_NONE(A-ERR)), 
				@error_severity = $(ESCAPE_NONE(A-SEV)), 
				@error_message = '$(ESCAPE_SQUOTE(A-MSG))', 
				@host_instance = '$(ESCAPE_SQUOTE(SRVR))',
				@recipients = 'dba_team@gmail.com';
		

		Additional Requirements
		1) Default Global Mail Profile
			-> SqlInstance -> Management -> Right click "Database Mail" -> Configure Database Mail -> Select option "Manage profile security" -> Check Public checkbox, and Select "Yes" for Default for profile that should be set a global default
		2) Make sure context database is set to correct dba database
	*/
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET LOCK_TIMEOUT 60000; -- 60 seconds

	-- Local Variables
	DECLARE @_sql NVARCHAR(MAX);
	DECLARE @_collection_time datetime = GETDATE();
	DECLARE @_last_sent_failed_active datetime;
	DECLARE @_last_sent_failed_cleared datetime;
	DECLARE @_mail_body_html NVARCHAR(MAX);  
	DECLARE @_subject nvarchar(1000);
	DECLARE @_job_name nvarchar(500);
	DECLARE @_continous_failures tinyint = 0;
	DECLARE @_send_mail bit = 0;

	SET @_job_name = '(dba) '+@alert_key;

	IF (@recipients IS NULL OR @recipients = 'dba_team@gmail.com') AND @verbose = 0
		raiserror ('@recipients is mandatory parameter', 20, -1) with log;

	-- Variables for Try/Catch Block
	DECLARE @_profile_name varchar(200);
	DECLARE	@_errorNumber int,
			@_errorSeverity int,
			@_errorState int,
			@_errorLine int,
			@_errorMessage nvarchar(4000);

	BEGIN TRY

		IF @verbose > 0
			PRINT 'Start Try Block..';
		insert [dbo].[alert_history]
			([server_name], [database_name], [error_number], [error_severity], [error_message], [host_instance])
		select	@server_name, @database_name, @error_number, @error_severity, @error_message, @host_instance;

	END TRY  -- Perform main logic inside Try/Catch
	BEGIN CATCH
		IF @verbose > 0
			PRINT 'Start Catch Block.'

		SELECT @_errorNumber	 = Error_Number()
				,@_errorSeverity = Error_Severity()
				,@_errorState	 = Error_State()
				,@_errorLine	 = Error_Line()
				,@_errorMessage	 = Error_Message();
		declare @product_version tinyint;
		select @product_version = CONVERT(tinyint,SERVERPROPERTY('ProductMajorVersion'));

		IF OBJECT_ID('tempdb..#CommandLog') IS NOT NULL
			TRUNCATE TABLE #CommandLog;
		ELSE
			CREATE TABLE #CommandLog(collection_time datetime2 not null, status varchar(30) not null);

		IF @verbose > 0
			PRINT CHAR(9)+'Inside Catch Block. Get recent '+cast(@threshold_continous_failure as varchar)+' execution entries from logs..'
		IF @product_version IS NOT NULL
		BEGIN
			SET @_sql = N'
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
			SET @_sql = N'
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
			PRINT CHAR(9)+@_sql;
		INSERT #CommandLog
		EXEC sp_executesql @_sql, N'@_job_name varchar(500), @_threshold_continous_failure tinyint', @_job_name = @_job_name, @_threshold_continous_failure = @threshold_continous_failure;

		SELECT @_continous_failures = COUNT(*)+1 FROM #CommandLog WHERE [status] = 'Failure';

		IF @verbose > 0
			PRINT CHAR(9)+'@_continous_failures => '+cast(@_continous_failures as varchar);
		IF @verbose > 1
		BEGIN
			PRINT CHAR(9)+'SELECT [RunningQuery] = ''Previous Run Status from #CommandLog'', * FROM #CommandLog;'
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
				N'<br><br>Regards,'+
				N'<br>Job ['+@_job_name+']' +
				N'<br><br>--> Continous Failure Threshold -> ' + CONVERT(varchar,@threshold_continous_failure) +
				N'<br>--> Notification Delay (Minutes) -> ' + CONVERT(varchar,@notification_delay_minutes)
		SET @_send_mail = 1;
	END
	ELSE
		PRINT 'IMPORTANT => Failure "Active" mail notification checks not satisfied. '+char(10)+char(9)+'((@send_error_mail = 1) AND (@_continous_failures >= @threshold_continous_failure) AND ( (@last_sent_failed IS NULL) OR (DATEDIFF(MINUTE,@last_sent_failed,GETDATE()) >= @notification_delay_minutes) ))';

	-- Check if No error, then clear active alert if any.
	IF (@send_error_mail = 1) AND (@_errorMessage IS NULL) AND (@_last_sent_failed_active >= ISNULL(@_last_sent_failed_cleared,@_last_sent_failed_active))
	BEGIN
		IF @verbose > 0
			PRINT 'Setting Mail variable values for Job FAILED CLEARED notification..'
		SET @_subject = QUOTENAME(@@SERVERNAME)+' - Job ['+@_job_name+'] - [FAILED] - [CLEARED]';
		SET @_mail_body_html=
				N'Sql Agent job '''+@_job_name+''' has completed successfully. So clearing alert @'+ CONVERT(nvarchar(30),getdate(),121) +'.'+
				N'<br><br>Regards,'+
				N'<br>Job ['+@_job_name+']' +
				N'<br><br>--> Continous Failure Threshold -> ' + CONVERT(varchar,@threshold_continous_failure) +
				N'<br>--> Notification Delay (Minutes) -> ' + CONVERT(varchar,@notification_delay_minutes)
		SET @_send_mail = 1;
	END
	ELSE
		PRINT 'IMPORTANT => Failure "Clearing" mail notification checks not satisfied. '+char(10)+char(9)+'(@send_error_mail = 1) AND (@_errorMessage IS NULL) AND (@_last_sent_failed_active > @_last_sent_failed_cleared)';

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


/*
select @@SPID;
RAISERROR (N'This is message %s %d.', -- Message text.
           19, -- Severity,
           1, -- State,
           N'number', -- First argument.
           5)
	with log; -- Second argument.
-- The message text returned is: This is message number 5.
*/
END
GO