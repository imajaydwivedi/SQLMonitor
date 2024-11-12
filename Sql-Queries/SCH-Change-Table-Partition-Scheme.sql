use DBA
go

declare @pk_name nvarchar(125) = null;
select	@pk_name = i.name /* i.object_id, i.name, i.index_id, i.type_desc as index_type, ds.name, ds.type_desc as partition_type */
from sys.indexes i join sys.data_spaces ds on ds.data_space_id = i.data_space_id
where i.object_id = OBJECT_ID('dbo.disk_space') and i.type_desc = 'CLUSTERED' and ds.name <> 'ps_dba_datetime2_daily'

if @pk_name is not null and exists (select * from sys.data_spaces where name = 'ps_dba_datetime2_daily')
begin
	declare @sql nvarchar(4000);
	set @sql = 'alter table dbo.disk_space drop constraint '+@pk_name;
	exec (@sql);

	exec ('alter table dbo.disk_space add constraint pk_disk_space primary key ([collection_time_utc],[host_name],[disk_volume]) on ps_dba_datetime2_daily ([collection_time_utc])');
end
go

if not exists (select * from sys.indexes where [object_id] = OBJECT_ID('[dbo].[disk_space]') and type_desc = 'CLUSTERED')
begin
	alter table [dbo].[disk_space] add constraint pk_disk_space primary key ([collection_time_utc],[host_name],[disk_volume]);
end
go

declare @pk_name nvarchar(125) = null;
select	@pk_name = i.name /* i.object_id, i.name, i.index_id, i.type_desc as index_type, ds.name, ds.type_desc as partition_type */
from sys.indexes i join sys.data_spaces ds on ds.data_space_id = i.data_space_id
where i.object_id = OBJECT_ID('dbo.file_io_stats') and i.type_desc = 'CLUSTERED' and ds.name <> 'ps_dba_datetime2_daily'

if @pk_name is not null and exists (select * from sys.data_spaces where name = 'ps_dba_datetime2_daily')
begin
	declare @sql nvarchar(4000);
	set @sql = 'alter table dbo.file_io_stats drop constraint '+@pk_name;
	exec (@sql);

	exec ('alter table dbo.file_io_stats add constraint pk_file_io_stats primary key ([collection_time_utc], [database_id], [file_id]) on ps_dba_datetime2_daily ([collection_time_utc])');
end
go

if not exists (select * from sys.indexes where [object_id] = OBJECT_ID('[dbo].[file_io_stats]') and type_desc = 'CLUSTERED')
begin
	alter table dbo.file_io_stats add constraint pk_file_io_stats primary key ([collection_time_utc], [database_id], [file_id]);
end
go

declare @pk_name nvarchar(125) = null;
select	@pk_name = i.name /* i.object_id, i.name, i.index_id, i.type_desc as index_type, ds.name, ds.type_desc as partition_type */
from sys.indexes i join sys.data_spaces ds on ds.data_space_id = i.data_space_id
where i.object_id = OBJECT_ID('dbo.wait_stats') and i.type_desc = 'CLUSTERED' and ds.name <> 'ps_dba_datetime2_daily'

if @pk_name is not null and exists (select * from sys.data_spaces where name = 'ps_dba_datetime2_daily')
begin
	declare @sql nvarchar(4000);
	set @sql = 'alter table dbo.wait_stats drop constraint '+@pk_name;
	exec (@sql);

	exec ('alter table [dbo].[wait_stats] add constraint pk_wait_stats primary key ([collection_time_utc], [wait_type]) on ps_dba_datetime2_daily ([collection_time_utc])');
end
go

if not exists (select * from sys.indexes where [object_id] = OBJECT_ID('[dbo].[wait_stats]') and type_desc = 'CLUSTERED')
begin
	alter table [dbo].[wait_stats] add constraint pk_wait_stats primary key ([collection_time_utc], [wait_type]);
end
go

if exists (select * from sys.data_spaces where name = 'ps_dba_datetime2_daily')
	exec usp_enable_page_compression @verbose = 0, @dry_run = 0;
go

declare @dbName nvarchar(125) = db_name();
exec sp_BlitzIndex @DatabaseName = @dbName, @BringThePain = 1, @Mode = 2;
go