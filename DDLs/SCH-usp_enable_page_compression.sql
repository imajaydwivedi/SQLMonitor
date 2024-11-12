IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
SET ARITHABORT ON;
GO

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_enable_page_compression')
    EXEC ('CREATE PROC dbo.usp_enable_page_compression AS SELECT ''stub version, to be replaced''')
GO

ALTER PROCEDURE dbo.usp_enable_page_compression
	@verbose tinyint = 0,
	@dry_run bit = 0
--WITH EXECUTE AS OWNER 
AS 
BEGIN

	/*
		Version:		1.0.1
		Date:			2022-10-15

		exec usp_enable_page_compression @verbose = 2, @dry_run = 1;
	*/
	SET NOCOUNT ON; 
	declare @table_name nvarchar(125);
	declare @index_name nvarchar(125);
	declare @sql_text nvarchar(4000);
	declare @counter int = 1;
	declare @index_counts int = 0;
	--declare @sql nvarchar(max);
	--declare @params nvarchar(max);
	--declare @err_message nvarchar(2000);
	declare @crlf nchar(2);
	declare @tab nchar(1);

	declare @index_table_to_compress table (id int identity(1,1) not null, table_name nvarchar(125) not null, index_name nvarchar(125) null);

	insert @index_table_to_compress (table_name, index_name)
	select table_name, index_name
	from (values ('dbo.performance_counters',NULL),
				 ('dbo.performance_counters','nci_counter_collection_time_utc'),
				 ('dbo.os_task_list',NULL),
				 ('dbo.os_task_list','nci_cpu_time_seconds'),
				  ('dbo.os_task_list','nci_memory_kb'),
				 ('dbo.os_task_list','nci_user_name'),
				 ('dbo.os_task_list','nci_window_title'),
				 ('dbo.wait_stats',NULL),
				 ('dbo.xevent_metrics', NULL),
				 ('dbo.xevent_metrics','uq_xevent_metrics'),
				 --('dbo.xevent_metrics_queries', NULL),
				 ('dbo.disk_space',NULL),
				 ('dbo.BlitzIndex',NULL),
				 ('dbo.file_io_stats',NULL),
				 ('dbo.WrongName',NULL)
		) table_indexes(table_name, index_name);

	select @index_counts = count(*) from @index_table_to_compress;

	if @verbose > 0
	begin
		select	running_query = '@index_table_to_compress',
				is_existing = case when OBJECT_ID(table_name) is null then 0 else 1 end, 
				*
		from @index_table_to_compress;
	end

	while @counter <= @index_counts
	begin
		select @table_name = table_name, @index_name = index_name from @index_table_to_compress where id = @counter;
		
		if @index_name is null
		begin
			set @sql_text = '
					if exists ( select * from sys.partitions p inner join sys.indexes i on p.object_id = i.object_id and p.index_id = i.index_id 
									where p.object_id = object_id('''+@table_name+''') and p.data_compression = 0 and i.index_id  in (0,1))
						ALTER TABLE '+@table_name+' REBUILD PARTITION = ALL WITH (DATA_COMPRESSION = PAGE);
				'+char(10)
		end
		else
		begin
			set @sql_text = '
					if exists ( select * from sys.partitions p inner join sys.indexes i on p.object_id = i.object_id and p.index_id = i.index_id 
									where p.object_id = object_id('''+@table_name+''') and p.data_compression = 0 and i.name = '''+@index_name+''' )
						ALTER INDEX '+quotename(@index_name)+' ON '+@table_name+' REBUILD PARTITION = ALL WITH (DATA_COMPRESSION = PAGE);  
				'+char(10)
		end

		if OBJECT_ID(@table_name) is not null
		begin
			if @verbose > 0
				print @sql_text;
			if @dry_run = 0
				exec (@sql_text);
		end
		else
			print 'Table '+@table_name+' does not exist.'

		set @counter = @counter + 1;
	end
END
GO

IF APP_NAME() = 'Microsoft SQL Server Management Studio - Query'
BEGIN
	exec usp_enable_page_compression;
END
go
