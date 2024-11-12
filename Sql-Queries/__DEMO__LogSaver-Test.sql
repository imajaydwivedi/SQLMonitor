use tempdb
go

-- create table in tempdb
if object_id('dbo.WhoIsActive_TempdbSaver') is not null
	drop table dbo.WhoIsActive_TempdbSaver;
select top 500000 *
into dbo.WhoIsActive_TempdbSaver
from DBA.dbo.WhoIsActive w
go

use tempdb
go
begin tran
	-- update data
	update dbo.WhoIsActive_TempdbSaver
	set blocked_session_count = blocked_session_count, tasks = tasks

	-- delete data
	delete top (50) percent from dbo.WhoIsActive_TempdbSaver

	select @@TRANCOUNT

-- do this later.
rollback tran
go

/*
exec msdb.dbo.sp_start_job @job_name = '(dba) Run-LogSaver';
go

exec usp_LogSaver @databases = 'DBA,tempdb',
				@log_used_pct_threshold = 80,
				--@log_used_gb_threshold = 500,
				--@threshold_condition = 'or',
				@skip_autogrowth_validation = 1,
				@email_recipients = 'sqlagentservice@gmail.com',
				@purge_table = 0,
				@kill_spids = 0,
				@send_email = 0,
				--@drop_create_table = 0,
				@verbose = 2;
go
*/
