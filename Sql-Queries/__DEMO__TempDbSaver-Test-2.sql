use DBA
go

-- create table in tempdb
if object_id('dbo.Posts_TempdbSaver') is not null
	drop table dbo.Posts_TempdbSaver;
select top 500 *
into dbo.Posts_TempdbSaver
from StackOverflow2013.dbo.Posts
go

select top 5000 *
into #Posts_TempdbSaver
from StackOverflow2013.dbo.Posts
go

begin tran
	insert dbo.#Posts_TempdbSaver (AcceptedAnswerId, AnswerCount, Body, ClosedDate, CommentCount, CommunityOwnedDate, CreationDate, FavoriteCount, LastActivityDate, LastEditDate, LastEditorDisplayName, LastEditorUserId, OwnerUserId, ParentId, PostTypeId, Score, Tags, Title, ViewCount)
	select top 200000 AcceptedAnswerId, AnswerCount, Body, ClosedDate, CommentCount, CommunityOwnedDate, CreationDate, FavoriteCount, LastActivityDate, LastEditDate, LastEditorDisplayName, LastEditorUserId, OwnerUserId, ParentId, PostTypeId, Score, Tags, Title, ViewCount
	from StackOverflow2013.dbo.Posts 
	go 20
	--order by newid()

-- Stop here
go


begin tran
	update top (20) percent dbo.Posts_TempdbSaver
	set ViewCount = ViewCount+1

	--delete top (10) percent from dbo.Posts_TempdbSaver

	--delete top (10) percent from dbo.Posts_TempdbSaver

	select @@TRANCOUNT

-- do this later.
-- rollback tran

/*
use DBA
go

begin tran
	select * from dbo.Posts_TempdbSaver

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


/*
use tempdb;
--	Find used/free space in Database Files
select	SERVERPROPERTY('MachineName') AS srv_name,
		DB_NAME() AS [db_name], f.type_desc, fg.name as file_group, f.name, f.physical_name, 
		[size_GB] = convert(numeric(20,2),(f.size*8.0)/1024/1024), f.max_size, f.growth, 
		[SpaceUsed_gb] = convert(numeric(20,2),CAST(FILEPROPERTY(f.name, 'SpaceUsed') as BIGINT)/128.0/1024)
		,[FreeSpace_GB] = convert(numeric(20,2),(size/128.0 -CAST(FILEPROPERTY(f.name,'SpaceUsed') AS INT)/128.0)/1024)
		,cast((FILEPROPERTY(f.name,'SpaceUsed')*100.0)/size as decimal(20,2)) as Used_Percentage
		,CASE WHEN f.type_desc = 'LOG' THEN (select d.log_reuse_wait_desc from sys.databases as d where d.name = DB_NAME()) ELSE NULL END as log_reuse_wait_desc
		,[set-size-autogrowth] = 'alter database '+quotename(db_name())+' modify file (name = '''+f.name+''', size = 6000mb, growth = 500mb, maxsize = unlimited);'
		,[shrink-cmd] = 'dbcc shrinkfile (N'''+f.name+''' , 5000) --mb'
		,[remove-file] = 'dbcc shrinkfile (N'''+f.name+''' ,emptyfile); alter database '+quotename(db_name())+' modify file (name = '''+f.name+''')'
--into tempdb..db_size_details
from sys.database_files f left join sys.filegroups fg on fg.data_space_id = f.data_space_id
--WHERE f.type_desc <> 'LOG'
--where fg.name like '2021%_M'
--where f.physical_name like 'G:\data\Tesla%'
--and ((size/128.0 -CAST(FILEPROPERTY(f.name,'SpaceUsed') AS INT)/128.0)/1024) > 5.0
--order by f.data_space_id;
order by FreeSpace_GB desc;
*/

/*
declare @_data_used_pct float = 40;
declare @_data_used_gb float = 10;

declare @_sqltext nvarchar(max);
declare @_params nvarchar(max);

set @_params = '@data_used_pct float, @data_used_gb float';
set @_sqltext = '
select	[collection_time_utc] = [updated_date_utc],
		[sql_instance], [data_size_mb], [data_used_mb], [data_used_pct], [log_size_mb], [log_used_mb], 
		[log_used_pct], [version_store_mb], [version_store_pct]
from dbo.tempdb_space_usage_all_servers su
where (su.data_used_pct > @data_used_pct
	or su.data_used_mb > (@data_used_gb*1024) -- 200 gb
	)
and (su.updated_date_utc >= dateadd(minute,-60,getutcdate())
  and su.collection_time_utc >= dateadd(minute,-20,getutcdate())
	)
and exists (select * from dbo.sma_servers s where s.is_decommissioned = 0 and s.is_onboarded = 1 and s.server = su.sql_instance)
'
exec sp_executesql @_sqltext, @_params, @data_used_pct = @_data_used_pct, @data_used_gb = @_data_used_gb;
*/