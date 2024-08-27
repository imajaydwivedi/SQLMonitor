IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET CONCAT_NULL_YIELDS_NULL ON;
--SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
SET ARITHABORT ON;
GO

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_check_sql_agent_jobs')
    EXEC ('CREATE PROC dbo.usp_check_sql_agent_jobs AS SELECT ''stub version, to be replaced''')
GO

ALTER PROCEDURE [dbo].[usp_check_sql_agent_jobs]
(	@job_category_to_include nvarchar(2000) = null, /* Include jobs of only these categories || Delimiter separated list */
	@job_category_to_exclude nvarchar(2000) = null, /* Execute jobs of these categories || Delimiter separated list */
	@jobs_to_include nvarchar(2000) = null, /* Include these jobs only */
	@jobs_to_exclude nvarchar(2000) = null, /* Execute these jobs || Delimiter separated list */
	@delimiter char(4) = ',', /* Delimiter to separate entities in above parameters */
	@send_error_mail bit = 1, /* Send mail on failure */
	@default_threshold_continous_failure tinyint = 2, /* Send mail only when failure is x times continously */
	@default_notification_delay_minutes tinyint = 15, /* Send mail only after a gap of x minutes from last mail */ 
	@default_mail_recipient varchar(500) = 'dba_team@gmail.com', /* Folks who receive the failure mail */
	@alert_key varchar(100) = 'Check-SQLAgentJobs', /* Subject of Failure Mail */
	@reset_stats bit = 0, /* truncate table dbo.sql_agent_job_stats */
	@consider_disabled_jobs bit = 1, /* fetch history for disabled jobs also */
	@drop_recreate bit = 0, /* drop & recreate tables */
	@is_test_alert bit = 0, /* enable for alert testing */
	@verbose tinyint = 0 /* 0 - no messages, 1 - debug messages, 2 = debug messages + table results */	
)
AS 
BEGIN

	/*
		Version:		1.6.1
		Purpose:		https://github.com/imajaydwivedi/SQLMonitor/issues/193
						Monitor SQL Agent jobs, and send mail when thresholds are crossed
		Updates:		2023-07-18 - Ajay=> Issue#269 - Add last execution Duration in table dbo.sql_agent_job_stats
						2023-07-03 - Ajay => Bug#265 - Disabled Jobs Not Appearing in Dashboard Panel SQLAgent Job Activity Monitor
						2023-05-08 - Ajay=> Initial Draft	
						2023-08-16 - Ajay => BugFix - Jobs which does not exist are not getting updated in column dbo.sql_agent_job_thresholds.IsNotFound

		EXEC dbo.usp_check_sql_agent_jobs @default_mail_recipient = 'dba_team@gmail.com'
		EXEC dbo.usp_check_sql_agent_jobs @default_mail_recipient = 'dba_team@gmail.com', @verbose = 2 ,@drop_recreate = 1
	
		Additional Requirements
		1) Default Global Mail Profile
			-> SqlInstance -> Management -> Right click "Database Mail" -> Configure Database Mail -> Select option "Manage profile security" -> Check Public checkbox, and Select "Yes" for Default for profile that should be set a global default
		2) Make sure context database is set to correct dba database
	*/
	SET NOCOUNT ON; 
	--SET ANSI_WARNINGS OFF;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET LOCK_TIMEOUT 60000; -- 60 seconds

	IF (@default_mail_recipient IS NULL OR @default_mail_recipient = 'dba_team@gmail.com') AND @verbose = 0
		raiserror ('@default_mail_recipient is mandatory parameter', 20, -1) with log;

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
	SET @_tab = N'  '; --NCHAR(9);

	
	SET @_output_column_list = '[collection_time][dd hh:mm:ss.mss][session_id][program_name][login_name][database_name]
							[cpu][used_memory][open_tran_count][status][wait_info][sql_command]
							[blocked_session_count][blocking_session_id][sql_text][%]';

	SET @_job_name = '(dba) '+@alert_key;

	-- Variables for Try/Catch Block
	DECLARE @_profile_name varchar(200);
	DECLARE	@_errorNumber int,
			@_errorSeverity int,
			@_errorState int,
			@_errorLine int,
			@_errorMessage nvarchar(4000);

	BEGIN TRY
		SET @_output += '<br>Start Try Block..'+@_crlf;
		IF @verbose > 0
			PRINT 'Start Try Block..';

		-- Drop tables if required
		IF @drop_recreate = 1
		BEGIN
			IF OBJECT_ID('dbo.sql_agent_job_thresholds') is not null
			begin
				SET @_output += '<br>Dropping table dbo.sql_agent_job_thresholds..'+@_crlf;
				EXEC ('DROP TABLE dbo.sql_agent_job_thresholds');
			end
			IF OBJECT_ID('dbo.sql_agent_job_stats') is not null
			begin
				SET @_output += '<br>Dropping table dbo.sql_agent_job_stats..'+@_crlf;
				EXEC ('DROP TABLE dbo.sql_agent_job_stats');
			end
		END

		IF OBJECT_ID('dbo.sql_agent_job_thresholds') IS NULL
		BEGIN
			SET @_output += '<br>Creating table dbo.sql_agent_job_thresholds..'+@_crlf;

			-- Drop table dbo.sql_agent_job_thresholds
			CREATE TABLE dbo.sql_agent_job_thresholds
			(	JobName varchar(255) NOT NULL,
				JobCategory varchar(255) NOT NULL,
				[Expected-Max-Duration(Min)] BIGINT,
				[Continous_Failure_Threshold] int default 2,
				[Successfull_Execution_ClockTime_Threshold_Minutes] bigint null, /* Job should execute successfully at least within this time */
				[StopJob_If_LongRunning] bit default 0,
				[StopJob_If_NotSuccessful_In_ThresholdTime] bit default 0,
				[RestartJob_If_NotSuccessful_In_ThresholdTime] bit default 0,
				[RestartJob_If_Failed] bit default 0,
				[Kill_Job_Blocker] bit default 0,
				[Alert_When_Blocked] bit default 0,
				[EnableJob_If_Found_Disabled] bit NOT NULL default 0,
				[IgnoreJob] bit not null default 0,
				[IsDisabled] bit default 0 not null,
				[IsNotFound] bit default 0 not null,
				[Include_In_MailNotification] bit default 0,
				[Mail_Recepients] varchar(2000) default null,
				CollectionTimeUTC datetime2 default sysutcdatetime(),
				UpdatedDateUTC datetime2 not null default sysutcdatetime(),
				UpdatedBy varchar(125) not null default suser_name(),
				Remarks varchar(2000) null,

				constraint pk_sql_agent_job_thresholds primary key clustered (JobName)
			);
		END

		IF OBJECT_ID('dbo.sql_agent_job_stats') IS NULL
		BEGIN
			SET @_output += '<br>Creating table dbo.sql_agent_job_stats..'+@_crlf;

			-- DROP TABLE dbo.sql_agent_job_stats
			CREATE TABLE dbo.sql_agent_job_stats
			(	JobName varchar(255) NOT NULL,
				Instance_Id bigint,
				[Last_RunTime] datetime2 null,
				[Last_Run_Duration_Seconds] int null,
				[Last_Run_Outcome] varchar(50) null,
				[Last_Successful_ExecutionTime] datetime2 null,				
				[Running_Since] datetime2,
				[Running_StepName] varchar(250) null,
				[Running_Since_Min] bigint,
				[Session_Id] int null,
				[Blocking_Session_Id] int null,
				[Next_RunTime] datetime2 null,
				[Total_Executions] bigint default 0,
				[Total_Success_Count] bigint default 0,
				[Total_Stopped_Count] bigint default 0,
				[Total_Failed_Count] bigint default 0,
				[Continous_Failures] int default 0,
				--[Starts_In_Min] bigint null,
				[<10-Min] bigint not null default 0,
				[10-Min] bigint not null default 0,
				[30-Min] bigint not null default 0,
				[1-Hrs] bigint not null default 0,
				[2-Hrs] bigint not null default 0,
				[3-Hrs] bigint not null default 0,
				[6-Hrs] bigint not null default 0,
				[9-Hrs] bigint not null default 0,
				[12-Hrs] bigint not null default 0,
				[18-Hrs] bigint not null default 0,
				[24-Hrs] bigint not null default 0,
				[36-Hrs] bigint not null default 0,
				[48-Hrs] bigint not null default 0,
				CollectionTimeUTC datetime2 default sysutcdatetime(),
				UpdatedDateUTC datetime2 not null default sysutcdatetime()

				constraint pk_sql_agent_job_stats primary key clustered (JobName)
			);
		END

		IF ( @reset_stats = 1 )
		BEGIN
			IF @verbose > 0
				PRINT @_tab+'Reset table dbo.sql_agent_job_stats..';

			IF @is_test_alert = 0
			BEGIN
				SET @_output += '<br>Reset table dbo.sql_agent_job_stats..'+@_crlf;
				TRUNCATE TABLE dbo.sql_agent_job_stats;
			END
		END

		-- Populate table dbo.sql_agent_job_thresholds
		IF @verbose > 0
			PRINT @_tab+'Populate new jobs into table dbo.sql_agent_job_thresholds..';
		SET @_output += '<br>'+@_tab+'Populate new jobs into table dbo.sql_agent_job_thresholds..'+@_crlf;
		;WITH JobStats AS (
			SELECT	[JobName] = j.name, 
					[JobCategory] = c.name, 
					[Expected-Max-Duration(Min)] = CASE WHEN h.run_status = 1 -- Only successful executions
														THEN (PERCENTILE_DISC(0.99) 
																WITHIN GROUP (ORDER BY ((run_duration/10000*3600 + (run_duration/100)%100*60 + run_duration%100 + 31 ) / 60) ) 
																OVER (PARTITION BY j.name))
														ELSE 5
														END,
					[IgnoreJob] = (CASE WHEN EXISTS (select  v.name as jobname, c.name as category from msdb.dbo.sysjobs_view as v left join msdb.dbo.syscategories as c on c.category_id = v.category_id where c.name like 'repl%' AND v.name = j.name) then 1 else 0 end)
					,h.run_status
			FROM	msdb.dbo.sysjobs AS j
			INNER JOIN msdb.dbo.syscategories AS c
				ON c.category_id = j.category_id
			LEFT JOIN
					msdb.dbo.sysjobhistory AS h
				ON	h.job_id = j.job_id			
			WHERE	h.step_id = 0
			AND j.name NOT IN (select t.JobName COLLATE SQL_Latin1_General_CP1_CI_AS from dbo.sql_agent_job_thresholds as t)
			--and j.name = 'SomeJobName'
			--and h.run_status = 1 
		)
		INSERT dbo.sql_agent_job_thresholds
		([JobName], [JobCategory], [Expected-Max-Duration(Min)], [Continous_Failure_Threshold], [Successfull_Execution_ClockTime_Threshold_Minutes], [StopJob_If_LongRunning], [StopJob_If_NotSuccessful_In_ThresholdTime], [RestartJob_If_NotSuccessful_In_ThresholdTime], [RestartJob_If_Failed], [EnableJob_If_Found_Disabled], [IgnoreJob], [IsDisabled], [IsNotFound], [Include_In_MailNotification], [Mail_Recepients], [Remarks])
		SELECT	[JobName], [JobCategory], 
				[Expected-Max-Duration(Min)] = CASE WHEN MAX([Expected-Max-Duration(Min)]) < 5 THEN 5 ELSE MAX([Expected-Max-Duration(Min)]) END,
				[Continous_Failure_Threshold] = -1, 
				[Successfull_Execution_ClockTime_Threshold_Minutes] = -1, 
				[StopJob_If_LongRunning] = 0, 
				[StopJob_If_NotSuccessful_In_ThresholdTime] = 0, 
				[RestartJob_If_NotSuccessful_In_ThresholdTime] = 0, 
				[RestartJob_If_Failed] = 0, 
				[EnableJob_If_Found_Disabled] = 0, 
				[IgnoreJob] = MAX([IgnoreJob]), 
				[IsDisabled] = 0, 
				[IsNotFound] = 0, 
				[Include_In_MailNotification] = 0, 
				[Mail_Recepients] = null,
				[Remarks] = null
		FROM JobStats js
		GROUP BY [JobName], [JobCategory];
    
		-- Update table dbo.sql_agent_job_thresholds
		IF @verbose > 0
			PRINT @_tab+'Detect/Updates changes in Job Category..';
		SET @_output += '<br>'+@_tab+'Detect/Updates changes in Job Category..'+@_crlf;

		UPDATE sajt 
		SET		JobCategory = sc.name, 
				IsDisabled = (case when sjv.enabled = 1 then 0 else 1 end)
		FROM msdb.dbo.sysjobs_view sjv
		JOIN msdb.dbo.syscategories sc
		ON sc.category_id = sjv.category_id
		JOIN dbo.sql_agent_job_thresholds sajt
		ON sajt.JobName = sjv.name COLLATE SQL_Latin1_General_CP1_CI_AS
		WHERE 1=1
		and (	(sc.name <> sajt.JobCategory COLLATE SQL_Latin1_General_CP1_CI_AS)
			or	(sajt.IsDisabled <> (case when sjv.enabled = 1 then 0 else 1 end))
			);

		IF @verbose > 0
			PRINT @_tab+'Remove jobs that don''t exist..';
		SET @_output += '<br>'+@_tab+'Remove jobs that don''t exist..'+@_crlf;

		DELETE sajt
		FROM dbo.sql_agent_job_thresholds sajt
		WHERE 1=1
		AND sajt.IsNotFound = 0
		AND NOT EXISTS (select 1/0 from msdb.dbo.sysjobs_view sjv where sajt.JobName = sjv.name COLLATE SQL_Latin1_General_CP1_CI_AS);

		if @verbose >= 2
		begin
			select [RunningQuery] = 'dbo.sql_agent_job_thresholds', *
			from dbo.sql_agent_job_thresholds
		end

		if @is_test_alert = 1
		begin
			if @verbose > 0
				PRINT @_tab+'Executing select 1/0..';
			SET @_output += '<br>'+@_tab+'Executing select 1/0..'+@_crlf;
			select 1/0;
		end

		-- Populate table dbo.sql_agent_job_stats
		IF @verbose > 0
			PRINT @_tab+'Populate table dbo.sql_agent_job_stats..';
		SET @_output += '<br>'+@_tab+'Populate table dbo.sql_agent_job_stats..'+@_crlf;

		IF @verbose > 0
			PRINT @_tab+@_tab+'Create table #JobPastHistory..';
		SET @_output += '<br>'+@_tab+'Populate table dbo.JobPastHistory..'+@_crlf;
		IF OBJECT_ID('tempdb..#JobPastHistory') IS NOT NULL
			DROP TABLE #JobPastHistory;
		;with jobs_history_all_instances as
		(
			/* Find Job Execution History more recent from Base Table */
			select	[JobName] = j.name, [Instance_Id] = jh.instance_id,
					[RunDateTime], [RunDurationMinutes], [RunDurationSeconds],
					[RunStatus] = case run_status	when 0 then 'Failed'
													when 1 then 'Succeeded'
													when 2 then 'Retry'
													when 3 then 'Canceled'
													when 4 then 'In Progress'
													else 'None'
													end
			from msdb.dbo.sysjobs_view j
			cross apply (
				select	[RunDateTime] = DATETIMEFROMPARTS(
											   LEFT(padded_run_date, 4),         -- year
											   SUBSTRING(padded_run_date, 5, 2), -- month
											   RIGHT(padded_run_date, 2),        -- day
											   LEFT(padded_run_time, 2),         -- hour
											   SUBSTRING(padded_run_time, 3, 2), -- minute
											   RIGHT(padded_run_time, 2),        -- second
											   0),          -- millisecond
						[RunDurationMinutes] = ((run_duration/10000*3600 + (run_duration/100)%100*60 + run_duration%100 + 31 ) / 60),
						[RunDurationSeconds] = datediff(second,'1900-01-01', (case when jh.run_duration <= 235959
												then convert(datetime, '1900-01-01 '+STUFF(STUFF(RIGHT(REPLICATE('0', 6) + CAST(jh.run_duration AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':'))
												else convert(varchar,dateadd(day,(CAST(LEFT(CAST(jh.run_duration AS VARCHAR), LEN(CAST(jh.run_duration AS VARCHAR)) - 4) AS INT) / 24),'1900-01-01'),23) + ' ' + 
												+ RIGHT('00' + CAST(CAST(LEFT(CAST(jh.run_duration AS VARCHAR), LEN(CAST(jh.run_duration AS VARCHAR)) - 4) AS INT) % 24 AS VARCHAR), 2) + ':' + STUFF(CAST(RIGHT(CAST(jh.run_duration AS VARCHAR), 4) AS VARCHAR(6)), 3, 0, ':')
													 end)),
						run_date ,run_time, jh.instance_id, jh.run_status
				from msdb.dbo.sysjobhistory jh
				CROSS APPLY ( SELECT RIGHT('000000' + CAST(jh.run_time AS VARCHAR(6)), 6), RIGHT('00000000' + CAST(jh.run_date AS VARCHAR(8)), 8) ) AS shp(padded_run_time, padded_run_date)
				inner join dbo.sql_agent_job_thresholds sajt
					on sajt.JobName = j.name COLLATE SQL_Latin1_General_CP1_CI_AS
					and sajt.IgnoreJob = 0
				left join dbo.sql_agent_job_stats as sajs
					on sajs.JobName = sajt.JobName
					and jh.instance_id > (case when sajs.Instance_Id is null then 0 else sajs.Instance_Id end)
				where jh.job_id = j.job_id and jh.step_id = 0
				and jh.run_status in (0,1,3) /* Failed, Success, Canceled */
			) jh
			--where j.name = 'Divide-By-Zero'
		)
		,jobs_history_all_instances_timeframed as (
			select	[JobName], [Instance_Id], [RunDateTime], [RunDurationMinutes], [RunDurationSeconds], [RunStatus],
					[TimeRange] = case	when [RunDurationMinutes]/60 >= 48 then '48-Hrs'
										when [RunDurationMinutes]/60 >= 36 then '36-Hrs'
										when [RunDurationMinutes]/60 >= 24 then '24-Hrs'
										when [RunDurationMinutes]/60 >= 18 then '18-Hrs'
										when [RunDurationMinutes]/60 >= 12 then '12-Hrs'
										when [RunDurationMinutes]/60 >= 9 then '9-Hrs'
										when [RunDurationMinutes]/60 >= 6 then '6-Hrs'
										when [RunDurationMinutes]/60 >= 3 then '3-Hrs'
										when [RunDurationMinutes]/60 >= 2 then '2-Hrs'
										when [RunDurationMinutes]/60 >= 1 then '1-Hrs'
										when [RunDurationMinutes] >= 30 then '30-Min'
										when [RunDurationMinutes] >= 10 then '10-Min'
										else '<10-Min'
									end
		
			from	jobs_history_all_instances
		)
		,jobs_history as (
			select	JobName, [Instance_Id] = max([Instance_Id]), [RunStatus] = NULL, 
					[Last_RunTime] = max([RunDateTime]),
					--[Last_Run_Duration_Seconds] = NULL,
					[Total_Executions] = COUNT(*),
					[Total_Success_Count] = SUM((CASE WHEN [RunStatus] = 'Succeeded' THEN 1 ELSE 0 END)),
					[Total_Stopped_Count] = SUM((CASE WHEN [RunStatus] = 'Canceled' THEN 1 ELSE 0 END)),
					[Total_Failed_Count] = SUM((CASE WHEN [RunStatus] = 'Failed' THEN 1 ELSE 0 END)),
					[Continous_Failures] = null,
					[Last_Successful_ExecutionTime] = MAX((CASE WHEN [RunStatus] = 'Succeeded' THEN [RunDateTime] ELSE NULL END)),
					[<10-Min] = sum(case [TimeRange] when '<10-Min' then 1 else 0 end),
					[10-Min] = sum(case [TimeRange] when '10-Min' then 1 else 0 end),
					[30-Min] = sum(case [TimeRange] when '30-Min' then 1 else 0 end),
					[1-Hrs] = sum(case [TimeRange] when '1-Hrs' then 1 else 0 end),
					[2-Hrs] = sum(case [TimeRange] when '2-Hrs' then 1 else 0 end),
					[3-Hrs] = sum(case [TimeRange] when '3-Hrs' then 1 else 0 end),
					[6-Hrs] = sum(case [TimeRange] when '6-Hrs' then 1 else 0 end),
					[9-Hrs] = sum(case [TimeRange] when '9-Hrs' then 1 else 0 end),
					[12-Hrs] = sum(case [TimeRange] when '12-Hrs' then 1 else 0 end),
					[18-Hrs] = sum(case [TimeRange] when '18-Hrs' then 1 else 0 end),
					[24-Hrs] = sum(case [TimeRange] when '24-Hrs' then 1 else 0 end),
					[36-Hrs] = sum(case [TimeRange] when '36-Hrs' then 1 else 0 end),
					[48-Hrs] = sum(case [TimeRange] when '48-Hrs' then 1 else 0 end)
		
			from jobs_history_all_instances_timeframed jh
			group by jh.JobName
		)
		select	js.JobName, js.[Instance_Id], rs.RunStatus, [Last_RunTime], 
				[Last_Run_Duration_Seconds] = rs.RunDurationSeconds,
				js.Total_Executions, js.Total_Success_Count, js.Total_Stopped_Count,
				js.Total_Failed_Count, js.Continous_Failures, js.Last_Successful_ExecutionTime, [<10-Min], [10-Min], [30-Min], 
				[1-Hrs], [2-Hrs], [3-Hrs], [6-Hrs], [9-Hrs], [12-Hrs], [18-Hrs], [24-Hrs], [36-Hrs], [48-Hrs]
		into	#JobPastHistory
		from jobs_history js
		outer apply ( select i.RunStatus, i.RunDurationSeconds from jobs_history_all_instances_timeframed i 
						where i.JobName = js.JobName and i.Instance_Id = js.Instance_Id
					) as rs;

		if @verbose >= 2
		begin
			select [RunningQuery] = '#JobPastHistory', *
			from #JobPastHistory
		end

		IF @verbose > 0
			PRINT @_tab+@_tab+'Populate table #AgentJobs using master..xp_sqlagent_enum_jobs..';
		SET @_output += '<br>'+@_tab+@_tab+'Populate table #AgentJobs using master..xp_sqlagent_enum_jobs..'+@_crlf;
		if OBJECT_ID('tempdb.dbo.#AgentJobs') is not null
			drop table #AgentJobs
		create table #AgentJobs
		(	Job_ID uniqueidentifier, 
			Last_Run_Date int, 
			Last_Run_Time int, 
			Next_Run_Date int, 
			Next_Run_Time int, 
			Next_Run_Schedule_ID int, 
			Requested_To_Run int, 
			Request_Source int, 
			Request_Source_ID varchar(100), 
			Running int, 
			Current_Step int, 
			Current_Retry_Attempt int, 
			[State] int
		);
		insert into #AgentJobs
		exec master.dbo.xp_sqlagent_enum_jobs 1, garbage;

		if @verbose >= 2
		begin
			select	[RunningQuery] = '#AgentJobs join sysjobs_view', aj.*, v.name, 
					[CurrentTime] = getdate(),
					[LastRunTime] = case	when aj.Last_Run_Date = 0 then NULL
										else CONVERT(varchar, DATEADD(S, (aj.Last_Run_Time / 10000) * 60 * 60 /* hours */
												+ ((aj.Last_Run_Time - (aj.Last_Run_Time / 10000) * 10000) / 100) * 60 /* mins */
												+ (aj.Last_Run_Time - (aj.Last_Run_Time / 100) * 100) /* secs */, CONVERT(datetime, RTRIM(aj.Last_Run_Date), 112)), 120)
										end,
					[NextRunTime] = case	when Next_Run_Date = 0 then NULL
										else CONVERT(varchar, DATEADD(S, (Next_Run_Time / 10000) * 60 * 60 /* hours */
												+ ((Next_Run_Time - (Next_Run_Time / 10000) * 10000) / 100) * 60 /* mins */
												+ (Next_Run_Time - (Next_Run_Time / 100) * 100) /* secs */, CONVERT(datetime, RTRIM(Next_Run_Date), 112)), 120)
										end
			from #AgentJobs aj
			join msdb..sysjobs_view v
				on v.job_id = aj.Job_ID
			where Running = 1
		end

		IF @verbose > 0
			PRINT @_tab+@_tab+'Create table #JobActivityMonitor..';
		SET @_output += '<br>'+@_tab+@_tab+'Create table #JobActivityMonitor..'+@_crlf;

		if object_id('tempdb..#JobActivityMonitor') is not null
			drop table #JobActivityMonitor;
		select	[JobName] = sj.name,
				[Enabled] = sj.enabled,
				rj.[Running],
				[Current_Step] = js.step_name + ' ( Step '+convert(varchar,rj.Current_Step)+')',
				[Session_Id] = blk.session_id,
				[Blocking_Session_Id] = blk.blocking_session_id,
				[State] = case [State]	when 1 then 'Executing'
										when 2 then 'Waiting for thread'
										when 3 then 'Between retries'
										when 4 then 'Idle'
										when 5 then 'Suspended'
										when 6 then 'Obsolete'
										when 7 then 'Performing completion actions'
										else 'Unknown'
										end,
				[StartTime] = case	when Next_Run_Date = 0 or Running = 0 then NULL
									else CONVERT(varchar, DATEADD(S, (Next_Run_Time / 10000) * 60 * 60 /* hours */
											+ ((Next_Run_Time - (Next_Run_Time / 10000) * 10000) / 100) * 60 /* mins */
											+ (Next_Run_Time - (Next_Run_Time / 100) * 100) /* secs */, CONVERT(datetime, RTRIM(Next_Run_Date), 112)), 120)
									end,
				[LastRunTime] = case	when rj.Last_Run_Date = 0 then NULL
									else CONVERT(varchar, DATEADD(S, (rj.Last_Run_Time / 10000) * 60 * 60 /* hours */
											+ ((rj.Last_Run_Time - (rj.Last_Run_Time / 10000) * 10000) / 100) * 60 /* mins */
											+ (rj.Last_Run_Time - (rj.Last_Run_Time / 100) * 100) /* secs */, CONVERT(datetime, RTRIM(rj.Last_Run_Date), 112)), 120)
									end,
				[NextRunTime] = case	when Next_Run_Date = 0 then NULL
									else CONVERT(varchar, DATEADD(S, (Next_Run_Time / 10000) * 60 * 60 /* hours */
											+ ((Next_Run_Time - (Next_Run_Time / 10000) * 10000) / 100) * 60 /* mins */
											+ (Next_Run_Time - (Next_Run_Time / 100) * 100) /* secs */, CONVERT(datetime, RTRIM(Next_Run_Date), 112)), 120)
									end
		into #JobActivityMonitor
		from #AgentJobs as rj
		join msdb.dbo.sysjobs sj on rj.Job_ID = sj.job_id
		left join msdb.dbo.sysjobsteps js on js.job_id = sj.job_id and js.step_id = rj.Current_Step
		outer apply (
					select top 1 der.blocking_session_id, des.session_id
					from sys.dm_exec_sessions des 
					left join sys.dm_exec_requests der 
						on der.session_id = des.session_id
						and der.blocking_session_id > 0
					where des.program_name like 'SQLAgent - TSQL JobStep %'
					and right(cast(js.job_id as nvarchar(50)),10) = RIGHT(substring(des.program_name,30,34),10) 
				) blk
		--where rj.[Running] = 1
		order by name;

		if @verbose >= 2
		begin
			select [RunningQuery] = '#JobActivityMonitor', *
			from #JobActivityMonitor
		end

		IF @verbose > 0
			PRINT @_tab+@_tab+'Create table #JobActivityMonitorConsolidated..';
		SET @_output += '<br>'+@_tab+@_tab+'Create table #JobActivityMonitorConsolidated..'+@_crlf;

		if object_id('tempdb..#JobActivityMonitorConsolidated') is not null
			drop table #JobActivityMonitorConsolidated;
		SELECT	[JobName] = coalesce(jh.[JobName],am.[JobName]), [Instance_Id], 
				[Last_RunTime] = case when am.LastRunTime > jh.Last_RunTime then am.LastRunTime else jh.Last_RunTime end,
				[Last_Run_Duration_Seconds] = jh.[Last_Run_Duration_Seconds],
				RunStatus, [Total_Executions], [Total_Success_Count], [Total_Stopped_Count], [Total_Failed_Count], 
				[Continous_Failures], [Last_Successful_ExecutionTime], 
				[Running_Since] = case when am.Running = 1 then am.StartTime else null end, 
				[Running_StepName] = am.Current_Step, 
				[Running_Since_Min] = datediff(minute,am.StartTime,GETDATE()),
				[Session_Id] = am.Session_Id,
				[Blocking_Session_Id] = am.Blocking_Session_Id,
				[Next_RunTime] = am.NextRunTime, 
				[<10-Min], [10-Min], [30-Min], [1-Hrs], [2-Hrs], [3-Hrs], 
				[6-Hrs], [9-Hrs], [12-Hrs], [18-Hrs], [24-Hrs], [36-Hrs], [48-Hrs], [UpdatedDate] = sysutcdatetime()
				,am.Enabled
		into #JobActivityMonitorConsolidated
		FROM #JobPastHistory jh
		full outer join #JobActivityMonitor am
			on am.JobName = jh.JobName;

		if @verbose >= 2
		begin
			select [RunningQuery] = '#JobActivityMonitorConsolidated', *
			from #JobActivityMonitorConsolidated
		end

		IF @verbose > 0
			PRINT @_tab+@_tab+'Create table #sql_agent_job_stats..';
		SET @_output += '<br>'+@_tab+@_tab+'Create table #sql_agent_job_stats..'+@_crlf;

		if object_id('tempdb..#sql_agent_job_stats') is not null
			drop table #sql_agent_job_stats;
		select	JobName = coalesce(js.JobName, jam.JobName) COLLATE SQL_Latin1_General_CP1_CI_AS,
				Instance_Id = case when isnull(jam.Instance_Id,0) > isnull(js.Instance_Id,0) then jam.Instance_Id else js.Instance_Id end,
				[Last_RunTime] = case when isnull(jam.Last_RunTime,'1970-01-01') > isnull(js.Last_RunTime,'1970-01-01') then jam.Last_RunTime else js.Last_RunTime end,
				[Last_Run_Duration_Seconds] = jam.[Last_Run_Duration_Seconds],
				[Last_Run_Outcome] = case when jam.RunStatus is not null then jam.RunStatus else js.Last_Run_Outcome end COLLATE SQL_Latin1_General_CP1_CI_AS,
				[Last_Successful_ExecutionTime] = case when jam.[Last_Successful_ExecutionTime] is not null 
														then jam.[Last_Successful_ExecutionTime] 
														else js.[Last_Successful_ExecutionTime] 
													end,
				[Running_Since] = jam.[Running_Since],
				[Running_StepName] = jam.[Running_StepName],
				[Running_Since_Min] = jam.[Running_Since_Min],
				[Session_Id] = jam.Session_Id,
				[Blocking_Session_Id] = jam.Blocking_Session_Id,
				[Next_RunTime] = jam.[Next_RunTime],
				[Total_Executions] = isnull(js.Total_Executions,0) + isnull(jam.Total_Executions,0),
				[Total_Success_Count] = isnull(js.Total_Success_Count,0) + isnull(jam.Total_Success_Count,0),
				[Total_Stopped_Count] = isnull(js.[Total_Stopped_Count],0) + isnull(jam.[Total_Stopped_Count],0),
				[Total_Failed_Count] = isnull(js.[Total_Failed_Count],0) + isnull(jam.[Total_Failed_Count],0),
				[Continous_Failures] = isnull(js.[Continous_Failures],0) + isnull(jam.[Continous_Failures],0),
				[<10-Min] = isnull(js.[<10-Min],0) + isnull(jam.[<10-Min],0),
				[10-Min] = isnull(js.[10-Min],0) + isnull(jam.[10-Min],0),
				[30-Min] = isnull(js.[30-Min],0) + isnull(jam.[30-Min],0),
				[1-Hrs] = isnull(js.[1-Hrs],0) + isnull(jam.[1-Hrs],0),
				[2-Hrs] = isnull(js.[2-Hrs],0) + isnull(jam.[2-Hrs],0),
				[3-Hrs] = isnull(js.[3-Hrs],0) + isnull(jam.[3-Hrs],0),
				[6-Hrs] = isnull(js.[6-Hrs],0) + isnull(jam.[6-Hrs],0),
				[9-Hrs] = isnull(js.[9-Hrs],0) + isnull(jam.[9-Hrs],0),
				[12-Hrs] = isnull(js.[12-Hrs],0) + isnull(jam.[12-Hrs],0),
				[18-Hrs] = isnull(js.[18-Hrs],0) + isnull(jam.[18-Hrs],0),
				[24-Hrs] = isnull(js.[24-Hrs],0) + isnull(jam.[24-Hrs],0),
				[36-Hrs] = isnull(js.[36-Hrs],0) + isnull(jam.[36-Hrs],0),
				[48-Hrs] = isnull(js.[48-Hrs],0) + isnull(jam.[48-Hrs],0),
				[CollectionTimeUTC] = coalesce(js.[CollectionTimeUTC],sysutcdatetime()),				
				[UpdatedDateUTC] = SYSUTCDATETIME()
		into #sql_agent_job_stats				
		from #JobActivityMonitorConsolidated jam
		full outer join dbo.sql_agent_job_stats js
			on js.JobName = jam.JobName COLLATE SQL_Latin1_General_CP1_CI_AS
		where 1=1
		and (	jam.Enabled = 1
			or	@consider_disabled_jobs = 1
			);

		if @verbose >= 2
		begin
			select [RunningQuery] = '#sql_agent_job_stats', *
			from #sql_agent_job_stats
		end

		BEGIN TRAN
			IF @verbose > 0
				PRINT @_tab+@_tab+'Truncate & Repopulate table dbo.sql_agent_job_stats..';
			SET @_output += '<br>'+@_tab+@_tab+'Truncate & Repopulate table dbo.sql_agent_job_stats..'+@_crlf;			

			truncate table dbo.sql_agent_job_stats;

			INSERT dbo.sql_agent_job_stats
			(	[JobName], [Instance_Id], [Last_RunTime], [Last_Run_Duration_Seconds], [Last_Run_Outcome], 
				[Last_Successful_ExecutionTime], [Running_Since], [Running_StepName], [Running_Since_Min], [Session_Id], 
				[Blocking_Session_Id], [Next_RunTime], [Total_Executions], [Total_Success_Count], [Total_Stopped_Count], 
				[Total_Failed_Count], [Continous_Failures], [<10-Min], [10-Min], [30-Min], [1-Hrs], [2-Hrs], [3-Hrs], 
				[6-Hrs], [9-Hrs], [12-Hrs], [18-Hrs], [24-Hrs], [36-Hrs], [48-Hrs], [CollectionTimeUTC], [UpdatedDateUTC]
			)
			SELECT	[JobName], [Instance_Id], [Last_RunTime], [Last_Run_Duration_Seconds], [Last_Run_Outcome], 
				[Last_Successful_ExecutionTime], [Running_Since], [Running_StepName], [Running_Since_Min], [Session_Id], 
				[Blocking_Session_Id], [Next_RunTime], [Total_Executions], [Total_Success_Count], [Total_Stopped_Count], 
				[Total_Failed_Count], [Continous_Failures], [<10-Min], [10-Min], [30-Min], [1-Hrs], [2-Hrs], [3-Hrs], 
				[6-Hrs], [9-Hrs], [12-Hrs], [18-Hrs], [24-Hrs], [36-Hrs], [48-Hrs], [CollectionTimeUTC], [UpdatedDateUTC]
			FROM #sql_agent_job_stats;			
		COMMIT TRAN	

		SET @_output += '<br>FINISH. Script executed without error.'+CHAR(10);
		IF @verbose > 0
		BEGIN
			PRINT 'End Try Block..';
			PRINT '***************************************************************'
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

    declare @_product_version tinyint;
	  select @_product_version = CONVERT(tinyint,SERVERPROPERTY('ProductMajorVersion'));

		IF OBJECT_ID('tempdb..#CommandLog') IS NOT NULL
			TRUNCATE TABLE #CommandLog;
		ELSE
			CREATE TABLE #CommandLog(collection_time datetime2 not null, status varchar(30) not null);

		IF @verbose > 0
			PRINT @_tab+'Inside Catch Block. Get recent '+cast(@default_threshold_continous_failure as varchar)+' execution entries from logs..'
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
		EXEC sp_executesql @_sqlString, N'@_job_name varchar(500), @_threshold_continous_failure tinyint', @_job_name = @_job_name, @_threshold_continous_failure = @default_threshold_continous_failure;

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
		BEGIN
			PRINT 'End Catch Block.'
			PRINT '***************************************************************'
		END
	END CATCH	

	

	IF @send_error_mail = 1 /* If failure alert has to be send */
	BEGIN
		/*	Check if Any Error, then based on Continous Threshold & Delay, send mail
			Check if No Error, then clear the alert if active,
		*/
		IF @verbose > 0
			PRINT @_crlf + 'Start Notification Validation Block..';

		IF @verbose > 0
			PRINT @_tab + 'Get Last @last_sent_failed &  @last_sent_cleared..';
		SELECT @_last_sent_failed_active = MAX(si.sent_date) FROM msdb..sysmail_sentitems si WHERE si.subject LIKE ('% - Job !['+@_job_name+'!] - ![FAILED!] - ![ACTIVE!]') ESCAPE '!';
		SELECT @_last_sent_failed_cleared = MAX(si.sent_date) FROM msdb..sysmail_sentitems si WHERE si.subject LIKE ('% - Job !['+@_job_name+'!] - ![FAILED!] - ![CLEARED!]') ESCAPE '!';

		IF @verbose > 0
		BEGIN
			PRINT @_tab + '@_last_sent_failed_active => '+ISNULL(CONVERT(nvarchar(30),@_last_sent_failed_active,121),'');
			PRINT @_tab + '@_last_sent_failed_cleared => '+ISNULL(CONVERT(nvarchar(30),@_last_sent_failed_cleared,121),'');
		END

		-- Check if Failed, @threshold_continous_failure is breached, and crossed @notification_delay_minutes
		IF		(@send_error_mail = 1) 
			AND (@_continous_failures >= @default_threshold_continous_failure) 
			AND ( (@_last_sent_failed_active IS NULL) OR (DATEDIFF(MINUTE,@_last_sent_failed_active,GETDATE()) >= @default_notification_delay_minutes) )
		BEGIN
			IF @verbose > 0
				PRINT @_tab + 'Setting Mail variable values for Job FAILED ACTIVE notification..'
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
					N'<br><br>--> Continous Failure Threshold -> ' + CONVERT(varchar,@default_threshold_continous_failure) +
					N'<br>--> Notification Delay (Minutes) -> ' + CONVERT(varchar,@default_notification_delay_minutes)
			SET @_send_mail = 1;
		END
		ELSE
			PRINT @_crlf+@_tab + 'IMPORTANT => Failure "Active" mail notification checks not satisfied. '+char(10)+@_tab+'((@send_error_mail = 1) AND (@_continous_failures >= @threshold_continous_failure) AND ( (@last_sent_failed IS NULL) OR (DATEDIFF(MINUTE,@last_sent_failed,GETDATE()) >= @notification_delay_minutes) ))';

		-- Check if No error, then clear active alert if any.
		IF (@send_error_mail = 1) AND (@_errorMessage IS NULL) AND (@_last_sent_failed_active >= ISNULL(@_last_sent_failed_cleared,@_last_sent_failed_active))
		BEGIN
			IF @verbose > 0
				PRINT @_tab + 'Setting Mail variable values for Job FAILED CLEARED notification..'
			SET @_subject = QUOTENAME(@@SERVERNAME)+' - Job ['+@_job_name+'] - [FAILED] - [CLEARED]';
			SET @_mail_body_html =
					N'Sql Agent job '''+@_job_name+''' has completed successfully. So clearing alert @'+ CONVERT(nvarchar(30),getdate(),121) +'.'+
					N'<br><br>Regards,'+
					N'<br>Job ['+@_job_name+']' +
					N'<br><br>--> Continous Failure Threshold -> ' + CONVERT(varchar,@default_threshold_continous_failure) +
					N'<br>--> Notification Delay (Minutes) -> ' + CONVERT(varchar,@default_notification_delay_minutes)
			SET @_send_mail = 1;
		END
		ELSE
			PRINT @_crlf+@_tab + 'IMPORTANT => Failure "Clearing" mail notification checks not satisfied. '+char(10)+@_tab+'(@send_error_mail = 1) AND (@_errorMessage IS NULL) AND (@_last_sent_failed_active > @_last_sent_failed_cleared)';

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
					@recipients = @default_mail_recipient,
					@profile_name = @_profile_name,
					@subject = @_subject,
					@body = @_mail_body_html,
					@body_format = 'HTML';
		END

		IF @verbose > 0
		BEGIN
			PRINT @_crlf + 'End Notification Validation Block..';
			PRINT '***************************************************************'
		END
	END

	IF @_errorMessage IS NOT NULL --AND @send_error_mail = 0
		raiserror (@_errorMessage, 20, -1) with log;
END
GO
