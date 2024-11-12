use master
go

declare @DbaADGroup nvarchar(255);

select @DbaADGroup = dss.service_account from sys.dm_server_services dss 
where servicename like 'SQL Server Agent (%';

select 'net localgroup "'+group_name+'" "'+@DbaADGroup+'" /add'
from (values ('administrators'),('Performance Log Users'),('Performance Monitor Users') ) groups (group_name);
go


USE [msdb]
GO

/* Purpose: Add SQL Agent service account into 3 Windows Groups */

BEGIN TRANSACTION
DECLARE @DbaADGroup varchar(500);
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

select @DbaADGroup = dss.service_account from sys.dm_server_services dss 
where servicename like 'SQL Server Agent (%';

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'(dba) SQLMonitor' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'(dba) SQLMonitor'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16);
DECLARE @description nvarchar(2000);
DECLARE @command nvarchar(2000);

SET @description = N'net localgroup administrators "'+@DbaADGroup+'" /add
net localgroup "Performance Log Users" "'+@DbaADGroup+'" /add
net localgroup "Performance Monitor Users" "'+@DbaADGroup+'" /add
';


EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'(dba) __Add-ServiceAccountPriviledges', 
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

SET @command = N'net localgroup administrators "'+@DbaADGroup+'" /add';
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Add to [administrators]', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'CmdExec', 
		@command=@command, 
		@flags=40
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

SET @command = N'net localgroup "Performance Log Users" "'+@DbaADGroup+'" /add';
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Add to [Performance Log Users]', 
		@step_id=2, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'CmdExec', 
		@command=@command, 
		@flags=40
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

SET @command = N'net localgroup "Performance Monitor Users" "'+@DbaADGroup+'" /add';
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Add to [Performance Monitor Users]', 
		@step_id=3, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'CmdExec', 
		@command=@command, 
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

IF exists (select * from msdb..sysjobs_view j where j.name = '(dba) __Add-ServiceAccountPriviledges')
	exec msdb.dbo.sp_start_job @job_name = '(dba) __Add-ServiceAccountPriviledges';

WAITFOR DELAY '00:10:00';

IF exists (select * from msdb..sysjobs_view j where j.name = '(dba) __Add-ServiceAccountPriviledges')
	exec msdb.dbo.sp_delete_job @job_name = '(dba) __Add-ServiceAccountPriviledges';
GO

