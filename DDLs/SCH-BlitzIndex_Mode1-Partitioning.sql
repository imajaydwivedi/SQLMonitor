-- SCH-BlitzIndex_Mode1-Partitioning.sql
IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

-- Drop Existing PK
USE [DBA];
declare @table_name sysname;
declare @cx_name sysname;
declare @data_space_id int;
declare @is_partitioned bit = 1;
declare @sql nvarchar(max);
set @table_name = 'dbo.BlitzIndex_Mode1';

--select [@cx_name] = name, [@data_space_id] = data_space_id 
select @cx_name = name, @data_space_id = data_space_id 
from sys.indexes 
where [object_id] = OBJECT_ID(@table_name) 
	and type_desc = 'CLUSTERED';

if		( @cx_name is not null and @is_partitioned = 1 and @data_space_id <= 1 )
	or	( @cx_name is not null and @cx_name <> 'pk_BlitzIndex_Mode1' )
begin
	print @table_name+'.'+quotename(@cx_name)+' can be dropped.';
	set @sql = 'alter table '+@table_name+' drop constraint '+quotename(@cx_name);
	print @sql;
	exec (@sql);
end
else
	if @data_space_id > 1
		print @table_name+' table seems already partitioned.'
	if @cx_name is null
		print @table_name+' table seems to not have [CX].'
GO

-- Create PK with Partitioning
USE [DBA];
declare @table_name sysname;
declare @cx_name sysname;
declare @data_space_id int;
declare @is_partitioned bit = 1;
declare @sql nvarchar(max);
set @table_name = 'dbo.BlitzIndex_Mode1';

--select [@cx_name] = name, [@data_space_id] = data_space_id 
select @cx_name = name, @data_space_id = data_space_id 
from sys.indexes 
where [object_id] = OBJECT_ID(@table_name) 
	and type_desc = 'CLUSTERED';

if @cx_name is null
begin
	print @table_name+' qualify for partitioning.';
	set @cx_name = 'pk_BlitzIndex_Mode1';

	print 'convert identity column to bigint.'
	set @sql = 'alter table '+@table_name+' alter column [id] [bigint] NOT NULL';
	print @sql;
	exec (@sql);

	print 'add default for [run_datetime] column.'
	set @sql = 'alter table '+@table_name+' add default (getdate()) for [run_datetime]';
	print @sql;
	begin try
		exec (@sql);
	end try
	begin catch
		print ERROR_MESSAGE();
	end catch

	print 'convert [run_datetime] column to not null.'
	set @sql = 'alter table '+@table_name+' alter column [run_datetime] [datetime] NOT NULL';
	print @sql;
	exec (@sql);

	if @is_partitioned = 1
		set @sql = 'alter table '+@table_name+' add constraint '+@cx_name+' primary key clustered ([run_datetime],[id]) on ps_dba_datetime_monthly ([run_datetime]);';
	else
		set @sql = 'alter table '+@table_name+' add constraint '+@cx_name+' primary key clustered ([run_datetime],[id]);';
	print @sql;
	exec (@sql);
end
else
begin
	print 'table '+@table_name+' is already having CX.'
	if @data_space_id = 1 and @is_partitioned = 1
		raiserror ('Partitioning should be implemented post dropping CX.', 20, -1) with log;
end
go
