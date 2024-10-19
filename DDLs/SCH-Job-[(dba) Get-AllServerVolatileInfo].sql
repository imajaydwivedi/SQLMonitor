USE [msdb]
GO

if exists (select * from msdb.dbo.sysjobs_view where name = N'(dba) Get-AllServerVolatileInfo')
	EXEC msdb.dbo.sp_delete_job @job_name=N'(dba) Get-AllServerVolatileInfo', @delete_unused_schedule=1
GO

USE [msdb]
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
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'(dba) Get-AllServerVolatileInfo', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'This job execute procedure usp_GetAllServerInfo and populates tables dbo.all_server_volatile_info & dbo.all_server_volatile_info_history

https://ajaydwivedi.com/github/sqlmonitor', 
		@category_name=N'(dba) SQLMonitor', 
		@job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'dbo.all_server_volatile_info', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'CmdExec', 
		@command=N'sqlcmd -E -b -S localhost -H "(dba) Get-AllServerVolatileInfo - all_server_volatile_info" -d DBA -Q "EXEC dbo.usp_wrapper_GetAllServerInfo @step_name = ''dbo.all_server_volatile_info'', @verbose = 0;"', 
		@flags=40
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [dbo.usp_populate__all_server_volatile_info_history]    Script Date: Sat, 19 Oct 10:51:24 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'dbo.usp_populate__all_server_volatile_info_history', 
		@step_id=2, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'CmdExec', 
		@command=N'sqlcmd -E -b -S localhost -H "(dba) Get-AllServerVolatileInfo - usp_populate__all_server_volatile_info_history" -d DBA -Q "EXEC dbo.usp_wrapper_GetAllServerInfo @step_name = ''dbo.usp_populate__all_server_volatile_info_history'', @verbose = 0;"', 
		@flags=40
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'(dba) Get-AllServerVolatileInfo', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=2, 
		@freq_subday_interval=30, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20220715, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959
		--,@schedule_uid=N'7c782313-f81f-4768-ac55-a42beeaea613'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO


EXEC msdb.dbo.sp_start_job @job_name=N'(dba) Get-AllServerVolatileInfo'
go
