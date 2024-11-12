use DBA
go

if object_id('dbo.WhoIsActive_TempdbSaver') is not null
	drop table dbo.WhoIsActive_TempdbSaver;
select top 500000 *
into dbo.WhoIsActive_TempdbSaver
from dbo.WhoIsActive w
go

insert dbo.WhoIsActive_TempdbSaver
select top 500000 *
from dbo.WhoIsActive w
go 3


begin tran
	update top (100) percent dbo.WhoIsActive_TempdbSaver
	set blocked_session_count = blocked_session_count

	--delete top (10) percent from dbo.WhoIsActive_TempdbSaver

	--delete top (10) percent from dbo.WhoIsActive_TempdbSaver

	select @@TRANCOUNT

-- do this later.
-- rollback tran

/*
use DBA
go

begin tran
	select * from WhoIsActive_TempdbSaver

-- do this later.
rollback tran
go

*/

/*
exec msdb.dbo.sp_start_job @job_name = '(dba) Run-TempdbSaver';
go

EXEC [dbo].[usp_TempDbSaver] @data_used_pct_threshold = 80, @data_used_gb_threshold = null, @kill_spids = 0, @verbose = 2, @first_x_rows = 10 -- Don't kill & Display all debug messages
GO
*/