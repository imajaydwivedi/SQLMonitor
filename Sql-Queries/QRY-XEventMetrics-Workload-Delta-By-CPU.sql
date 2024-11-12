use DBA
go

set nocount on;
declare @top_filter int = 30;

declare @start_time_snap1	datetime2 = '2024-08-20 09:25';
declare @end_time_snap1		datetime2 = '2024-08-20 09:55';
--
declare @start_time_snap2	datetime2 = '2024-08-21 09:25';
declare @end_time_snap2		datetime2 = '2024-08-21 09:55';

if object_id('tempdb..#current') is not null 
	drop table #current;
create table #current
(
	[query] [varchar](50) NOT NULL,
	[date] [date] NOT NULL,
	[row_rank] [bigint] NOT NULL,
	[username] [varchar](255) NOT NULL,
	--[program] [nvarchar](255) NULL,
	[logical_reads_gb] [numeric](20, 2) NULL,
	[logical_reads_mb] [numeric](20, 2) NULL,
	[cpu_time_minutes] [numeric](20, 2) NULL,
	[cpu_time] [varchar](65) NULL,
	[executions > 5 sec] [int] NULL
);
declare @sql nvarchar(max);
declare @params nvarchar(max);
set @params = N'@top_filter int, @start_time_snap1 datetime2, @end_time_snap1 datetime2, @start_time_snap2 datetime2, @end_time_snap2 datetime2';

set quoted_identifier off;
set @sql = "
;with cte as (
	select	[query] = 'total-stats',
			[date] = convert(date,event_time), 
			[row_rank] = row_number()over(partition by convert(date,event_time) order by sum(logical_reads) desc),
			--database_name, username, client_app_name, client_hostname, client_app_name,
			username,
			logical_reads_gb = convert(numeric(20,2),sum(logical_reads)*8.0/1024/1024), 
			logical_reads_mb = convert(numeric(20,2),sum(logical_reads)*8.0/1024), 
			cpu_time_minutes = (sum(cpu_time_ms)/60000),
			cpu_time = convert(varchar,floor((sum(cpu_time_ms)/60000)/60/24)) + ' Day '+ convert(varchar,dateadd(second,(sum(cpu_time_ms)/1000),'1900-01-01 00:00:00'),108)
			,[executions > 5 sec] = count(1)
	from dbo.xevent_metrics rc
	where rc.event_time between @start_time_snap2 and @end_time_snap2
	"+(case when datediff(minute,@start_time_snap2, @end_time_snap2) <= 180 then '' else '--' end)+"or rc.start_time between @start_time_snap2 and @end_time_snap2
	group by convert(date,event_time), 
			--database_name, username, client_app_name, client_hostname, client_app_name
			username
)
select * 
from cte where row_rank <= @top_filter
order by [date],[row_rank];
"
set quoted_identifier on;

print 'Populate table #current..';
insert #current ([query], [date], [row_rank], [username], [logical_reads_gb], [logical_reads_mb], [cpu_time_minutes], [cpu_time], [executions > 5 sec])
exec sp_executesql @sql, @params, @top_filter, @start_time_snap1, @end_time_snap1, @start_time_snap2, @end_time_snap2;

if object_id('tempdb..#previous') is not null 
	drop table #previous;
create table #previous
(
	[query] [varchar](50) NOT NULL,
	[date] [date] NOT NULL,
	[row_rank] [bigint] NOT NULL,
	[username] [varchar](255) NOT NULL,
	--[program] [nvarchar](255) NULL,
	[logical_reads_gb] [numeric](20, 2) NULL,
	[logical_reads_mb] [numeric](20, 2) NULL,
	[cpu_time_minutes] [numeric](20, 2) NULL,
	[cpu_time] [varchar](65) NULL,
	[executions > 5 sec] [int] NULL
);

set quoted_identifier off;
set @sql = "
;with cte as (
	select	[query] = 'total-stats',
			[date] = convert(date,event_time), 
			[row_rank] = row_number()over(partition by convert(date,event_time) order by sum(logical_reads) desc),
			--database_name, username, client_app_name, client_hostname, client_app_name,
			username,
			logical_reads_gb = convert(numeric(20,2),sum(logical_reads)*8.0/1024/1024), 
			logical_reads_mb = convert(numeric(20,2),sum(logical_reads)*8.0/1024), 
			cpu_time_minutes = (sum(cpu_time_ms)/60000),
			cpu_time = convert(varchar,floor((sum(cpu_time_ms)/60000)/60/24)) + ' Day '+ convert(varchar,dateadd(second,(sum(cpu_time_ms)/1000),'1900-01-01 00:00:00'),108)
			,[executions > 5 sec] = count(1)
	from dbo.xevent_metrics rc
	where rc.event_time between @start_time_snap1 and @end_time_snap1
	"+(case when datediff(minute,@start_time_snap1, @end_time_snap1) <= 180 then '' else '--' end)+"or rc.start_time between @start_time_snap1 and @end_time_snap1
	group by convert(date,event_time), 
			--database_name, username, client_app_name, client_hostname, client_app_name
			username
)
select * from cte where row_rank <= @top_filter
order by [date],[row_rank];
";
set quoted_identifier on;

