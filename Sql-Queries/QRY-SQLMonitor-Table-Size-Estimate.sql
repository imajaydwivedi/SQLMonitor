use DBA
go

select table_name = coalesce(pt.table_name, 'dbo.'+bi.table_name), bi.index_name, 
		[retention_days] = case when bi.index_name like '%WhoIsActive%' 
								then (select datediff(day,min(w.collection_time),GETDATE()) from dbo.WhoIsActive w) 
								else pt.retention_days 
								end, 
		bi.index_size_summary, bi.data_compression_desc
from dbo.BlitzIndex bi left join dbo.purge_table pt 
	on pt.table_name = 'dbo.'+bi.table_name
where bi.run_datetime = (select max(run_datetime) from dbo.BlitzIndex i)
and bi.database_name = DB_NAME()
and (pt.table_name is not null or bi.table_name = 'WhoIsActive')


/*
update dbo.purge_table
set retention_days = 365
where table_name in ('dbo.BlitzIndex','dbo.BlitzIndex_Mode0','dbo.BlitzIndex_Mode1','dbo.BlitzIndex_Mode4')
go

update dbo.purge_table
set retention_days = 365*2
where table_name in ('dbo.disk_space')
go

update dbo.purge_table
set retention_days = 30
where table_name in ('dbo.performance_counters')
go

update dbo.purge_table
set retention_days = 365
where table_name in ('dbo.resource_consumption')
go

*/

