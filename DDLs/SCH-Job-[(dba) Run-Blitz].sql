USE [msdb]
GO

if exists (select * from msdb.dbo.sysjobs_view where name = N'(dba) Run-Blitz')
	EXEC msdb.dbo.sp_delete_job @job_name=N'(dba) Run-Blitz', @delete_unused_schedule=1
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
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'(dba) Run-Blitz', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Capture Overall Server Health Checks', 
		@category_name=N'(dba) SQLMonitor', 
		--@owner_login_name=N'sa', 
		@job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'sp_Blitz', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'CmdExec', 
		@command=N'sqlcmd -E -b -S localhost -H "(dba) Run-Blitz" -d DBA -Q "EXEC master.dbo.sp_Blitz @CheckUserDatabaseObjects = 1, @BringThePain = 1, @CheckServerInfo = 1, @OutputDatabaseName = ''DBA'', @OutputSchemaName = ''dbo'', @OutputTableName = ''Blitz'';"', 
		@flags=40
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'(dba) Run-Blitz', 
		@enabled=1, 
		@freq_type=8, 
		@freq_interval=64, 
		@freq_recurrence_factor=1, 
		@active_start_time=60000
		--,@schedule_uid=N'cc775d0e-ad80-4318-8894-c58fedcdabb4'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

--exec master.dbo.sp_Blitz @CheckUserDatabaseObjects = 0, @BringThePain = 0, @CheckServerInfo = 1, @OutputDatabaseName = 'DBA', @OutputSchemaName = 'dbo', @OutputTableName = 'Blitz';
GO

-- Executing this job caused delay in deployment of SQLMonitor.
EXEC msdb.dbo.sp_start_job @job_name=N'(dba) Run-Blitz'
GO

