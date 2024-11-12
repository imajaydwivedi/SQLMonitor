use tempdb
go

-- create table in tempdb
if object_id('dbo.Posts_TempdbSaver') is not null
	drop table dbo.Posts_TempdbSaver;
select top 50 *
into dbo.Posts_TempdbSaver
from StackOverflow2013.dbo.Posts
go

insert dbo.Posts_TempdbSaver (AcceptedAnswerId, AnswerCount, Body, ClosedDate, CommentCount, CommunityOwnedDate, CreationDate, FavoriteCount, LastActivityDate, LastEditDate, LastEditorDisplayName, LastEditorUserId, OwnerUserId, ParentId, PostTypeId, Score, Tags, Title, ViewCount)
select top 2000 AcceptedAnswerId, AnswerCount, Body, ClosedDate, CommentCount, CommunityOwnedDate, CreationDate, FavoriteCount, LastActivityDate, LastEditDate, LastEditorDisplayName, LastEditorUserId, OwnerUserId, ParentId, PostTypeId, Score, Tags, Title, ViewCount
from StackOverflow2013.dbo.Posts order by newid()
go 2


use tempdb
go
begin tran
	-- update data
	update top (50) percent dbo.Posts_TempdbSaver
	--set LastActivityDate = getdate(), CommentCount = 10
	set Body = Body+''

	-- delete data
	delete top (5000) from dbo.Posts_TempdbSaver
	go 2

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


/*
USE [tempdb]
GO
DBCC SHRINKFILE (N'tempdev' , 100)
GO
DBCC SHRINKFILE (N'temp2' , 100)
GO
DBCC SHRINKFILE (N'temp3' , 100)
GO
DBCC SHRINKFILE (N'temp4' , 100)
GO
USE [tempdb]
GO
DBCC SHRINKFILE (N'templog' , 200)
GO


USE [master]
GO
ALTER DATABASE [tempdb] MODIFY FILE ( NAME = N'temp2', FILEGROWTH = 20480KB )
GO
ALTER DATABASE [tempdb] MODIFY FILE ( NAME = N'temp3', FILEGROWTH = 20480KB )
GO
ALTER DATABASE [tempdb] MODIFY FILE ( NAME = N'temp4', FILEGROWTH = 20480KB )
GO
ALTER DATABASE [tempdb] MODIFY FILE ( NAME = N'tempdev', FILEGROWTH = 20480KB )
GO

*/