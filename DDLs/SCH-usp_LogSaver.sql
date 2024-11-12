IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
SET ARITHABORT ON;
GO

IF OBJECT_ID('dbo.usp_LogSaver') IS NULL
	EXEC('CREATE PROCEDURE dbo.usp_LogSaver AS select 1 as dummy;');
GO
ALTER PROCEDURE [dbo].[usp_LogSaver]
(
	@log_used_pct_threshold tinyint = 80,
	@log_used_gb_threshold int = NULL,
	@threshold_condition varchar(5) = 'or', /* and | or */
	@databases varchar(max) = NULL, /* Comma separated list of databases. -ve (negative) if database has to be excluded */
	@email_recipients varchar(max) = 'dba_team@gmail.com',
	@retention_days int = 30,
	@purge_table bit = 1,
	@drop_create_table bit = 0,
	@kill_spids bit = 0,
	@send_email bit = 0,
	@skip_autogrowth_validation bit = 0,
	@verbose tinyint = 0 /* 1 => messages, 2 => messages + table results */
)
AS
BEGIN
/*	Purpose:		
	Modifications:	2023-08-11 - Initial Draft
	

	exec usp_LogSaver 
				--@databases = 'Facebook,-DBA,Dbatools,tempdb',
				--@databases = '-DBA',
				@log_used_pct_threshold = 80,
				@log_used_gb_threshold = 500,
				@threshold_condition = 'or',
				@skip_autogrowth_validation = 0,
				@email_recipients = 'sqlagentservice@gmail.com',
				@purge_table = 0,
				@kill_spids = 0,
				@send_email = 0,
				@drop_create_table = 0,
				@verbose = 2;

	select * from dbo.log_space_consumers where collection_time > dateadd(minute,-10,getdate())
*/
	SET NOCOUNT ON
	SET XACT_ABORT ON
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @_start_time datetime2;
	SET @_start_time = SYSDATETIME();

	IF @verbose >= 1
		PRINT '('+convert(varchar, getdate(), 21)+') Declaring local variables..';

	DECLARE @_spid int
	DECLARE @_sql varchar(max)
	DECLARE @_params nvarchar(max)
	DECLARE @_email_body varchar(max) = ''
	DECLARE @_email_subject nvarchar(255)
	DECLARE @_log_used_pct decimal(38,2)
	DECLARE @_error varchar(8000)
	DECLARE @_is_pct_threshold_valid bit = 0;
	DECLARE @_is_gb_threshold_valid bit = 0;
	DECLARE @_thresholds_validated bit = 0;
	DECLARE @_exists_valid_autogrowing_file bit = 0;
	DECLARE @_transaction_start_time datetime;

	DECLARE @_tab nchar(1) = CHAR(9);

	declare @c_database_name sysname;
	declare @c_recovery_model varchar(50);
	declare @c_log_reuse_wait_desc varchar(125);
	declare @c_log_size_mb numeric(12,2);
	declare @c_log_used_pct numeric(6,2);

	IF @verbose >= 1
		PRINT '('+convert(varchar, getdate(), 21)+') Creating #temp tables..';

	IF OBJECT_ID('tempdb..#logspace') IS NOT NULL
		DROP TABLE #logspace;
	CREATE TABLE #logspace
	(	[database_name] sysname,
		log_size_mb   decimal(38,2),
		log_used_pct  decimal(38,2),
		log_status    int
	);

	IF OBJECT_ID('tempdb..#dbcc_opentran') IS NOT NULL
		DROP TABLE #dbcc_opentran;
	CREATE TABLE #dbcc_opentran
	(	[database_name]  sysname NULL,
		transaction_property varchar(100) NULL,
		transaction_property_value varchar(1000) NULL
	);

	IF OBJECT_ID('tempdb..#log_space_consumers') IS NOT NULL
		DROP TABLE #log_space_consumers;
	CREATE TABLE #log_space_consumers 
	(
		[collection_time] datetime2 not null
		,[database_name] sysname not null
		,[recovery_model] varchar(20) not null
		,[log_reuse_wait_desc] varchar(125) not null
		,[log_size_mb] decimal(20, 2) not null
		,[log_used_mb] decimal(20, 2) not null
		,[exists_valid_autogrowing_file] bit null
		,[log_used_pct] decimal(10, 2) default 0.0 not null
		,[log_used_pct_threshold] decimal(10,2) not null
		,[log_used_gb_threshold] decimal(20,2) null
		,[spid] int null
		,[transaction_start_time] datetime null
		,[login_name] sysname null
		,[program_name] sysname null
		,[host_name] sysname null
		,[host_process_id] int null
		,[command] varchar(16) null
		,[additional_info] varchar(255) null
		,[action_taken] varchar(100) null
		,[sql_text] varchar(max) null
		,[is_pct_threshold_valid] bit default 0 not null
		,[is_gb_threshold_valid] bit default 0 not null
		,[threshold_condition] varchar(5) not null
		,[thresholds_validated] bit default 0 not null
	);

	IF OBJECT_ID('dbo.log_space_consumers') IS NOT NULL AND @drop_create_table = 1
		EXEC ('drop table dbo.log_space_consumers');

	IF OBJECT_ID('dbo.log_space_consumers') IS NULL
	BEGIN
		SET @_sql = 'SELECT * INTO dbo.log_space_consumers FROM #log_space_consumers;
		CREATE CLUSTERED INDEX ci_log_space_consumers ON dbo.log_space_consumers (collection_time);'

		EXEC (@_sql);
	END

	-- Create Temporary Tables
	IF OBJECT_ID('tempdb..#db_list_from_params') IS NOT NULL
		DROP TABLE #db_list_from_params;
	CREATE TABLE #db_list_from_params ([database_name] sysname, [skip_db] bit);

	IF OBJECT_ID('tempdb..#db_list') IS NOT NULL
		DROP TABLE #db_list;
	CREATE TABLE #db_list ([database_name] sysname, [recovery_model] varchar(50), [log_reuse_wait_desc] varchar(125));	

	IF @databases IS NOT NULL
	BEGIN
		IF @verbose >= 1
			PRINT '('+convert(varchar, getdate(), 21)+') Extracting database names from ('+@databases+') parameter value..';
		;WITH t1([database_name], [databases]) AS 
		(
			SELECT	CAST(LEFT(@databases, CHARINDEX(',',@databases+',')-1) AS VARCHAR(500)) as [database_name],
					STUFF(@databases, 1, CHARINDEX(',',@databases+','), '') as [databases]
			--
			UNION ALL
			--
			SELECT	CAST(LEFT([databases], CHARINDEX(',',[databases]+',')-1) AS VARChAR(500)) AS [database_name],
					STUFF([databases], 1, CHARINDEX(',',[databases]+','), '')  as [databases]
			FROM t1
			WHERE [databases] > ''	
		)
		INSERT #db_list_from_params ([database_name], [skip_db])
		SELECT	[database_name] = case when left(ltrim(rtrim([database_name])),1) = '-' then RIGHT(ltrim(rtrim([database_name])),len(ltrim(rtrim([database_name])))-1) else ltrim(rtrim([database_name])) end, 
				[skip_db] = case when left(ltrim(rtrim([database_name])),1) = '-' then 1 else 0 end
		FROM t1
		OPTION (MAXRECURSION 32000);

		IF @verbose >= 2
		BEGIN
			PRINT '('+convert(varchar, getdate(), 21)+') select * from #db_list_from_params..'
			select running_query, t.*
			from #db_list_from_params t
			full outer join (values ('#db_list_from_params') )dummy(running_query) on 1 = 1
		END
	END
	
	IF @databases IS NOT NULL
	BEGIN
		IF @verbose >= 1
			PRINT '('+convert(varchar, getdate(), 21)+') Extracting database names from ('+@databases+') parameter value..';

		IF EXISTS (SELECT 1/0 FROM #db_list_from_params p WHERE p.skip_db = 0)
		BEGIN
			IF @verbose >= 1
				PRINT '('+convert(varchar, getdate(), 21)+') Databases parameter has databases for Inclusion logic. Working on same..';

			INSERT #db_list ([database_name], [recovery_model], [log_reuse_wait_desc])
			SELECT d.name, d.recovery_model_desc, d.[log_reuse_wait_desc]
			FROM sys.databases d
			INNER JOIN #db_list_from_params pl
				ON pl.database_name = d.name
			WHERE	1=1
				AND	d.state_desc = 'ONLINE'
				AND pl.skip_db = 0;
		END
		ELSE
		BEGIN
			IF @verbose >= 1
				PRINT '('+convert(varchar, getdate(), 21)+') Databases parameter has databases for Exclusion logic only. Working on same..';

			INSERT #db_list ([database_name], [recovery_model], [log_reuse_wait_desc])
			SELECT d.name, d.recovery_model_desc, d.[log_reuse_wait_desc]
			FROM sys.databases d			
			WHERE	1=1
				AND	d.state_desc = 'ONLINE'
				AND d.name NOT IN (SELECT pl.database_name FROM #db_list_from_params pl WHERE pl.skip_db = 1);
		END
	END
	ELSE
	BEGIN
		IF @verbose >= 1
			PRINT '('+convert(varchar, getdate(), 21)+') Databases parameter not provided. Working on #db_list..';

		INSERT #db_list ([database_name], [recovery_model], [log_reuse_wait_desc])
		SELECT d.name, d.recovery_model_desc, d.[log_reuse_wait_desc]
		FROM sys.databases d			
		WHERE	1=1
			AND	d.state_desc = 'ONLINE';
	END

	IF @verbose >= 2
	BEGIN
		PRINT '('+convert(varchar, getdate(), 21)+') select * from #db_list..'
		select running_query, t.*
		from #db_list t
		full outer join (values ('#db_list') )dummy(running_query) on 1 = 1
	END

	IF @verbose >= 1
		PRINT '('+convert(varchar, getdate(), 21)+') Populate #logspace using SQLPERF(LOGSPACE)..'
	INSERT INTO #logspace ([database_name], log_size_mb, log_used_pct, log_status) 
		EXEC ('DBCC SQLPERF(LOGSPACE) WITH NO_INFOMSGS');

	IF @verbose >= 2
	BEGIN
		PRINT '('+convert(varchar, getdate(), 21)+') select * from #logspace join #db_list..'
		select running_query, t.*, dl.*
		from #logspace t
		join #db_list dl on dl.database_name = t.database_name
		full outer join (values ('#logspace + #db_list') )dummy(running_query) on 1 = 1
	END
	
	IF @verbose >= 1
		PRINT '('+convert(varchar, getdate(), 21)+') Start a cursor, and loop through each database..'

	DECLARE cur_databases CURSOR LOCAL FORWARD_ONLY FOR
		SELECT dl.database_name, dl.recovery_model, dl.log_reuse_wait_desc, 
				ls.log_size_mb, ls.log_used_pct
		FROM #db_list dl
		JOIN #logspace ls
			ON ls.database_name = dl.database_name;

	OPEN cur_databases;
	FETCH NEXT FROM cur_databases INTO @c_database_name, @c_recovery_model, @c_log_reuse_wait_desc, @c_log_size_mb, @c_log_used_pct;

	WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @_is_pct_threshold_valid = 0;
		SET @_is_gb_threshold_valid = 0;
		SET @_thresholds_validated = 0;		
		SET @_exists_valid_autogrowing_file = 0;
		SET @_spid = NULL;
		SET @_transaction_start_time = NULL;
		TRUNCATE TABLE #dbcc_opentran;

		IF @verbose >= 1
			PRINT '('+convert(varchar, getdate(), 21)+') Working on database ['+@c_database_name+']..';

		IF @verbose >= 1
			PRINT @_tab+@_tab+'Validate if a valid auto-growing log file exists..'
		IF EXISTS (	SELECT * FROM sys.master_files mf 
					WHERE mf.database_id = DB_ID(@c_database_name) AND mf.type_desc = 'LOG'
					AND mf.growth > 0 AND mf.max_size <> 0 -- auto growth is enabled
					AND (	mf.max_size = -1
						OR	((mf.max_size*8.0/1024)*@log_used_pct_threshold/100.0) > @c_log_size_mb -- @log_used_pct_threshold of max size is not reached
						)
				)
		BEGIN
			SET @_exists_valid_autogrowing_file = 1;
		END

		-- Validate if % thresholds are crossed
		IF	(	@log_used_pct_threshold IS NOT NULL
			AND	@c_log_used_pct >= @log_used_pct_threshold
			AND (	@_exists_valid_autogrowing_file = 0
				OR	@skip_autogrowth_validation = 1
				)
			)
		BEGIN
			SET @_is_pct_threshold_valid = 1;
		END

		IF (@log_used_gb_threshold IS NOT NULL) AND ((@c_log_size_mb * @c_log_used_pct / 100.0) > (@log_used_gb_threshold*1024.0))
		BEGIN
			SET @_is_gb_threshold_valid = 1;
		END

		SET @_thresholds_validated = (CASE	WHEN @threshold_condition = 'and' and (@_is_pct_threshold_valid = 1 and @_is_gb_threshold_valid = 1) THEN 1
											WHEN @threshold_condition = 'or' and (@_is_pct_threshold_valid = 1 OR @_is_gb_threshold_valid = 1) THEN 1
											ELSE 0
											END);

		IF (@_thresholds_validated = 1) AND (@verbose >= 1)
			PRINT @_tab+@_tab+'Threshold broken for database ['+@c_database_name+']..';
		
		IF @verbose >= 1
		BEGIN
			PRINT @_tab+@_tab+'@c_log_reuse_wait_desc = '+ @c_log_reuse_wait_desc;
			PRINT @_tab+@_tab+'@c_log_size_mb = '+ convert(varchar,@c_log_size_mb);
			PRINT @_tab+@_tab+'@c_log_used_pct = '+ convert(varchar,@c_log_used_pct);
			PRINT @_tab+@_tab+'@_exists_valid_autogrowing_file = '+ convert(varchar,@_exists_valid_autogrowing_file);
			PRINT @_tab+@_tab+'@_is_pct_threshold_valid = '+ convert(varchar,@_is_pct_threshold_valid);
			PRINT @_tab+@_tab+'@_is_gb_threshold_valid = '+ convert(varchar,@_is_gb_threshold_valid);
			--PRINT @_tab+@_tab+'@_thresholds_validated = '+ convert(varchar,@_thresholds_validated);
		END
		
		-- If Thresholds are met, then find out oldest transaction details
		IF @_thresholds_validated = 1
		BEGIN
			IF @verbose >= 1
				PRINT @_tab+@_tab+'Find longest open transaction using DBCC OPENTRAN..';
			SET @_sql = 'DBCC OPENTRAN(''' + @c_database_name + ''') WITH TABLERESULTS, NO_INFOMSGS;';
			INSERT INTO #dbcc_opentran (transaction_property, transaction_property_value) 
			EXEC (@_sql);

			IF @verbose >= 2
			BEGIN
				PRINT @_tab+@_tab+' select * from #dbcc_opentran..'
				select running_query, [@c_database_name] = @c_database_name, t.*
				from #dbcc_opentran t
				full outer join (values ('#dbcc_opentran') )dummy(running_query) on 1 = 1
			END

			SELECT	@_spid = CASE WHEN transaction_property = 'OLDACT_SPID' THEN transaction_property_value ELSE @_spid END,
					@_transaction_start_time = CASE WHEN transaction_property = 'OLDACT_STARTTIME' THEN convert(datetime,transaction_property_value) ELSE @_transaction_start_time END
			FROM #dbcc_opentran 
			WHERE transaction_property IN ('OLDACT_SPID','OLDACT_STARTTIME');
		END

		IF @verbose >= 1
			PRINT @_tab+@_tab+'Populate #log_space_consumers with log usage + transaction details..';

		INSERT INTO #log_space_consumers
		(	[collection_time], [database_name], [recovery_model], [log_reuse_wait_desc], [log_size_mb], [log_used_mb], 
			[exists_valid_autogrowing_file], [log_used_pct], [log_used_pct_threshold], [log_used_gb_threshold], [spid], 
			[transaction_start_time], [login_name], [program_name], [host_name], [host_process_id], [command], [sql_text], 
			[action_taken], [additional_info], [is_pct_threshold_valid], [is_gb_threshold_valid], [threshold_condition],
			[thresholds_validated]
		)
		SELECT	[collection_time] = @_start_time,
				[database_name] = @c_database_name,
				[recovery_model] = @c_recovery_model,
				[log_reuse_wait_desc] = @c_log_reuse_wait_desc,
				[log_size_mb] = @c_log_size_mb,
				[log_used_mb] = convert(numeric(20,2), @c_log_size_mb*@c_log_used_pct/100.0),
				[exists_valid_autogrowing_file] = @_exists_valid_autogrowing_file,
				[log_used_pct] = @c_log_used_pct,
				[log_used_pct_threshold] = @log_used_pct_threshold,
				[log_used_gb_threshold] = @log_used_gb_threshold,
				[spid] = des.session_id,
				[transaction_start_time] = @_transaction_start_time,
				[login_name] = des.login_name,
				[program_name] = CASE	WHEN	des.program_name like 'SQLAgent - TSQL JobStep %'
										THEN	(	select	top 1 'SQL Job = '+j.name 
													from msdb.dbo.sysjobs (nolock) as j
													inner join msdb.dbo.sysjobsteps (nolock) AS js on j.job_id=js.job_id
													where right(cast(js.job_id as nvarchar(50)),10) = RIGHT(substring(des.program_name,30,34),10) 
												) + ' ( '+SUBSTRING(LTRIM(RTRIM(des.program_name)), CHARINDEX(': Step ',LTRIM(RTRIM(des.program_name)))+2,LEN(LTRIM(RTRIM(des.program_name)))-CHARINDEX(': Step ',LTRIM(RTRIM(des.program_name)))-2)+' )'
										ELSE	des.program_name
										END,
				[host_name] = des.[host_name],
				[host_process_id] = des.host_process_id,
				[command] = der.command,
				[sql_text] = est.text,
				[action_taken] = CASE WHEN dl.log_reuse_wait_desc = 'ACTIVE_TRANSACTION'
									THEN CASE	WHEN @kill_spids = 1 AND @send_email = 1 THEN 'Process Terminated, Notified DBA'
												WHEN @kill_spids = 1 THEN 'Process Terminated'
												WHEN @send_email = 1 THEN 'Notified DBA'
												ELSE 'No Action Taken'
												END
									ELSE 'No Action Taken'
									END,
				[additional_info] = null,
				[is_pct_threshold_valid] = @_is_pct_threshold_valid, 
				[is_gb_threshold_valid] = @_is_gb_threshold_valid, 
				[threshold_condition] = @threshold_condition,
				[thresholds_validated] = @_thresholds_validated
		FROM	#logspace t
		INNER JOIN #db_list dl 
			ON	dl.database_name = t.database_name
			AND	dl.database_name = @c_database_name
		LEFT JOIN sys.dm_exec_sessions des
			ON	des.session_id = @_spid
			AND	dl.log_reuse_wait_desc IN ('ACTIVE_TRANSACTION')
		LEFT JOIN sys.dm_exec_requests der
			ON	der.session_id = des.session_id
		OUTER APPLY sys.dm_exec_sql_text(der.sql_handle) est
		WHERE	1=1;
			--AND	status <> 'background'
			--AND	loginame NOT IN ('sa', 'NT AUTHORITY\SYSTEM');

		-- If Thresholds are met, then ACTIVE_TRANSACTION is main issue, then take action if allowed.
		IF (@_thresholds_validated = 1) AND (@_spid IS NOT NULL) AND (@c_log_reuse_wait_desc = 'ACTIVE_TRANSACTION')
		BEGIN
			IF ( (@_spid <> 0 AND @_spid >= 50) AND (@c_log_reuse_wait_desc = 'ACTIVE_TRANSACTION') )
			BEGIN
				SET @_sql = 'KILL ' + CONVERT(varchar(30), @_spid) + ';'
				IF @verbose >= 1
					PRINT @_tab+@_tab+(CASE WHEN @kill_spids = 1 THEN 'Execute: ' ELSE 'DryRun: ' END)+@_sql;

				IF @kill_spids = 1	
				BEGIN
					BEGIN TRY
						EXEC (@_sql);
					END TRY
					BEGIN CATCH
						PRINT '***** ERROR *****'+CHAR(13)+@_tab+ERROR_MESSAGE()+CHAR(13);
					END CATCH
				END
			END
			ELSE
			BEGIN
				IF @verbose >= 1
					PRINT @_tab+@_tab+'Log space is NOT caused by active transaction. So no action taken.';
			END
		END
		ELSE IF (@_thresholds_validated = 1) AND (@c_log_reuse_wait_desc <> 'ACTIVE_TRANSACTION') AND (@verbose >= 1)
			PRINT @_tab+@_tab+'Log space is NOT caused by active transaction. So no action taken.';
		ELSE IF (@verbose >= 1)
			PRINT @_tab+@_tab+'No action required for database ['+@c_database_name+']..';

		FETCH NEXT FROM cur_databases INTO @c_database_name, @c_recovery_model, @c_log_reuse_wait_desc, @c_log_size_mb, @c_log_used_pct;
	END

	IF @verbose >= 2
	BEGIN
		PRINT '('+convert(varchar, getdate(), 21)+') select * from #log_space_consumers..'
		select running_query, t.*
		from #log_space_consumers t
		full outer join (values ('#log_space_consumers') )dummy(running_query) on 1 = 1
	END

	IF EXISTS (SELECT 1/0 FROM #log_space_consumers)
	BEGIN
		IF @verbose >= 1
			PRINT '('+convert(varchar, getdate(), 21)+') Populate dbo.log_space_consumers from #log_space_consumers..'
		INSERT dbo.log_space_consumers
		SELECT * FROM #log_space_consumers;
	END

	IF (@purge_table = 1)
	BEGIN
		IF @verbose > 0
			PRINT '('+convert(varchar, getdate(), 21)+') Purge dbo.log_space_consumers with @retention_days = '+convert(varchar,@retention_days);
		DELETE FROM dbo.log_space_consumers WHERE collection_time <= DATEADD(day, -@retention_days, GETDATE());
	END

	IF EXISTS (SELECT 1/0 FROM #log_space_consumers WHERE thresholds_validated = 1 and spid IS NOT NULL)
	BEGIN
		-- Get 1st spid to report about
		select @c_database_name = lsc.database_name, @_spid = lsc.spid
		from #log_space_consumers lsc
		where thresholds_validated = 1
		and spid IS NOT NULL
		order by spid
		offset 0 rows fetch next 1 row only;

		WHILE @@ROWCOUNT <> 0
		BEGIN
			SET @_email_subject  = NULL;
			SET @_email_body = NULL;

			SET @_email_body = 'The following SQL Server process ' + CASE WHEN @kill_spids = 1 THEN 'was' ELSE 'is' END + ' preventing the ['+@c_database_name+'] database transaction log from clearing. Please visit https://ajaydwivedi.com/go/logsaver to view killed database process history.' + CHAR(10) + CHAR(10);

			SELECT	@_email_subject = 'Log Saver: ' + CONVERT(nvarchar(255), SERVERPROPERTY('ServerName')) + ' - ' + QUOTENAME(@c_database_name),
					@_email_body = @_email_body +
								'        current time: ' + CONVERT(varchar(100), collection_time, 121) + CHAR(10) +
								'                spid: ' + CONVERT(varchar(30), spid) + CHAR(10) +
								'     tran start time: ' + CONVERT(varchar(100), transaction_start_time, 121) + CHAR(10) +
								'       database_name: ' + database_name + CHAR(10) +
								'      recovery_model: ' + recovery_model + CHAR(10) +
								' log_reuse_wait_desc: ' + log_reuse_wait_desc + CHAR(10) +
								'         log_size_gb: ' + CONVERT(varchar(100), log_size_mb/1024) + CHAR(10) +
								'         log_used_gb: ' + CONVERT(varchar(100), log_used_mb/1024) + CHAR(10) +
								'        log_used_pct: ' + CONVERT(varchar(100), log_used_pct) + CHAR(10) +
								'          login_name: ' + login_name + CHAR(10) +
								'        program_name: ' + program_name + CHAR(10) +
								'           host_name: ' + host_name + CHAR(10) +
								'     host_process_id: ' + CONVERT(varchar(30), host_process_id) + CHAR(10) +
								'             command: ' + command + CHAR(10) +
								'            sql_text: ' + LTRIM(REPLACE(REPLACE(REPLACE(LEFT(sql_text, 200), CHAR(10), ' '), CHAR(13), ' '), '  ', ' ')) + CHAR(10) +
								'        action_taken: ' + action_taken + CHAR(10) + CHAR(10)
			FROM   #log_space_consumers
			WHERE thresholds_validated = 1
			and spid = @_spid;

			IF @verbose > 0
			BEGIN
				PRINT CHAR(13)+CHAR(13)+@_email_subject;
				PRINT @_email_body;
			END

			IF @send_email = 1
			BEGIN
				IF @verbose > 0
					PRINT '('+convert(varchar, getdate(), 21)+') Notifying DBA using email..';
				EXEC msdb.dbo.sp_send_dbmail
							@recipients =  @email_recipients,
							@subject =     @_email_subject,
							@body =        @_email_body,
							@body_format = 'TEXT'
			END
			
			select @c_database_name = lsc.database_name, @_spid = lsc.spid
			from #log_space_consumers lsc
			where thresholds_validated = 1
			and spid IS NOT NULL
			and lsc.spid > @_spid
			order by spid
			offset 0 rows fetch next 1 row only;
		END
	END
END
GO