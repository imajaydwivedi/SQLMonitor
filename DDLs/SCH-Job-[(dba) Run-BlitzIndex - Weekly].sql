USE [msdb]
GO

if exists (select * from msdb.dbo.sysjobs_view where name = N'(dba) Run-BlitzIndex - Weekly')
	EXEC msdb.dbo.sp_delete_job @job_name=N'(dba) Run-BlitzIndex - Weekly', @delete_unused_schedule=1
GO

BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'(dba) SQLMonitor' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'(dba) SQLMonitor'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'(dba) Run-BlitzIndex - Weekly', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Capture index usage details into SQL Table .', 
		@category_name=N'(dba) SQLMonitor', 
		--@owner_login_name=N'sa', 
		@job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'sp_BlitzIndex @Mode = 0', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'CmdExec', 
		@command=N'sqlcmd -E -b -S "localhost" -H "(dba) Run-BlitzIndex - Weekly - @Mode = 0" -d "DBA" -Q "EXEC master.dbo.sp_BlitzIndex @GetAllDatabases = 1, @Mode = 0, @BringThePain = 1, @OutputDatabaseName = ''DBA'', @OutputSchemaName = ''dbo'', @OutputTableName = ''BlitzIndex_Mode0'';"', 
		@flags=40
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'sp_BlitzIndex @Mode = 1', 
		@step_id=2, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'CmdExec', 
		@command=N'sqlcmd -E -b -S "localhost" -H "(dba) Run-BlitzIndex - Weekly - @Mode = 1" -d "DBA" -Q "EXEC master.dbo.sp_BlitzIndex @GetAllDatabases = 1, @Mode = 1, @BringThePain = 1, @OutputDatabaseName = ''DBA'', @OutputSchemaName = ''dbo'', @OutputTableName = ''BlitzIndex_Mode1'';"', 
		@flags=40
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'sp_BlitzIndex @Mode = 4', 
		@step_id=3, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'CmdExec', 
		@command=N'sqlcmd -E -b -S "localhost" -H "(dba) Run-BlitzIndex - Weekly - @Mode = 4" -d "DBA" -Q "EXEC master.dbo.sp_BlitzIndex @GetAllDatabases = 1, @Mode = 4, @BringThePain = 1, @OutputDatabaseName = ''DBA'', @OutputSchemaName = ''dbo'', @OutputTableName = ''BlitzIndex_Mode4'';"', 
		@flags=40
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'(dba) Run-BlitzIndex - Weekly', 
		@enabled=1, 
		@freq_type=8, 
		@freq_interval=64, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=1, 
		@active_start_date=20221002, 
		@active_end_date=99991231, 
		@active_start_time=50000
		--,@schedule_uid=N'a1f4f1fd-4ef5-49dd-bf26-f7661af46d37'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '***************************** EXEC master.dbo.sp_BlitzIndex @Mode = 0 *****************************';
EXEC master.dbo.sp_BlitzIndex @DatabaseName = 'master', @Mode = 0, @BringThePain = 1, 
			@OutputDatabaseName = 'DBA', @OutputSchemaName = 'dbo', @OutputTableName = 'BlitzIndex_Mode0';
GO

if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '***************************** EXEC master.dbo.sp_BlitzIndex @Mode = 1 *****************************';
EXEC master.dbo.sp_BlitzIndex @DatabaseName = 'master', @Mode = 1, @BringThePain = 1, 
			@OutputDatabaseName = 'DBA', @OutputSchemaName = 'dbo', @OutputTableName = 'BlitzIndex_Mode1';
GO
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '***************************** EXEC master.dbo.sp_BlitzIndex @Mode = 4 *****************************';
EXEC master.dbo.sp_BlitzIndex @DatabaseName = 'master', @Mode = 4, @BringThePain = 1, 
			@OutputDatabaseName = 'DBA', @OutputSchemaName = 'dbo', @OutputTableName = 'BlitzIndex_Mode4';
GO

-- Executing this job caused delay in deployment of SQLMonitor.
EXEC msdb.dbo.sp_start_job @job_name=N'(dba) Run-BlitzIndex - Weekly'
go