print 'Populate table #previous..';
insert #previous ([query], [date], [row_rank], [username], [logical_reads_gb], [logical_reads_mb], [cpu_time_minutes], [cpu_time], [executions > 5 sec])
exec sp_executesql @sql, @params, @top_filter, @start_time_snap1, @end_time_snap1, @start_time_snap2, @end_time_snap2;

select	[query] = 'workload-by-CPU', 		
		[date-snap1] = coalesce(p.date, prev_date),
		[date-snap2] = coalesce(c.date, cur_date), 
		[user_name] = coalesce(c.username,p.username),		
		/*
		[cpu_min (+-)] = case when isnull(c.cpu_time_minutes,0.0) > isnull(p.cpu_time_minutes,0.0) 
										then convert(varchar,isnull(c.cpu_time_minutes,0.0) - isnull(p.cpu_time_minutes,0.0)) +N' +'
										when isnull(c.cpu_time_minutes,0.0) = isnull(p.cpu_time_minutes,0.0) then '='
										else convert(varchar,isnull(p.cpu_time_minutes,0.0)-isnull(c.cpu_time_minutes,0.0))+N' -' end,
		*/
		[cpu_time (+/-)] = case when isnull(c.cpu_time_minutes,0.0) > isnull(p.cpu_time_minutes,0.0) 
										-- (isnull(c.cpu_time_minutes,0.0) - isnull(p.cpu_time_minutes,0.0))
										then convert(varchar,floor(((isnull(c.cpu_time_minutes,0.0) - isnull(p.cpu_time_minutes,0.0)))/60/24)) + ' Day '+ convert(varchar,dateadd(minute,((isnull(c.cpu_time_minutes,0.0) - isnull(p.cpu_time_minutes,0.0))),'1900-01-01 00:00:00'),108) +N' +'
										when isnull(c.cpu_time_minutes,0.0) = isnull(p.cpu_time_minutes,0.0) then '='
										else convert(varchar,floor(((isnull(p.cpu_time_minutes,0.0) - isnull(c.cpu_time_minutes,0.0)))/60/24)) + ' Day '+ convert(varchar,dateadd(minute,((isnull(p.cpu_time_minutes,0.0) - isnull(c.cpu_time_minutes,0.0))),'1900-01-01 00:00:00'),108) +N' -' 
										end,
		[executions (+-)] = case when isnull(c.[executions > 5 sec],0) > isnull(p.[executions > 5 sec],0) 
										then convert(varchar,isnull(c.[executions > 5 sec],0) - isnull(p.[executions > 5 sec],0))+N' +'
										when isnull(c.[executions > 5 sec],0) = isnull(p.[executions > 5 sec],0) then '='
										else convert(varchar,isnull(p.[executions > 5 sec],0)-isnull(c.[executions > 5 sec],0))+N' -' end,
		[logical_reads_gb (+-)] = case when isnull(c.logical_reads_gb,0.0) > isnull(p.logical_reads_gb,0.0) 
										then convert(varchar,isnull(c.logical_reads_gb,0.0) - isnull(p.logical_reads_gb,0.0))+N' +'
										when isnull(c.logical_reads_gb,0.0) = isnull(p.logical_reads_gb,0.0) then '='
										else convert(varchar,isnull(p.logical_reads_gb,0.0)-isnull(c.logical_reads_gb,0.0))+N' -' end,
		[cpu_time-snap1] = p.cpu_time,
		[cpu_time-snap2] = c.cpu_time,
		[cpu_TOTAL (+/-)] = case when sum(c.cpu_time_minutes)over() > sum(p.cpu_time_minutes)over() 
										--then convert(varchar,sum(c.cpu_time_minutes)over() - sum(p.cpu_time_minutes)over()) +N' +'
										--(sum(c.cpu_time_minutes)over() - sum(p.cpu_time_minutes)over())
										then convert(varchar,floor(((sum(c.cpu_time_minutes)over() - sum(p.cpu_time_minutes)over()))/60/24)) + ' Day '+ convert(varchar,dateadd(minute,((sum(c.cpu_time_minutes)over() - sum(p.cpu_time_minutes)over())),'1900-01-01 00:00:00'),108) +N' +'
										when sum(c.cpu_time_minutes)over() = sum(p.cpu_time_minutes)over() then '='
										else convert(varchar,floor(((sum(p.cpu_time_minutes)over() - sum(c.cpu_time_minutes)over()))/60/24)) + ' Day '+ convert(varchar,dateadd(minute,((sum(p.cpu_time_minutes)over() - sum(c.cpu_time_minutes)over())),'1900-01-01 00:00:00'),108) +N' -' 
										end,
		[executions > 5 sec - snap1] = p.[executions > 5 sec],
		[executions > 5 sec - snap2] = c.[executions > 5 sec]		
		,[logical_reads_gb-snap1] = p.logical_reads_gb
		,[logical_reads_gb-snap2] = c.logical_reads_gb		
		,[logical_reads_gb_TOTAL (+-)] = case when (sum(c.logical_reads_gb)over()) - (sum(p.logical_reads_gb)over()) >= 0.0 
										then convert(varchar,(sum(c.logical_reads_gb)over()) - (sum(p.logical_reads_gb)over()))+N' +'
										else convert(varchar,(sum(p.logical_reads_gb)over())-(sum(c.logical_reads_gb)over()))+N' -'
										end
