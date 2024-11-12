use DBA
go
/* Script to get Top Tables that should be Analyzed for Indexing */
set nocount on;
declare @sql nvarchar(max);
declare @params nvarchar(2000);
declare @more_info_filter varchar(2000);
declare @run_datetime_mode0 datetime = '2024-03-01 20:16:00.000';
declare @run_datetime_mode2 datetime = '2024-03-01 19:26:00.000';
declare @heap_size_mb_threshold numeric(20,2) = '200';
declare @heap_reads_mimimum int = 100;

set @params = '@more_info_filter varchar(2000), @run_datetime_mode0 datetime, @run_datetime_mode2 datetime, @heap_size_mb_threshold numeric(20,2), @heap_reads_mimimum int';

-- Get Findings that should be evaluated further before analysis to decide if Should be Ignored or not
if object_id('tempdb..#BlitzIndex_Mode0_Heaps') is not null
	drop table #BlitzIndex_Mode0_Heaps;
select distinct finding, bi.database_name, more_info
into #BlitzIndex_Mode0_Heaps
from dbo.BlitzIndex_Mode0 bi
where 1=1
--and bi.priority = -1 -- Use it to find out stats for max UpTime Days
and bi.run_datetime = @run_datetime_mode0
--and bi.finding in ('Self Loathing Indexes: Small Active heap','Self Loathing Indexes: Medium Active heap','Self Loathing Indexes: Large Active Heap');
and bi.finding like '%Heap%'

print 'Total records in #BlitzIndex_Mode0_Heaps => '+convert(varchar,@@rowcount);

-- Create table skeleton to store more filtered High Priority Heap warnings
if object_id('tempdb..#BlitzIndex_Mode0_Heaps_Final') is not null
	drop table #BlitzIndex_Mode0_Heaps_Final;
select *
into #BlitzIndex_Mode0_Heaps_Final
from #BlitzIndex_Mode0_Heaps
where 1=0;

-- Loop through Heaps warnings, and filter out Heaps that do not qualify based on {row count/size/reads}
declare @db_name varchar(255);
declare @db_db_name varchar(255) = db_name();
declare cur_index_dbs cursor local fast_forward for
	select distinct [database_name] from #BlitzIndex_Mode0_Heaps;

open cur_index_dbs;
fetch next from cur_index_dbs into @db_name;
while @@FETCH_STATUS = 0
begin
	set quoted_identifier off;
	set @sql = "
use ["+@db_name+"];
insert #BlitzIndex_Mode0_Heaps_Final (finding, database_name, more_info)
select fi.finding, fi.database_name, fi.more_info
from #BlitzIndex_Mode0_Heaps fi
join ["+(@db_db_name  collate SQL_Latin1_General_CP1_CI_AS)+"].dbo.BlitzIndex bi 
	on bi.more_info collate SQL_Latin1_General_CP1_CI_AS = fi.more_info collate SQL_Latin1_General_CP1_CI_AS
	and bi.run_datetime = @run_datetime_mode2
	and bi.index_id <= 1
where exists (	select 1/0 
				/* There is identity column present */
				from sys.tables t
				join sys.identity_columns c
					on c.object_id = t.object_id
				join sys.schemas s
					on s.schema_id = t.schema_id
				where s.name collate SQL_Latin1_General_CP1_CI_AS = bi.schema_name collate SQL_Latin1_General_CP1_CI_AS 
				and t.name collate SQL_Latin1_General_CP1_CI_AS = bi.table_name collate SQL_Latin1_General_CP1_CI_AS
		)
	or ( (bi.total_reserved_MB >= @heap_size_mb_threshold) and (bi.reads_per_write > 1.0) and (bi.total_reads >= @heap_reads_mimimum) )
	or ( (bi.total_reserved_MB >= (@heap_size_mb_threshold*2)) and (bi.total_reads > @heap_reads_mimimum/2) )
