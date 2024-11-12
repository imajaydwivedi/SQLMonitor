USE msdb ;  
GO

if exists (select * from msdb.dbo.sysjobs_view where name = N'(dba) Enable-PageCompression')
	EXEC msdb.dbo.sp_delete_job @job_name=N'(dba) Enable-PageCompression', @delete_unused_schedule=1
GO

EXEC msdb.dbo.sp_add_job  
			@job_name = N'(dba) Enable-PageCompression',
			@notify_level_eventlog=0,
			@notify_level_email=2, 
			@notify_level_page=2,
			@delete_level=1,
			@description=N'This job purges data from SQLMonitor tables mentioned in dbo.purge_table.

https://ajaydwivedi.com/github/sqlmonitor', 
			@category_name=N'(dba) SQLMonitor'
			--,@owner_login_name=N'sa'
GO  

EXEC msdb.dbo.sp_add_jobstep  
			@job_name = N'(dba) Enable-PageCompression',  
			@step_name = N'Enable-PageCompression',  
			@subsystem = N'TSQL', 
			@command = N'exec dbo.usp_enable_page_compression',
			@database_name=N'DBA', 
			@retry_attempts = 1,
			@retry_interval = 1;
GO  

EXEC msdb.dbo.sp_add_schedule  
			@schedule_name = N'(dba) Enable-PageCompression',  
			@freq_type = 1,
			@enabled=1;
GO

EXEC msdb.dbo.sp_attach_schedule  
   @job_name = N'(dba) Enable-PageCompression',  
   @schedule_name = N'(dba) Enable-PageCompression';  
GO  

EXEC msdb.dbo.sp_add_jobserver  
    @job_name = N'(dba) Enable-PageCompression';  
GO

EXEC msdb..sp_start_job @job_name = N'(dba) Enable-PageCompression'
GO