from #current c full outer join #previous p on c.username = p.username
outer apply (select top 1 i.date as cur_date from #current i) cur
outer apply (select top 1 i.date as prev_date from #previous i) prev
where abs(isnull(c.cpu_time_minutes,0.0) - isnull(p.cpu_time_minutes,0.0)) >= 5
order by abs(isnull(c.cpu_time_minutes,0.0) - isnull(p.cpu_time_minutes,0.0)) desc
go

/*
--	GROUP BY LOGIN --
;with cte as (
	select  --top 10 with ties
			[query] = 'hourly-stats',
			[date] = convert(date,event_time), [hour] = right('00'+convert(varchar,datepart(hour,event_time)),2),
			[row_rank] = row_number()over(partition by convert(date,event_time), right('00'+convert(varchar,datepart(hour,event_time)),2) order by sum(logical_reads) desc),
			--database_name, username, client_app_name, client_hostname, client_app_name,
			username,
			logical_reads_gb = convert(numeric(20,2),sum(logical_reads)*8.0/1024/1024), 
			logical_reads_mb = convert(numeric(20,2),sum(logical_reads)*8.0/1024), 
			--cpu_time_hours = (sum(cpu_time)/1e+6)/60/60,
			cpu_time = convert(varchar,floor((sum(cpu_time)/1e+6)/60/60/24)) + ' Day '+ convert(varchar,dateadd(second,(sum(cpu_time)/1e+6),'1900-01-01 00:00:00'),108)
			,[executions > 5 sec] = count(1)
	from dbo.xevent_metrics rc
	where rc.event_time between '2022-08-16 07:30' and '2022-08-16 16:00'
	group by convert(date,event_time), right('00'+convert(varchar,datepart(hour,event_time)),2), 
			--database_name, username, client_app_name, client_hostname, client_app_name
			username
)
select * from cte where row_rank <= 3
order by [date],[hour],[row_rank]
go

;with cte as (
	select --top 20 
			[query] = 'hourly-stats',
			[date] = convert(date,event_time), [hour] = right('00'+convert(varchar,datepart(hour,event_time)),2),
			[row_rank] = row_number()over(partition by convert(date,event_time), right('00'+convert(varchar,datepart(hour,event_time)),2) order by sum(logical_reads) desc),
			--database_name, username, client_app_name, client_hostname, client_app_name,
			username,
			logical_reads_gb = convert(numeric(20,2),sum(logical_reads)*8.0/1024/1024), 
			logical_reads_mb = convert(numeric(20,2),sum(logical_reads)*8.0/1024), 
			--cpu_time_hours = (sum(cpu_time)/1e+6)/60/60,
			cpu_time = convert(varchar,floor((sum(cpu_time)/1e+6)/60/60/24)) + ' Day '+ convert(varchar,dateadd(second,(sum(cpu_time)/1e+6),'1900-01-01 00:00:00'),108)
			,[executions > 5 sec] = count(1)
	from dbo.xevent_metrics rc
	where rc.event_time between '2022-08-09 07:30' and '2022-08-09 16:00'
	group by convert(date,event_time), right('00'+convert(varchar,datepart(hour,event_time)),2), 
			--database_name, username, client_app_name, client_hostname, client_app_name
			username
)
select * from cte where row_rank <= 3
order by [date],[hour],[row_rank]
go

*/