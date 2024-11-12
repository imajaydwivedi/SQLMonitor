use DBA
go

set nocount on;
declare @host_name varchar(125);
declare @database_name varchar(125);
declare @object_name varchar(255);
declare @sql nvarchar(max);
declare @params nvarchar(max);
declare @lfcr nchar(2) = nchar(13)+nchar(10);

set @params = N'@host_name varchar(125), @database_name varchar(125)';

select @host_name = host_name from dbo.instance_details;
set @object_name = (case when @@SERVICENAME = 'MSSQLSERVER' then 'SQLServer' else 'MSSQL$'+@@SERVICENAME end);
--set @database_name = 'DBA'

set quoted_identifier off;
set @sql = "
;with t_size_start as (
	select 'InitialSize' as QueryData, [RowRank] = row_number()over(partition by instance order by collection_time_utc asc), *
	from dbo.performance_counters pc
	where pc.host_name = @host_name
	and pc.object = ('"+@object_name+":Databases') and pc.counter in ('Data File(s) Size (KB)')
	"+(case when @database_name is null then '--' else '' end)+"and instance = @database_name
)
, t_size_latest as (
	select 'CurrentSize' as QueryData, [RowRank] = row_number()over(partition by instance order by collection_time_utc desc), *
	from dbo.performance_counters pc
	where pc.host_name = @host_name
	and pc.object = ('"+@object_name+":Databases') and pc.counter in ('Data File(s) Size (KB)')
	"+(case when @database_name is null then '--' else '' end)+"and instance = @database_name
)
select 'Db-Size-from-Start' as QueryData, [Database] = l.instance, [start__collection_time_utc] = convert(smalldatetime,i.collection_time_utc)
		,[start__size_gb] = convert(numeric(20,2),i.value/1024/1024) ,[current__size_gb] = convert(numeric(20,2),l.value/1024/1024)
		,DATEDIFF(day,i.collection_time_utc, l.collection_time_utc) as [days-of-growth]
		,[size_gb-of-growth] = convert(numeric(20,2),(l.value-i.value)/1024.0/1024.0)
		,[estimated-size_gb-for-90Days] = convert(numeric(20,2),(((l.value-i.value)/1024.0/1024.0)/(DATEDIFF(day,i.collection_time_utc, l.collection_time_utc)))*90)
from t_size_latest l join t_size_start i on l.instance = i.instance
where l.RowRank = 1 and i.RowRank = 1";
set quoted_identifier on;

exec sp_executesql @sql, @params, @host_name, @database_name;
go
