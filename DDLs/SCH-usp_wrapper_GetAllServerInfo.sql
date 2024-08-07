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

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_wrapper_GetAllServerInfo')
    EXEC ('CREATE PROC dbo.usp_wrapper_GetAllServerInfo AS SELECT ''stub version, to be replaced''')
GO

ALTER PROCEDURE dbo.usp_wrapper_GetAllServerInfo
(	@threshold_continous_failure tinyint = 3, /* Send mail only when failure is x times continously */
	@notification_delay_minutes tinyint = 10, /* Send mail only after a gap of x minutes from last mail */ 
	@is_test_alert bit = 0, /* enable for alert testing */
	@verbose tinyint = 0, /* 0 - no messages, 1 - debug messages, 2 = debug messages + table results */
	@recipients varchar(500) = 'some_dba_mail_id@gmail.com', /* Folks who receive the failure mail */
	@alert_key varchar(100) = 'Get-AllServerInfo', /* Subject of Failure Mail */
	@send_error_mail bit = 1, /* Send mail on failure */
	@step_name varchar(100) = 'dbo.all_server_stable_info',
	@schedule_minutes int = 10 /* schedule for execution in minutes */
)
AS 
BEGIN

	/*
		Version:		2024-06-05
		Date:			2024-06-05 - Enhancement#42 - Get [avg_disk_wait_ms]
						2023-07-14 - Enhancement#268 - Add tables sql_agent_job_stats & memory_clerks in Collection Latency Dashboard
						2023-06-19 - Enhancement#262 - Add is_enabled field
						2023-04-02 - Initial Draft

		EXEC dbo.usp_wrapper_GetAllServerInfo @recipients = 'some_dba_mail_id@gmail.com', @step_name = 'dbo.all_server_stable_info'
		EXEC dbo.usp_wrapper_GetAllServerInfo @recipients = 'some_dba_mail_id@gmail.com', @step_name = 'dbo.all_server_volatile_info'
		EXEC dbo.usp_wrapper_GetAllServerInfo @recipients = 'some_dba_mail_id@gmail.com', @step_name = 'dbo.all_server_collection_latency_info'
		EXEC dbo.usp_wrapper_GetAllServerInfo @recipients = 'some_dba_mail_id@gmail.com', @step_name = 'dbo.usp_populate__all_server_volatile_info_history'

		Additional Requirements
		1) Default Global Mail Profile
			-> SqlInstance -> Management -> Right click "Database Mail" -> Configure Database Mail -> Select option "Manage profile security" -> Check Public checkbox, and Select "Yes" for Default for profile that should be set a global default
		2) Make sure context database is set to correct dba database
	*/
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	--SET LOCK_TIMEOUT 60000; -- 60 seconds

	-- Local Variables
	DECLARE @_sql NVARCHAR(MAX);
	DECLARE @_params NVARCHAR(MAX);
	DECLARE @_collection_time datetime = GETDATE();
	DECLARE @_last_sent_failed_active datetime;
	DECLARE @_last_sent_failed_cleared datetime;
	DECLARE @_mail_body_html NVARCHAR(MAX);  
	DECLARE @_subject nvarchar(1000);
	DECLARE @_job_name nvarchar(500);
	DECLARE @_continous_failures tinyint = 0;
	DECLARE @_send_mail bit = 0;

	SET @_job_name = '(dba) '+@alert_key;

	IF (@recipients IS NULL OR @recipients = 'some_dba_mail_id@gmail.com') AND @verbose = 0
		raiserror ('@recipients is mandatory parameter', 20, -1) with log;

	-- Variables for Try/Catch Block
	DECLARE @_profile_name varchar(200);
	DECLARE	@_errorNumber int,
			@_errorSeverity int,
			@_errorState int,
			@_errorLine int,
			@_errorMessage nvarchar(4000);

	SET @_params = N'@verbose tinyint, @schedule_minutes int';

	BEGIN TRY

		IF @verbose > 0
			PRINT 'Start Try Block..';	
		
		IF @step_name = 'dbo.all_server_stable_info'
		BEGIN
			IF @verbose > 0
				PRINT 'dbo.all_server_stable_info';
			SET @_sql = N'-- Stable Info Every 30 Minutes
