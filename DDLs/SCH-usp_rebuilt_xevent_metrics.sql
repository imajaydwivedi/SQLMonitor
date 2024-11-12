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

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_rebuilt_xevent_metrics')
    EXEC ('CREATE PROC dbo.usp_rebuilt_xevent_metrics AS SELECT ''stub version, to be replaced''')
GO

ALTER PROCEDURE dbo.usp_rebuilt_xevent_metrics
	@verbose tinyint = 0,
	@dry_run bit = 0
AS 
BEGIN

	/*
		Version:		0.0.0
		Date:			2022-11-15 - Initial Draft - NOT PRODUCTION READY

		EXEC dbo.usp_rebuilt_xevent_metrics @verbose = 2, @dry_run = 1;
	*/
	SET NOCOUNT ON;

	declare @_sql nvarchar(max);
	declare @_params nvarchar(max);
	declare @_err_message nvarchar(2000);
	declare @_crlf nchar(2);
	declare @_tab nchar(1);
	declare @_tables nvarchar(2000);
	declare @_is_columnstore bit = 0;

	declare @PartitionBoundaryValue_StartDate date --= dateadd(day,-3,getdate());
	declare @PartitionBoundaryValue_EndDate_EXCLUSIVE date --= dateadd(day,-2,getdate());
	declare @TableName nvarchar(125) = 'dbo.xevent_metrics';

	declare @sql nvarchar(max);

	set @_crlf = nchar(13)+nchar(10);
	set @_tab = nchar(9);

	if exists (select 1 from sys.indexes i where i.object_id = OBJECT_ID('dbo.xevent_metrics') and i.index_id <= 1 and i.type_desc = 'CLUSTERED COLUMNSTORE')
		set @_is_columnstore = 1;

	if @_is_columnstore = 0
		print '('+convert(varchar,getdate(),120)+')'+@_tab+'Table [dbo].[xevent_metrics] is not clustered columnstore table.';
	else
		print '('+convert(varchar,getdate(),120)+')'+@_tab+'Table [dbo].[xevent_metrics] qualify clustered columnstore table scenario.'

	if object_id('dbo.xevent_metrics_staging') is null and @_is_columnstore = 1
	begin
		if @verbose > 0
			print '('+convert(varchar,getdate(),120)+')'+@_tab+'Table [dbo].[xevent_metrics_staging] does not exist. So creating it..'
		CREATE TABLE [dbo].[xevent_metrics_staging]
		(
			[row_id] [bigint] NOT NULL,
			[start_time] [datetime2](7) NOT NULL,
			[event_time] [datetime2](7) NOT NULL,
			[event_name] [nvarchar](60) NOT NULL,
			[session_id] [int] NOT NULL,
			[request_id] [int] NOT NULL,
			[result] [varchar](50) NULL,
			[database_name] [varchar](255) NULL,
			[client_app_name] [varchar](255) NULL,
			[username] [varchar](255) NULL,
			[cpu_time] [bigint] NULL,
			[duration_seconds] [bigint] NULL,
			[logical_reads] [bigint] NULL,
			[physical_reads] [bigint] NULL,
			[row_count] [bigint] NULL,
			[writes] [bigint] NULL,
			[spills] [bigint] NULL,
			[client_hostname] [varchar](255) NULL,
			[session_resource_pool_id] [int] NULL,
			[session_resource_group_id] [int] NULL,
			[scheduler_id] [int] NULL,
			INDEX CCI CLUSTERED COLUMNSTORE
		);
	end
	else
	begin
		if @verbose > 0
			print '('+convert(varchar,getdate(),120)+')'+@_tab+'Table [dbo].[xevent_metrics_staging] already exists.'
	end

	if not exists (select 1 from dbo.xevent_metrics) and @_is_columnstore = 1
	begin
		if @verbose > 0
			print '('+convert(varchar,getdate(),120)+')'+@_tab+'Table [dbo].[xevent_metrics_staging] already exists.'

		-- View Partitioned Table information
		SELECT [ObjectName] = quotename(db_name())+'.'+quotename(OBJECT_SCHEMA_NAME(i.object_id))+'.'+quotename(OBJECT_NAME(i.object_id))
			,i.type_desc as [Structure]
			--,ps.name AS PartitionSchemeName
			,ds.name AS [FileGroup||PartitionScheme]
			,pf.name AS PartitionFunctionName
			,CASE when pf.boundary_value_on_right is null then null 
					when pf.boundary_value_on_right = 0 THEN 'Range Left' ELSE 'Range Right' END AS PartitionFunctionRange
			,CASE when pf.boundary_value_on_right is null then null 
				when pf.boundary_value_on_right = 0 THEN 'Upper Boundary' ELSE 'Lower Boundary' END AS PartitionBoundary
			,prv.value AS PartitionBoundaryValue
			,c.name AS PartitionKey
			,CASE 
				WHEN pf.boundary_value_on_right = 0 
				THEN c.name + ' > ' + CAST(ISNULL(LAG(prv.value) OVER(PARTITION BY pstats.object_id ORDER BY pstats.object_id, pstats.partition_number), 'Infinity') AS VARCHAR(100)) + ' and ' + c.name + ' <= ' + CAST(ISNULL(prv.value, 'Infinity') AS VARCHAR(100)) 
				ELSE c.name + ' >= ' + CAST(ISNULL(prv.value, 'Infinity') AS VARCHAR(100))  + ' and ' + c.name + ' < ' + CAST(ISNULL(LEAD(prv.value) OVER(PARTITION BY pstats.object_id ORDER BY pstats.object_id, pstats.partition_number), 'Infinity') AS VARCHAR(100))
			END AS PartitionRange
			,pstats.partition_number AS PartitionNumber
			,pstats.row_count AS PartitionRowCount
			,p.data_compression_desc AS DataCompression
			,fg.name as [Filegroup]
		FROM sys.indexes AS i -- 1 row per index
		INNER JOIN sys.data_spaces AS ds 
			ON ds.data_space_id = i.data_space_id -- dds.data_space_id
		INNER JOIN sys.dm_db_partition_stats AS pstats  -- 1 row per index per partition
			ON pstats.object_id = i.object_id AND pstats.index_id = i.index_id
		INNER JOIN sys.partitions AS p 
			ON pstats.object_id = i.object_id 
			and pstats.index_id = i.index_id 
			and pstats.partition_id = p.partition_id
		JOIN sys.allocation_units as au on au.container_id = p.hobt_id
			and au.type_desc ='IN_ROW_DATA' 
				/* Avoiding double rows for columnstore indexes. */
				/* We can pick up LOB page count from partition_stats */
		JOIN sys.filegroups as fg on fg.data_space_id = au.data_space_id
		LEFT JOIN sys.partition_schemes AS ps 
			ON ps.data_space_id = i.data_space_id
		LEFT JOIN sys.partition_functions AS pf 
			ON pf.function_id = ps.function_id
		LEFT JOIN sys.index_columns AS ic ON i.index_id = ic.index_id AND i.object_id = ic.object_id AND ic.partition_ordinal > 0
		LEFT JOIN sys.columns AS c ON i.object_id = c.object_id AND ic.column_id = c.column_id
		LEFT JOIN sys.partition_range_values AS prv ON pf.function_id = prv.function_id
				AND pstats.partition_number = (CASE pf.boundary_value_on_right WHEN 0 THEN prv.boundary_id ELSE (prv.boundary_id+1) END)
		--LEFT JOIN sys.destination_data_spaces dds
		--	ON dds.partition_scheme_id = ps.data_space_id and dds.data_space_id = ds.data_space_id
		WHERE 1=1
		and (i.object_id = OBJECT_ID('dbo.xevent_metrics'))
		--and (prv.value >= @PartitionBoundaryValue_StartDate and prv.value < @PartitionBoundaryValue_EndDate_EXCLUSIVE) 
		ORDER BY [ObjectName], PartitionNumber
		option (recompile)
	end

END
GO

EXEC dbo.usp_rebuilt_xevent_metrics @verbose = 2, @dry_run = 1;
go