";
	set quoted_identifier on;
	--print @sql;

	/*	Heap table with either -
			- Identity column
			- Forwarded records
			- Size over @heap_size_mb_threshold & there are more reads than writes on table
			- Size over (@heap_size_mb_threshold * 2) & there are reads on table
	*/
	exec sp_executesql @sql, @params, @more_info_filter, @run_datetime_mode0, @run_datetime_mode2, @heap_size_mb_threshold, @heap_reads_mimimum;

	fetch next from cur_index_dbs into @db_name;
end
close cur_index_dbs;
deallocate cur_index_dbs;

-- Get All Index Warnings with Filtered warnings for Heaps
if object_id('tempdb..#BlitzIndex_Mode0_FinalPrint') is not null
	drop table #BlitzIndex_Mode0_FinalPrint;
select	[sno] = right('000'+convert(varchar,ROW_NUMBER()over(order by min(bi.priority), sum(bi.priority) desc, bi.more_info)),3), 
		bi.more_info, sum(bi.priority) as priority_total, min(bi.priority) as priority_min
		--[print-msg] = N'-- '+right('000'+convert(varchar,ROW_NUMBER()over(order by min(bi.priority), sum(bi.priority) desc, bi.more_info)),3)+') '
		--				+ ' Priority_total='+convert(varchar,sum(bi.priority))+' , Priority_min='+convert(varchar,min(bi.priority))
		--				+ nchar(13) + bi.more_info + nchar(13)
into #BlitzIndex_Mode0_FinalPrint
from dbo.BlitzIndex_Mode0 bi
where 1=1
and bi.priority <> -1 -- Use it to find out stats for max UpTime Days
and bi.run_datetime = @run_datetime_mode0
--and bi.database_name not in ('DBA','Facebook')
and (	bi.finding not in ('Self Loathing Indexes: Small Active heap','Self Loathing Indexes: Medium Active heap','Self Loathing Indexes: Large Active Heap')
		or
		(	bi.finding in ('Self Loathing Indexes: Small Active heap','Self Loathing Indexes: Medium Active heap','Self Loathing Indexes: Large Active Heap')
			and exists (	select 1/0
							from #BlitzIndex_Mode0_Heaps_Final ff
							where ff.more_info = bi.more_info
					)
		)
	)
--and bi.finding = 'Self Loathing Indexes: Heaps with Forwarded Fetches'
group by bi.more_info;
--order by priority_min, priority_total DESC, bi.more_info
--order by [print-msg];

-- Print user friendly indexing info
--declare @run_datetime_mode0 datetime = '2024-01-26 20:13:00.000';
--declare @run_datetime_mode2 datetime = '2024-02-01 20:39:00.000';
	select	sno, more_info, priority_total, priority_min, m2.tbl_name, m2.type, m2.index_size_summary,
			m2.data_compression_desc, m2.index_usage_summary, m2.index_op_stats, m2.index_definition, m2.pk_definition,
			[total_nci_count] = (select count(*) from dbo.BlitzIndex nci where nci.run_datetime = @run_datetime_mode2 
																and nci.more_info = bi.more_info and nci.index_id > 1),
			m2.[database_name], m2.schema_name, m2.table_name
			--[@run_datetime_mode0] = @run_datetime_mode0, [@run_datetime_mode2] = @run_datetime_mode2
	from #BlitzIndex_Mode0_FinalPrint bi
	outer apply (select m2.database_name, m2.schema_name, m2.table_name,
						[tbl_name] = quotename(m2.database_name)+'.'+quotename(m2.schema_name)+'.'+quotename(m2.table_name),
						[type] = (case when m2.index_id = 1 and m2.is_primary_key = 1 then '[CX][PK]. '
										when m2.index_id = 1 and m2.is_primary_key = 0 then '[CX]. '
										when m2.index_id = 0 then '[HEAP]. ' 
										end) +
								 (case when pk.is_primary_key = 1 then '[PK]. ' else '' end),
						m2.index_size_summary,
						m2.data_compression_desc,
						m2.index_usage_summary,
						m2.index_op_stats,
						m2.index_definition,
						pk_definition = pk.index_definition
					from dbo.BlitzIndex m2 
					left outer join dbo.BlitzIndex pk
						on pk.more_info = m2.more_info
						and pk.run_datetime = m2.run_datetime
						and pk.index_id > 1 and pk.is_primary_key = 1
					where m2.more_info = bi.more_info
					and m2.run_datetime = @run_datetime_mode2
					and m2.index_id <= 1

				) m2
	order by sno;