if	( (select count(distinct srv_name) from dbo.all_server_stable_info) <> (select count(distinct sql_instance) from dbo.instance_details where is_available = 1 and is_enabled = 1 and is_alias = 0) )
	or ( (select max(collection_time) from  dbo.all_server_stable_info) < dateadd(minute, -@schedule_minutes, SYSDATETIME()) )
begin
	--host_distribution, processor_name,
	exec dbo.usp_GetAllServerInfo @result_to_table = ''dbo.all_server_stable_info'', @verbose = @verbose,
				@output = ''srv_name, at_server_name, machine_name, server_name, ip, domain, host_name, fqdn, host_distribution, processor_name, product_version, edition, sqlserver_start_time_utc, total_physical_memory_kb, os_start_time_utc, cpu_count, scheduler_count, major_version_number, minor_version_number'';
end
else
	print ''Did not meet schedule requirement.''+char(13);';
			IF @verbose > 0
				PRINT @_sql;
			EXEC sp_executesql @_sql, @_params, @verbose, @schedule_minutes;
		END
		
		IF @step_name = 'dbo.all_server_volatile_info'
		BEGIN
			IF @verbose > 0
				PRINT 'dbo.all_server_volatile_info';
			SET @_sql = N'-- Volatile Info
exec dbo.usp_GetAllServerInfo @result_to_table = ''dbo.all_server_volatile_info'', @verbose = @verbose, 
			@output = ''srv_name, os_cpu, sql_cpu, pcnt_kernel_mode, page_faults_kb, blocked_counts, blocked_duration_max_seconds, available_physical_memory_kb, system_high_memory_signal_state, physical_memory_in_use_kb, memory_grants_pending, connection_count, active_requests_count, waits_per_core_per_minute, avg_disk_wait_ms'';';
			IF @verbose > 0
				PRINT @_sql;
			EXEC sp_executesql @_sql, @_params, @verbose, @schedule_minutes;
		END

		IF @step_name = 'dbo.all_server_collection_latency_info'
		BEGIN
			IF @verbose > 0
				PRINT 'dbo.all_server_collection_latency_info';
			SET @_sql = N'-- Fetch Collection Info Every 15 Minutes
if not exists (select 1/0 from dbo.all_server_collection_latency_info where collection_time >= dateadd(minute,-@schedule_minutes,getdate()))
begin
	exec dbo.usp_GetAllServerInfo @result_to_table = ''dbo.all_server_collection_latency_info'', @verbose = @verbose, 
				@output = ''srv_name, host_name, performance_counters__latency_minutes, xevent_metrics__latency_minutes, WhoIsActive__latency_minutes, os_task_list__latency_minutes, disk_space__latency_minutes, file_io_stats__latency_minutes, sql_agent_job_stats__latency_minutes, memory_clerks__latency_minutes, wait_stats__latency_minutes, BlitzIndex__latency_days, BlitzIndex_Mode0__latency_days, BlitzIndex_Mode1__latency_days, BlitzIndex_Mode4__latency_days'';
end
else
	print ''Did not meet schedule requirement.''+char(13);';
			IF @verbose > 0
				PRINT @_sql;
			EXEC sp_executesql @_sql, @_params, @verbose, @schedule_minutes;
		END

		IF @step_name = 'dbo.usp_populate__all_server_volatile_info_history'
		BEGIN
			IF @verbose > 0
				PRINT 'dbo.usp_populate__all_server_volatile_info_history';
			SET @_sql = N'-- Populate dbo.all_server_volatile_info_history
exec dbo.usp_populate__all_server_volatile_info_history';
			IF @verbose > 0
				PRINT @_sql;
			EXEC sp_executesql @_sql, @_params, @verbose, @schedule_minutes;
		END

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

		IF @verbose >= 1
		BEGIN
			PRINT CHAR(13);
			PRINT '@_errorNumber => '+convert(varchar,@_errorNumber);
			PRINT '@_errorState => '+convert(varchar,@_errorState);
			PRINT '@_errorMessage => '+@_errorMessage;
			PRINT CHAR(13);
		END

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
END
GO