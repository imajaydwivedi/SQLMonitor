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

if object_id('tempdb..#FileSize') is not null drop table #FileSize;
create table #FileSize ([Date] date not null, [Database] nvarchar(255) not null, [counter] varchar(255) not null, [SizeKB] numeric(20,2));

set quoted_identifier off;
set @sql = "with Sizing as (
	select *, [RowRank] = row_number()over(partition by convert(date,pc.collection_time_utc), instance, counter order by collection_time_utc asc)
	from dbo.vw_performance_counters pc with (nolock)
	where 1=1
	and pc.host_name = @host_name
	and  pc.object = ('"+@object_name+":Databases') 
	and pc.counter in ('Log File(s) Size (KB)', 'Data File(s) Size (KB)')
	"+(case when @database_name is null then '--' else '' end)+"and instance = @database_name
)
select [Date] = convert(date,collection_time_utc), [Database] = instance, [counter], [SizeKB] = [value]
from Sizing s
where RowRank = 1
"
set quoted_identifier off;

insert #FileSize ([Date], [Database], [counter], [SizeKB])
exec sp_executesql @sql, @params, @host_name, @database_name;

--select * from #FileSize order by 1, 2, 3;

if object_id('tempdb..#DatabaseSize') is not null drop table #DatabaseSize;
select [Date], [Database], 
		[LogSize_gb] = ceiling([Log File(s) Size (KB)]/1024/1024), 
		[DataSize_gb] = ceiling([Data File(s) Size (KB)]/1024/1024),
		[TotalSize_gb] = ceiling(([Log File(s) Size (KB)]+[Data File(s) Size (KB)])/1024/1024)
into #DatabaseSize
from #FileSize up
pivot ( max([SizeKB]) for [counter] in ([log file(s) size (kb)],[Data File(s) Size (KB)]) ) as pvt
order by 1, 2;

--select * from #DatabaseSize order by 1,2;

declare @databases nvarchar(max);

select @databases = coalesce(@databases + ', '+ quotename([Database]), quotename([Database])) 
from (select distinct [Database] from #DatabaseSize ) l
order by [Database];

set quoted_identifier off;
set @sql = "
select [Query] = 'Db-Size-Over-Time-GB', [Server] = @@servername, [Date], "+@databases+"
from (select [Date], [Database], [TotalSize_gb]   from #DatabaseSize) up
pivot ( max([TotalSize_gb]) for [Database] in ("+@databases+") ) pvt
order by 1"
set quoted_identifier off;

exec sp_ExecuteSql @sql;
go