declare @_sno varchar(10);
declare @_more_info nvarchar(2000);
declare @_priority_total int;
declare @_priority_min int;
declare @_tbl_name_full nvarchar(500);
declare @_type varchar(20);
declare @_index_size_summary varchar(500);
declare @_data_compression_desc varchar(500);
declare @_index_usage_summary varchar(500);
declare @_index_op_stats varchar(500);
declare @_index_definition varchar(500);
declare @_pk_definition varchar(500);
declare @_total_nci_count int;
declare @_database_name varchar(255);
declare @_schema_name varchar(255);
declare @_table_name varchar(500);
declare @_total_columns int;
declare @_identity_column varchar(255);
declare @_string varchar(2000);
declare @_sql nvarchar(max);
declare @_params nvarchar(max);
declare @_all_high_priority_warnings varchar(2000);
set @_params = N'@_database_name varchar(255), @_schema_name varchar(255), @_table_name varchar(500), @_total_columns int output, @_identity_column varchar(255) output';

declare cur_tables cursor local fast_forward for
	select	sno, more_info, priority_total, priority_min, m2.tbl_name, m2.type, m2.index_size_summary,
			m2.data_compression_desc, m2.index_usage_summary, m2.index_op_stats, m2.index_definition, m2.pk_definition,
			[total_nci_count] = (select count(*) from dbo.BlitzIndex nci where nci.run_datetime = @run_datetime_mode2 
																and nci.more_info = bi.more_info and nci.index_id > 1),
			m2.[database_name], m2.schema_name, m2.table_name
			--[@run_datetime_mode0] = @run_datetime_mode0, [@run_datetime_mode2] = @run_datetime_mode2
	from #BlitzIndex_Mode0_FinalPrint bi
	outer apply (select m2.database_name, m2.schema_name, m2.table_name,
						[tbl_name] = quotename(m2.database_name)+'.'+quotename(m2.schema_name)+'.'+quotename(m2.table_name),
						[type] = (case when m2.index_id = 1 and m2.is_primary_key = 1 then '[CX][PK]. '
										when m2.index_id = 1 and m2.is_primary_key = 0 then '[CX]. '
										when m2.index_id = 0 then '[HEAP]. ' 
										end) +
								 (case when pk.is_primary_key = 1 then '[PK]. ' else '' end),
						m2.index_size_summary,
						m2.data_compression_desc,
						m2.index_usage_summary,
						m2.index_op_stats,
						m2.index_definition,
						pk_definition = pk.index_definition
					from dbo.BlitzIndex m2 
					left outer join dbo.BlitzIndex pk
						on pk.more_info = m2.more_info
						and pk.run_datetime = m2.run_datetime
						and pk.index_id > 1 and pk.is_primary_key = 1
					where m2.more_info = bi.more_info
					and m2.run_datetime = @run_datetime_mode2
					and m2.index_id <= 1

				) m2
	order by sno;

open cur_tables;
fetch next from cur_tables into @_sno, @_more_info, @_priority_total, @_priority_min, @_tbl_name_full, @_type, @_index_size_summary,
			@_data_compression_desc, @_index_usage_summary, @_index_op_stats, @_index_definition, @_pk_definition, @_total_nci_count, 
			@_database_name, @_schema_name, @_table_name;

