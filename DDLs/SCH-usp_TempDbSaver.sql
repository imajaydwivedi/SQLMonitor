IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
SET ARITHABORT ON;
GO

IF OBJECT_ID('dbo.usp_TempDbSaver') IS NULL
	EXEC('CREATE PROCEDURE dbo.usp_TempDbSaver AS select 1 as dummy;');
GO

ALTER PROCEDURE [dbo].[usp_TempDbSaver]
(
	 @data_used_pct_threshold tinyint = 90,
	 @data_used_gb_threshold int = null,
	 @threshold_condition varchar(5) = 'or', /* {and | or} */
	 @kill_spids bit = 0,	 
	 @email_recipients varchar(max) = 'dba_team@gmail.com',
	 @send_email bit = 0,
	 @verbose tinyint = 0, /* 1 => messages, 2 => messages + table results */
	 @first_x_rows int = 10,
	 @drop_create_table bit = 0,
	 @retention_days int = 15,
	 @purge_table bit = 1
)
AS
BEGIN
	/*
		Purpose:		Detect and/or Kill sessions causing tempdb space utilization
		Modifications:	2023-Aug-10 - Initial Draft

		EXEC [dbo].[usp_TempDbSaver] @data_used_pct_threshold = 80, @data_used_gb_threshold = null, @kill_spids = 0, @verbose = 2, @first_x_rows = 10 -- Don't kill & Display all debug messages
		EXEC [dbo].[usp_TempDbSaver] @data_used_pct_threshold = 80, @data_used_gb_threshold = 500, @kill_spids = 1, @verbose = 0, @first_x_rows = 10 -- Kill & Avoid any messages

		declare @first_x_rows int = 10;
		select top 1 * from dbo.tempdb_space_usage order by collection_time desc;
		select * from dbo.tempdb_space_consumers order by collection_time desc, usage_rank asc
				offset 0 rows fetch next @first_x_rows rows only;

	*/
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET XACT_ABORT ON;

	IF @data_used_pct_threshold IS NULL AND @data_used_gb_threshold IS NULL
		THROW 51000, '@data_used_pct_threshold or @data_used_gb_threshold must be provided.', 1;
	IF @threshold_condition NOT IN ('and','or')
		THROW 51000, 'Expected value for @threshold_condition are {and || or} only.', 1;

	DECLARE @_start_time datetime2;
	SET @_start_time = SYSDATETIME();

	DECLARE @_sql nvarchar(max) = ''; 
	DECLARE @_sql_kill nvarchar(max);
	DECLARE @_params nvarchar(max);
	DECLARE @_email_body varchar(max) = null;
	DECLARE @_email_subject nvarchar(255) = 'Tempdb Saver: ' + @@SERVERNAME;
	DECLARE @_data_used_pct_current decimal(5,2);
	DECLARE @_is_pct_threshold_valid bit = 0;
	DECLARE @_is_gb_threshold_valid bit = 0;
	DEclare @_thresholds_validated bit = 0;

	SET @_params = N'@collection_time datetime2';

	DECLARE @t_login_exceptions TABLE (login_name sysname);
	/*
	INSERT @t_login_exceptions
	VALUES ('sa'),
			('NT AUTHORITY\SYSTEM');
	*/

	IF (@verbose > 0)
		PRINT '('+convert(varchar, getdate(), 21)+') Creating table variable @t_tempdb_consumers..';
	DECLARE @t_tempdb_consumers TABLE
	(
		[collection_time] [datetime2] NOT NULL,
		[spid] [smallint] NULL,
		[login_name] [nvarchar](128) NOT NULL,
		[program_name] [nvarchar](128) NULL,
		[host_name] [nvarchar](128) NULL,
		[host_process_id] [int] NULL,
		[is_active_session] [int] NOT NULL,
		[open_transaction_count] [int] NOT NULL,
		[transaction_isolation_level] [varchar](15) NULL,
		[size_bytes] [bigint] NULL,
		[transaction_begin_time] [datetime] NULL,
		[is_snapshot] [int] NOT NULL,
		[log_bytes] [bigint] NULL,
		[log_rsvd] [bigint] NULL,
		[action_taken] [varchar](200) NULL
	);
	
	IF @drop_create_table = 1 AND OBJECT_ID('dbo.tempdb_space_usage') IS NOT NULL
		EXEC ('drop table dbo.tempdb_space_usage;');

	IF OBJECT_ID('dbo.tempdb_space_usage') IS NULL
	BEGIN
		SET @_sql = '
		CREATE TABLE dbo.tempdb_space_usage
		(	[collection_time] datetime2 not null,
			[data_size_mb] varchar(100) not null,
			[data_used_mb] varchar(100) not null, 
			[data_used_pct] decimal(5,2) not null, 
			[log_size_mb] varchar(100) not null,
			[log_used_mb] varchar(100) null,
			[log_used_pct] decimal(5,2) null,
			[version_store_mb] decimal(20,2) null,
			[version_store_pct] decimal(20,2) null
		);
		create unique clustered index CI_tempdb_space_usage on dbo.tempdb_space_usage (collection_time);
		'
		IF (@verbose > 0)
		BEGIN
			PRINT '('+convert(varchar, getdate(), 21)+') Creating table dbo.tempdb_space_usage..'+CHAR(10)+CHAR(13);
			PRINT @_sql;
		END

		EXEC (@_sql)
	END

	IF @drop_create_table = 1 AND OBJECT_ID('dbo.tempdb_space_consumers') IS NOT NULL
		EXEC ('drop table dbo.tempdb_space_consumers;');

	IF OBJECT_ID('dbo.tempdb_space_consumers') IS NULL
	BEGIN
		SET @_sql = '
		CREATE TABLE dbo.tempdb_space_consumers
		(
			 collection_time datetime2 not null,
			 usage_rank tinyint not null,
			 spid int not null,
			 login_name sysname not null,
			 program_name sysname NULL,
			 host_name sysname NULL,
			 host_process_id int null,
			 is_active_session int null,
			 open_transaction_count int null,
			 transaction_isolation_level varchar(15) null,
			 size_bytes bigint null,
			 [transaction_begin_time] [datetime] NULL,
			 [is_snapshot] [int] NOT NULL,
			 [log_bytes] [bigint] NULL,
			 [log_rsvd] [bigint] NULL,
			 action_taken varchar(100) null
		);
		create unique clustered index CI_tempdb_space_consumers on dbo.tempdb_space_consumers (collection_time, usage_rank);
		'
		IF (@verbose > 0)
		BEGIN
			PRINT '('+convert(varchar, getdate(), 21)+') Creating table dbo.tempdb_space_consumers..'+CHAR(10)+CHAR(13);
			PRINT @_sql;
		END

		EXEC (@_sql)
	END

	IF (@verbose > 0)
		PRINT '('+convert(varchar, getdate(), 21)+') Populate table dbo.tempdb_space_usage..'
		
	SET @_sql = '
		use tempdb ;

		;with t_files_size as (
			select	[file_type] = f.type_desc,
					[size_mb] = convert(numeric(10,2), (f.size*8.0)/1024 ),
					[used_mb] = convert(numeric(10,2), CAST(FILEPROPERTY(f.name, ''SpaceUsed'') as int)/128.0 )
			from sys.database_files f left join sys.filegroups fg on fg.data_space_id = f.data_space_id
		)
		,t_files_by_type as (
			select	[data_size_mb] = case when file_type = ''ROWS'' then [size_mb] else 0.0 end,
					[data_used_mb] = case when file_type = ''ROWS'' then [used_mb] else 0.0 end,
					[log_size_mb] = case when file_type = ''LOG'' then [size_mb] else 0.0 end,
					[log_used_mb] = case when file_type = ''LOG'' then [used_mb] else 0 end,
					vs.[version_store_mb]
			from t_files_size fs
			full outer join (	SELECT [version_store_mb] = (SUM(version_store_reserved_page_count) / 128.0)	
								FROM tempdb.sys.dm_db_file_space_usage fsu with (nolock)
							) vs
				on 1=1
		)
		select	[collection_time] = @collection_time,
				[data_size_mb] = sum([data_size_mb]),
				[data_used_mb] = sum([data_used_mb]),
				[data_used_pct] = convert(numeric(12,2),sum([data_used_mb])*100.0/(sum([data_size_mb]))),
				[log_size_mb] = sum([log_size_mb]),
				[log_used_mb] = sum([log_used_mb]),
				[log_used_pct] = convert(numeric(12,2),sum([log_used_mb])*100.0/(sum([log_size_mb]))),
				[version_store_mb] = max([version_store_mb]),
				[version_store_pct] = convert(numeric(12,2),max([version_store_mb])*100.0/sum([data_used_mb]))
		from t_files_by_type; ';

	IF (@verbose > 0)
	BEGIN
		PRINT '('+convert(varchar, getdate(), 21)+') Insert dbo.tempdb_space_usage..'+CHAR(10)+CHAR(13);
		PRINT @_sql;
	END

	INSERT INTO dbo.tempdb_space_usage
	([collection_time], data_size_mb, data_used_mb, data_used_pct, log_size_mb, log_used_mb, log_used_pct, version_store_mb, version_store_pct)
	EXEC sp_executesql @_sql, @_params, @collection_time = @_start_time;

	IF (@verbose >= 2)
	BEGIN
		PRINT '('+convert(varchar, getdate(), 21)+') select * from dbo.tempdb_space_usage..'
		select top 1 running_query, t.*
		from dbo.tempdb_space_usage t
		full outer join (values ('dbo.tempdb_space_usage') )dummy(running_query) on 1 = 1
		where t.collection_time = @_start_time;
	END	

	IF (@verbose > 0)
		PRINT '('+convert(varchar, getdate(), 21)+') Populate table @t_tempdb_consumers..'	
	SET @_sql = '
	;WITH T_SnapshotTran
	AS (	
		SELECT	[s_tst].[session_id], --DB_NAME(s_tdt.database_id) as database_name,
				[begin_time] = ISNULL(MIN([s_tdt].[database_transaction_begin_time]),MIN(DATEADD(SECOND,-snp.elapsed_time_seconds,GETDATE()))),
				--[database_transaction_begin_time] = MIN([s_tdt].[database_transaction_begin_time]),
				--[database_transaction_begin_time2] = MIN(DATEADD(SECOND,-snp.elapsed_time_seconds,GETDATE())),
				SUM([s_tdt].[database_transaction_log_bytes_used]) AS [log_bytes],
				SUM([s_tdt].[database_transaction_log_bytes_reserved]) AS [log_rsvd],
				MAX(CASE WHEN snp.elapsed_time_seconds IS NOT NULL THEN 1 ELSE 0 END) AS is_snapshot
		FROM sys.dm_tran_database_transactions [s_tdt]
		JOIN sys.dm_tran_session_transactions [s_tst]
			ON [s_tst].[transaction_id] = [s_tdt].[transaction_id]
		LEFT JOIN sys.dm_tran_active_snapshot_database_transactions snp
			ON snp.session_id = s_tst.session_id AND snp.transaction_id = s_tst.transaction_id
		--WHERE s_tdt.database_id = 2
		GROUP BY [s_tst].[session_id] --,s_tdt.database_id
	)
	,T_TempDbTrans AS 
	(
		SELECT	[collection_time] = @collection_time,
				[spid] = des.session_id,
				[login_name] = des.original_login_name,  
				--des.program_name,
				[program_name] = CASE	WHEN	des.program_name like ''SQLAgent - TSQL JobStep %''
					THEN	(	select	top 1 ''SQL Job = ''+j.name 
								from msdb.dbo.sysjobs (nolock) as j
								inner join msdb.dbo.sysjobsteps (nolock) AS js on j.job_id=js.job_id
								where right(cast(js.job_id as nvarchar(50)),10) = RIGHT(substring(des.program_name,30,34),10) 
							) + '' ( ''+SUBSTRING(LTRIM(RTRIM(des.program_name)), CHARINDEX('': Step '',LTRIM(RTRIM(des.program_name)))+2,LEN(LTRIM(RTRIM(des.program_name)))-CHARINDEX('': Step '',LTRIM(RTRIM(des.program_name)))-2)+'' )'' collate SQL_Latin1_General_CP1_CI_AS
					ELSE	des.program_name
					END,
				des.host_name,
				des.host_process_id,
				[is_active_session] = CASE WHEN er.request_id IS NOT NULL THEN 1 ELSE 0 END,
				des.open_transaction_count,
				[transaction_isolation_level] = (CASE des.transaction_isolation_level 
						WHEN 0 THEN ''Unspecified''
						WHEN 1 THEN ''ReadUncommitted''
						WHEN 2 THEN ''ReadCommitted''
						WHEN 3 THEN ''Repeatable''
						WHEN 4 THEN ''Serializable'' 
						WHEN 5 THEN ''Snapshot'' END ),
				[size_bytes] = ((ssu.user_objects_alloc_page_count+ssu.internal_objects_alloc_page_count)-(ssu.internal_objects_dealloc_page_count+ssu.user_objects_dealloc_page_count))*8192,
				[transaction_begin_time] = case when des.open_transaction_count > 0 then (case when ott.begin_time is not null then ott.begin_time when er.start_time is not null then er.start_time else des.last_request_start_time end) else er.start_time end,
				[is_snapshot] = CASE WHEN ISNULL(ott.is_snapshot,0) = 1 THEN 1
									 WHEN tasdt.is_snapshot = 1 THEN 1
									 ELSE ISNULL(ott.is_snapshot,0)
									 END,
				ott.[log_bytes], ott.log_rsvd,
				CONVERT(varchar(200),NULL) AS action_taken
		FROM       sys.dm_exec_sessions des
		LEFT JOIN sys.dm_db_session_space_usage ssu on ssu.session_id = des.session_id
		LEFT JOIN T_SnapshotTran ott ON ott.session_id = ssu.session_id
		LEFT JOIN sys.dm_exec_requests er ON er.session_id = des.session_id
		OUTER APPLY (SELECT ( (tsu.user_objects_alloc_page_count+tsu.internal_objects_alloc_page_count)-(tsu.user_objects_dealloc_page_count+tsu.internal_objects_dealloc_page_count) )*8192 AS size_bytes 
					FROM sys.dm_db_task_space_usage tsu 
					WHERE ((tsu.user_objects_alloc_page_count+tsu.internal_objects_alloc_page_count)-(tsu.user_objects_dealloc_page_count+tsu.internal_objects_dealloc_page_count)) > 0
						AND tsu.session_id = er.session_id
					) as ra
		OUTER APPLY (select 1 as [is_snapshot] from sys.dm_tran_active_snapshot_database_transactions asdt where asdt.session_id = des.session_id) as tasdt
		WHERE des.session_id <> @@SPID --AND (er.request_id IS NOT NULL OR des.open_transaction_count > 0)
			--AND ssu.database_id = 2
	)
	SELECT top (@first_x_rows) *
	FROM T_TempDbTrans ot
	WHERE 1=1
	and ot.[spid] >= 50
	and (size_bytes > 0 OR is_active_session = 1 OR open_transaction_count > 0 OR  is_snapshot = 1)
	'
	IF EXISTS (SELECT * FROM dbo.tempdb_space_usage s WHERE s.collection_time = @_start_time and s.version_store_pct >= 30)
	BEGIN
		--SET @_sql = @_sql + 'and is_snapshot = 1'+CHAR(10)
		SET @_sql = @_sql + 'order by is_snapshot DESC, (case when transaction_begin_time is null then dateadd(day,1,getdate()) else transaction_begin_time end ) ASC, size_bytes desc;'+CHAR(10)
	END
	ELSE
		SET @_sql = @_sql + 'order by size_bytes desc;'+CHAR(10)
	
	IF (@verbose > 1)
		PRINT @_sql

	SET @_params = N'@collection_time datetime2, @first_x_rows int';
	INSERT @t_tempdb_consumers
	EXEC sp_executesql @_sql, @_params, @collection_time = @_start_time, @first_x_rows = @first_x_rows;

	IF (@verbose > 1)
	BEGIN
		PRINT '('+convert(varchar, getdate(), 21)+') select * from @t_tempdb_consumers..'
		
		IF EXISTS (SELECT * FROM dbo.tempdb_space_usage s WHERE s.collection_time = @_start_time and s.version_store_pct >= 30)
			select running_query, t.*
			from @t_tempdb_consumers t
			full outer join (values ('@t_tempdb_consumers') )dummy(running_query) on 1 = 1
			order by is_snapshot DESC, transaction_begin_time ASC;
		ELSE
			select running_query, t.* --top (@first_x_rows) 
			from @t_tempdb_consumers t
			full outer join (values ('@t_tempdb_consumers') )dummy(running_query) on 1 = 1
			order by size_bytes desc;
	END

	IF @data_used_pct_threshold IS NOT NULL AND EXISTS (SELECT 1/0 FROM dbo.tempdb_space_usage s WHERE s.collection_time = @_start_time and data_used_pct > @data_used_pct_threshold)
		SET @_is_pct_threshold_valid = 1;
	IF @data_used_gb_threshold IS NOT NULL AND EXISTS (SELECT 1/0 FROM dbo.tempdb_space_usage s WHERE s.collection_time = @_start_time and data_used_mb > (@data_used_gb_threshold*1024.0))
		SET @_is_gb_threshold_valid = 1;
	SET @_thresholds_validated = (CASE	WHEN @threshold_condition = 'and' and (@_is_pct_threshold_valid = 1 and @_is_gb_threshold_valid = 1) THEN 1
										WHEN @threshold_condition = 'or' and (@_is_pct_threshold_valid = 1 OR @_is_gb_threshold_valid = 1) THEN 1
										ELSE 0
										END);

	IF @verbose >= 1
	BEGIN
		SELECT	[@data_used_pct_threshold] = @data_used_pct_threshold, 
				[@_is_pct_threshold_valid] = @_is_pct_threshold_valid,
				[@data_used_gb_threshold] = @data_used_gb_threshold,
				[@_is_gb_threshold_valid] = @_is_gb_threshold_valid, 
				[@_thresholds_validated] = @_thresholds_validated,
				[@threshold_condition] = @threshold_condition;
	END

	IF @verbose > 0
		PRINT '('+convert(varchar, getdate(), 21)+') Validate @_thresholds_validated, and take action..'	
	IF @_thresholds_validated = 1
	BEGIN
		IF @verbose > 0
			PRINT '('+convert(varchar, getdate(), 21)+') Found @_thresholds_validated to be true.'
			
		IF EXISTS (SELECT * FROM dbo.tempdb_space_usage s WHERE s.collection_time = @_start_time and s.version_store_pct >= 30) -- If Version Store Issue
		BEGIN
			IF @verbose > 0
			BEGIN
				PRINT '('+convert(varchar, getdate(), 21)+') Version Store Issue.';
				PRINT '('+convert(varchar, getdate(), 21)+') version_store_mb >= 30% of data_used_mb';
				PRINT '('+convert(varchar, getdate(), 21)+') Pick top spid (@_sql_kill) order by ''ORDER BY is_snapshot DESC, transaction_begin_time ASC''';
			END
			SELECT TOP 1 @_sql_kill = CONVERT(varchar(30), tu.spid)
			FROM	@t_tempdb_consumers tu
			WHERE   host_process_id IS NOT NULL
			AND     login_name NOT IN (SELECT ex.login_name FROM @t_login_exceptions ex)
			ORDER BY is_snapshot DESC, transaction_begin_time ASC;
		END
		ELSE
		BEGIN -- Not Version Store issue.
			IF @verbose > 0
			BEGIN
				PRINT '('+convert(varchar, getdate(), 21)+') Not Version Store Issue.';
				PRINT '('+convert(varchar, getdate(), 21)+') version_store_mb < 30% of data_used_mb';
				PRINT '('+convert(varchar, getdate(), 21)+') Pick top spid (@_sql_kill) order by ''(ISNULL(size_bytes,0)+ISNULL(log_bytes,0)+ISNULL(log_rsvd,0)) DESC''';
			END
			SELECT TOP 1 @_sql_kill = CONVERT(varchar(30), tu.spid)
			FROM @t_tempdb_consumers tu
			WHERE         host_process_id IS NOT NULL
			AND         login_name NOT IN (SELECT ex.login_name FROM @t_login_exceptions ex)
			AND size_bytes <> 0
			ORDER BY (ISNULL(size_bytes,0)+ISNULL(log_bytes,0)+ISNULL(log_rsvd,0)) DESC;
		END
		

		IF @verbose > 0
			PRINT '('+convert(varchar, getdate(), 21)+') Top tempdb consumer spid (@_sql_kill) = '+@_sql_kill;
  
		IF (@_sql_kill IS NOT NULL)
		BEGIN
			IF (@kill_spids = 1)
			BEGIN
				IF @verbose > 0
					PRINT '('+convert(varchar, getdate(), 21)+') Kill top consumer.';
				UPDATE @t_tempdb_consumers SET action_taken = 'Process Terminated' WHERE spid = @_sql_kill
				SET @_sql = 'kill ' + @_sql_kill;
				PRINT (@_sql);
				EXEC (@_sql);
				IF @verbose > 0
					PRINT '('+convert(varchar, getdate(), 21)+') Update @t_tempdb_consumers with action_taken ''Process Terminated''.';
			END
			ELSE
			BEGIN
				UPDATE @t_tempdb_consumers SET action_taken = 'Notified DBA' WHERE spid = @_sql_kill
				IF @verbose > 0
					PRINT '('+convert(varchar, getdate(), 21)+') Update @t_tempdb_consumers with action_taken ''Notified DBA''.';
			END;

			SET @_email_body = 'The following SQL Server process ' + CASE WHEN @kill_spids = 1 THEN 'was' ELSE 'is' END + ' consuming the most tempdb space.' + CHAR(10) + CHAR(10)
			SELECT @_data_used_pct_current = data_used_pct FROM dbo.tempdb_space_usage s WHERE s.collection_time = @_start_time;
			SELECT @_email_body = @_email_body + 
								'      date_time: ' + CONVERT(varchar(100), collection_time, 121) + CHAR(10) + 
								'tempdb_used_pct: ' + CONVERT(varchar(100), @_data_used_pct_current) + CHAR(10) +
								'           spid: ' + CONVERT(varchar(30), spid) + CHAR(10) +
								'     login_name: ' + login_name + CHAR(10) +
								'   program_name: ' + ISNULL(program_name, '') + CHAR(10) +
								'      host_name: ' + ISNULL(host_name, '') + CHAR(10) +
								'host_process_id: ' + CONVERT(varchar(30), host_process_id) + CHAR(10) +
								'      is_active: ' + CONVERT(varchar(30), is_active_session) + CHAR(10) +
								'     tran_count: ' + CONVERT(varchar(30), open_transaction_count) + CHAR(10) +
								'    is_snapshot: ' + CONVERT(varchar(30), is_snapshot) + CHAR(10) +
								'tran_start_time: ' + (case when transaction_begin_time is null then '' else CONVERT(varchar(100), transaction_begin_time, 121) end) + CHAR(10) + 
								'   action_taken: ' + action_taken + CHAR(10) + CHAR(10)
			FROM   @t_tempdb_consumers tu
			WHERE spid = @_sql_kill;

			PRINT @_email_body
			If(@send_email =1)
			BEGIN
				EXEC msdb.dbo.sp_send_dbmail  
					@recipients =  @email_recipients,  
					@subject =     @_email_subject,  
					@body =        @_email_body,
				@body_format = 'TEXT'
			END
		END;

		IF @verbose > 0
			PRINT '('+convert(varchar, getdate(), 21)+') Populate table dbo.tempdb_space_consumers with top 10 session details.';
		IF EXISTS (SELECT * FROM dbo.tempdb_space_usage s WHERE s.collection_time = @_start_time and s.version_store_pct >= 30)
		BEGIN
			INSERT INTO dbo.tempdb_space_consumers 
			([collection_time], [spid], [login_name], [program_name], [host_name], [host_process_id], [is_active_session], [open_transaction_count], [transaction_isolation_level], [size_bytes], [transaction_begin_time], [is_snapshot], [log_bytes], [log_rsvd], [action_taken], [usage_rank])
			SELECT [collection_time], [spid], [login_name], [program_name], [host_name], [host_process_id], [is_active_session], [open_transaction_count], [transaction_isolation_level], [size_bytes], [transaction_begin_time], [is_snapshot], [log_bytes], [log_rsvd], [action_taken], 
					[usage_rank] = ROW_NUMBER()over(order by collection_time, is_snapshot DESC, (case when transaction_begin_time is null then dateadd(day,1,getdate()) else transaction_begin_time end) ASC)
			FROM  @t_tempdb_consumers 
			order by collection_time, is_snapshot DESC, (case when transaction_begin_time is null then dateadd(day,1,getdate()) else transaction_begin_time end) ASC, [size_bytes] desc, [log_rsvd] desc
			offset 0 rows fetch next @first_x_rows rows only;
			
		END
		ELSE
			INSERT INTO dbo.tempdb_space_consumers 
			([collection_time], [spid], [login_name], [program_name], [host_name], [host_process_id], [is_active_session], [open_transaction_count], [transaction_isolation_level], [size_bytes], [transaction_begin_time], [is_snapshot], [log_bytes], [log_rsvd], [action_taken], [usage_rank])
			SELECT [collection_time], [spid], [login_name], [program_name], [host_name], [host_process_id], [is_active_session], [open_transaction_count], [transaction_isolation_level], [size_bytes], [transaction_begin_time], [is_snapshot], [log_bytes], [log_rsvd], [action_taken], 
					[usage_rank] = ROW_NUMBER()over(order by collection_time, size_bytes DESC)
			FROM  @t_tempdb_consumers 
			order by collection_time, size_bytes DESC
			offset 0 rows fetch next @first_x_rows rows only;
	END;
	ELSE
	BEGIN
		IF @verbose > 0
			PRINT '('+convert(varchar, getdate(), 21)+') Current tempdb space usage under threshold.'
	END

	IF (@purge_table = 1)
	BEGIN
		IF @verbose > 0
			PRINT '('+convert(varchar, getdate(), 21)+') Purge dbo.tempdb_space_consumers with @retention_days = '+convert(varchar,@retention_days);
		DELETE FROM dbo.tempdb_space_consumers WHERE collection_time <= DATEADD(day, -@retention_days, GETDATE());

		IF @verbose > 0
			PRINT '('+convert(varchar, getdate(), 21)+') Purge dbo.tempdb_space_usage with @retention_days = '+convert(varchar,@retention_days);
		DELETE FROM dbo.tempdb_space_usage WHERE collection_time <= DATEADD(day, -@retention_days, GETDATE());
	END

	--if @_email_body != null
	--begin
	--	SELECT @_email_body as Body
	--end
END
GO
