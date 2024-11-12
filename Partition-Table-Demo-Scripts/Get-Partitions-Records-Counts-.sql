use tempdb
go

/* Foreach Partition, get
		- table, filegroup, file, function, scheme,
		- partition range, partition key, 
		- partition number, row_counts
*/
declare @PartitionBoundaryValue_StartDate date --= dateadd(day,-3,getdate());
declare @PartitionBoundaryValue_EndDate_EXCLUSIVE date --= dateadd(day,-2,getdate());
declare @TableName nvarchar(125) = 'performance_counters';
declare @PartitionFunctionFilter nvarchar(125) --= 'pf_dba_datetime_hourly';
declare @NonEmptyPartitionsOnly bit = 1;
declare @OnlyPartitionedObjects bit = 1;

declare @sql nvarchar(max);
declare @params nvarchar(max);

set @params = N'@TableName nvarchar(125), @PartitionBoundaryValue_StartDate date, @PartitionBoundaryValue_EndDate_EXCLUSIVE date, @PartitionFunctionFilter nvarchar(125)';

set quoted_identifier off;
set @sql = "
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
"+(case when @NonEmptyPartitionsOnly is not null and @NonEmptyPartitionsOnly = 1 then '' else '--' end)+"and (pstats.row_count > 0)
"+(case when @OnlyPartitionedObjects is not null and @OnlyPartitionedObjects = 1 then '' else '--' end)+"and (pf.name is not null)
"+(case when @TableName is null then '--' else '' end)+"and (i.object_id = OBJECT_ID(@TableName))
"+(case when @PartitionFunctionFilter is null then '--' else '' end)+"and (pf.name = @PartitionFunctionFilter)
and i.index_id <= 1
"+(case when @PartitionBoundaryValue_StartDate is null then '--' else '' end)+"and prv.value >= @PartitionBoundaryValue_StartDate
"+(case when @PartitionBoundaryValue_EndDate_EXCLUSIVE is null then '--' else '' end)+"and prv.value < @PartitionBoundaryValue_EndDate_EXCLUSIVE
ORDER BY [ObjectName], PartitionNumber
option (recompile)
"
print @sql
exec sp_executesql @sql, @params,
					@TableName, @PartitionBoundaryValue_StartDate, @PartitionBoundaryValue_EndDate_EXCLUSIVE, @PartitionFunctionFilter;
go

/*

SELECT	$PARTITION.pf_dba_datetime2_daily(collection_time_utc) AS Partition,   
		COUNT(*) AS [COUNT] 
FROM dbo.performance_counters
GROUP BY $PARTITION.pf_dba_datetime2_daily(collection_time_utc)  
ORDER BY Partition ;  

*/

SELECT	$PARTITION.pf_dba_datetime2_daily(collection_time_utc) AS Partition, 
		COUNT(*) AS [COUNT] 
FROM dbo.performance_counters
GROUP BY $PARTITION.pf_dba_datetime2_daily(collection_time_utc)  
ORDER BY Partition ;  
go