while @@FETCH_STATUS = 0
begin
	set @_all_high_priority_warnings = null;
	set @_string = NULL;
	--select @_sno, @_more_info, @_priority_total, @_priority_min, @_tbl_name, @_total_nci_count;
	--break;

	--print 'Fetch total column counts & identity column name for '+@_tbl_name_full+'..';

	;with t_findings as (
		select distinct bi.finding
		from dbo.BlitzIndex_Mode0 bi
		where bi.more_info = @_more_info
		and bi.run_datetime = @run_datetime_mode0
	)
	select @_all_high_priority_warnings = coalesce(@_all_high_priority_warnings + char(13)+char(9)+finding,finding)
	from t_findings;

	set @_sql = N'USE '+QUOTENAME(@_database_name)+';
	;with t_columns as (
		select schema_name = s.name, table_name = t.name, column_name = c.name, c.is_identity,
				column_counts = count(*) over ()
		from sys.tables t 
		join sys.schemas s
			on s.schema_id = t.schema_id
		join sys.columns c 
			on c.object_id = t.object_id
		where 1=1
		and s.name = @_schema_name
		and t.name = @_table_name		
	)
	select top 1 @_total_columns = column_counts, 
				@_identity_column = case when is_identity = 1 then column_name else null end
	from t_columns 
	order by is_identity desc
	';

	exec sp_executesql @_sql, @_params, @_database_name, @_schema_name, @_table_name, @_total_columns output, @_identity_column output;

	set @_string = case when @_index_definition is not null and @_index_definition <> '[HEAP] '
						then @_index_definition 
						else null 
						end;
	set @_string = case when @_string is not null -- cx is not null
						then case when @_pk_definition is not null -- pk is not null
								  then @_string+char(13)+char(9)+@_pk_definition 
								  else @_string 
								  end
						when @_string is null -- cx is null
						then case when @_pk_definition is not null -- pk is not null
								  then @_pk_definition
								  else null
								  end
						else null
						end

	set quoted_identifier off;
	set @_sql = "
/*	*****************************************************************************************************************
	"+@_tbl_name_full+". "+@_type+""+ @_index_size_summary+". "+@_data_compression_desc+"
	"+@_index_usage_summary+"
	"+@_index_op_stats+
	(case when @_string is not null then char(13)+char(9)+@_string else '' end)+ "
	"+(case when @_total_nci_count > 0 then convert(varchar,@_total_nci_count)+' NCIs || ' else '' end) + 
	convert(varchar,@_total_columns)+" columns in table"+coalesce(' || '+quotename(@_identity_column)+' as identity column','')+"

	"+(case when @_all_high_priority_warnings is not null then @_all_high_priority_warnings else '' end)+"

-- "+@_sno+")  Priority_total="+convert(varchar,@_priority_total)+" , Priority_min="+convert(varchar,@_priority_min)+"
"+@_more_info+"
*/

			-- << Some Table Index Changes in HERE >>

/*	ROLLBACK


*/
GO
	";
	set quoted_identifier on;
	print @_sql;

	fetch next from cur_tables into @_sno, @_more_info, @_priority_total, @_priority_min, @_tbl_name_full, @_type, @_index_size_summary,
			@_data_compression_desc, @_index_usage_summary, @_index_op_stats, @_index_definition, @_pk_definition, @_total_nci_count, 
			@_database_name, @_schema_name, @_table_name;
end

close cur_tables;
deallocate cur_tables;

go

/*
SELECT distinct [@run_datetime_mode0] =  run_datetime, index_definition from dbo.BlitzIndex_Mode0 bi
	where run_datetime >= dateadd(day,-30,getdate()) and bi.priority = -1
	order by run_datetime desc offset 0 rows fetch next 10 rows only
	-- 2024-02-16 20:13:00.000

SELECT distinct  [@run_datetime_mode4] =  run_datetime, index_definition from dbo.BlitzIndex_Mode4 bi
	where run_datetime >= dateadd(day,-30,getdate()) and bi.priority = -1
	order by run_datetime desc offset 0 rows fetch next 10 rows only
	-- 2024-01-26 20:40:00.000

SELECT distinct  [@run_datetime_mode2] =  run_datetime from dbo.BlitzIndex bi
	where run_datetime >= dateadd(day,-30,getdate()) 
	order by run_datetime desc offset 0 rows fetch next 20 rows only
	-- 2024-02-01 20:39:00.000

*/
