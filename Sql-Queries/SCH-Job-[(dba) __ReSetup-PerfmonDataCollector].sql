USE [msdb]
GO

BEGIN TRANSACTION
DECLARE @ReturnCode INT;
SELECT @ReturnCode = 0

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'(dba) SQLMonitor' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'(dba) SQLMonitor'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16);
DECLARE @description nvarchar(2000);
SET @description = N'powershell.exe -executionpolicy bypass -Noninteractive  C:\SQLMonitor\perfmon-collector-logman.ps1 -ReSetupCollector:$true -ErrorAction Stop';

EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'(dba) __ReSetup-PerfmonDataCollector', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=@description, 
		@category_name=N'(dba) SQLMonitor',
		@job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'ReSetup Perfmon Data Collector', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'CmdExec', 
		@command=@description, 
		@flags=40
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

IF exists (select * from msdb..sysjobs_view j where j.name = '(dba) __ReSetup-PerfmonDataCollector')
	exec msdb.dbo.sp_start_job @job_name = '(dba) __ReSetup-PerfmonDataCollector';

WAITFOR DELAY '00:10:00';

IF exists (select * from msdb..sysjobs_view j where j.name = '(dba) __ReSetup-PerfmonDataCollector')
	exec msdb.dbo.sp_delete_job @job_name = '(dba) __ReSetup-PerfmonDataCollector';
GO
