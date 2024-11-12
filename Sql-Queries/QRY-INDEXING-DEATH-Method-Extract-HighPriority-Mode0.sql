use DBA_Admin
go

--create table more_info_table_DBE_21 (more_info nvarchar(2000));
/*
set quoted_identifier off;
insert more_info_table_DBE_21
select "EXEC dbo.sp_BlitzIndex @DatabaseName='StackOverflow', @SchemaName='dbo', @TableName='Posts';";
set quoted_identifier on;
*/

;with t_index_info as (
	select bi.more_info, bi.finding, bi.database_name, bi.details, bi.index_definition, bi.secret_columns,
			bi.index_size_summary, bi.index_usage_summary, bi.url, bi.create_tsql, bi.priority
			,[table_records] = count(*) over (partition by bi.more_info)
			,[total_priority] = sum(priority) over (partition by bi.more_info)
			,[row_id] = ROW_NUMBER() over (partition by bi.more_info order by bi.priority asc)
	from dbo.BlitzIndex_Mode0 bi
	where 1=1
	--and bi.run_datetime = (select max(run_datetime) from dbo.BlitzIndex_Mode0)
	and bi.run_datetime = '2024-03-01 20:16:00.000'
	and priority <> -1
	and bi.more_info not in (select e.more_info from more_info_table_DBE_21 e)
)
select [table_records], bi.more_info, bi.finding, bi.database_name, bi.details, bi.index_definition, bi.secret_columns,
			bi.index_size_summary, bi.index_usage_summary, bi.url, bi.create_tsql, bi.priority
from t_index_info bi
order by [table_records] desc, [row_id] asc