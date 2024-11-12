declare @sql nvarchar(max);
declare @params nvarchar(max);
declare @database_name nvarchar(255);
declare @table_name nvarchar(255);
declare @index_name nvarchar(255);
declare @column_name nvarchar(255);

set @database_name = 'StackOverflow';
set @table_name = 'Users';
set @index_name = 'Location';
--set @column_name = 'Location';

set quoted_identifier off;
set @sql = "
use "+@database_name+";
;WITH StatsOnTable AS (
	SELECT	[table_name] = object_name(st.object_id), st.stats_id, ltrim(rtrim(st.name)) as stats_name, filter_definition, last_updated, rows, rows_sampled, steps, unfiltered_rows, 
			modification_counter, [stats_columns] = LTRIM(RTRIM([stats_columns])), [object_id] = st.object_id,
			[leading_stats_col] = ltrim(rtrim(case when charindex(',',c.stats_columns) > 0 
									then left(c.stats_columns,charindex(',',c.stats_columns)-1)
									else c.stats_columns end))
	FROM sys.stats AS st
			CROSS APPLY sys.dm_db_stats_properties(st.object_id, st.stats_id) AS sp
			OUTER APPLY (	SELECT STUFF((SELECT  ', ' + c.name
						FROM  sys.stats_columns as sc
							left join sys.columns as c on sc.object_id = c.object_id AND c.column_id = sc.column_id  
						WHERE sc.object_id = st.object_id and sc.stats_id = st.stats_id
						ORDER BY sc.stats_column_id
						FOR XML PATH('')), 1, 1, '') AS [stats_columns]            
			) c
	WHERE 1=1
	"+(case when @table_name is null then '--' else '' end)+"AND st.object_id = OBJECT_ID(@table_name)
)
SELECT [table_name], stats_id, Stats_Name, filter_definition, last_updated, rows, rows_sampled, steps, unfiltered_rows, modification_counter,
		[stats_columns],
		[!~~~~~~~~~~~~~~~~ tsql-Histogram-Sql2016+ ~~~~~~~~~~~~~~~!] = 'USE "+@database_name+"; select [table_name] = '''+[table_name]+''', stats_col = '''+ltrim(rtrim([leading_stats_col]))+''', * from '+QUOTENAME(DB_NAME())+'.sys.dm_db_stats_histogram ('+convert(varchar,[object_id])+', '+convert(varchar,stats_id)+') h;'
		,[--tsql-SHOW_STATISTICS-STAT_HEADER--] = 'dbcc show_statistics ('''+([table_name] collate SQL_Latin1_General_CP1_CI_AS)+''','+stats_name+') with STAT_HEADER'
		,[--tsql-SHOW_STATISTICS-DENSITY_VECTOR--] = 'dbcc show_statistics ('''+([table_name] collate SQL_Latin1_General_CP1_CI_AS)+''','+stats_name+') with DENSITY_VECTOR'
		,[--tsql-SHOW_STATISTICS-HISTOGRAM--] = 'dbcc show_statistics ('''+([table_name] collate SQL_Latin1_General_CP1_CI_AS)+''','+stats_name+') with HISTOGRAM'
FROM StatsOnTable sts 
WHERE 1=1
"+(case when @index_name is null then '--' else '' end)+"AND Stats_Name = @index_name	
"+(case when @column_name is null then '--' else '' end)+"AND leading_stats_col = @column_name
ORDER BY [stats_columns];
"
set quoted_identifier on;
print @sql

set @params = N'@database_name varchar(255), @table_name varchar(255), @index_name nvarchar(255), @column_name nvarchar(255)';
exec sp_ExecuteSql @sql, @params, @database_name, @table_name, @index_name, @column_name;