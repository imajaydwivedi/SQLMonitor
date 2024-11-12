USE [msdb]
GO

if exists (select * from msdb.dbo.sysjobs_view where name = N'(dba) Update-SqlServerVersions') and APP_NAME() = 'Microsoft SQL Server Management Studio - Query'
	EXEC msdb.dbo.sp_delete_job @job_name=N'(dba) Update-SqlServerVersions', @delete_unused_schedule=1
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
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'(dba) Update-SqlServerVersions', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'This job fetches script "https://raw.githubusercontent.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/dev/SqlServerVersions.sql", and updates table [master].[dbo].[SqlServerVersions]

https://ajaydwivedi.com/github/sqlmonitor', 
		@category_name=N'(dba) SQLMonitor', 
		--@owner_login_name=N'sa', 
		@job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Update-SqlServerVersions', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=2, 
		@retry_interval=1, 
		@os_run_priority=0, @subsystem=N'CmdExec', 
		@command=N'powershell.exe -executionpolicy bypass -Noninteractive C:\SQLMonitor\sqlserver-versions-update.ps1 -SqlInstance localhost -ErrorAction Stop', 
		@flags=40
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'(dba) Update-SqlServerVersions', 
		@enabled=1, 
		@freq_type=8, 
		@freq_interval=40, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=1, 
		@active_start_date=20220515, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959
		--@schedule_uid=N'30731c94-4aee-486b-a86f-d609ec3af51c'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

IF APP_NAME() = 'Microsoft SQL Server Management Studio - Query'
	EXEC msdb.dbo.sp_start_job @job_name=N'(dba) Update-SqlServerVersions';
GO
