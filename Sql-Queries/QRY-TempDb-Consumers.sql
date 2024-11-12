use DBA
go

;with MyRows as (
	select	*, 
			LastEntryID = ROW_NUMBER() over (partition by session_id, program_name, login_name, database_name, host_name order by collection_time desc),
			[tempdb_allocations_gb] = convert(numeric(20,2),convert(bigint,replace(ltrim(rtrim(w.tempdb_allocations)),',',''))/128.0/1024)
	from dbo.WhoIsActive w
	where w.collection_time between '2022-12-08 05:00' and '2022-12-08 08:00'
	and (w.tempdb_allocations is not null and convert(bigint,replace(ltrim(rtrim(w.tempdb_allocations)),',','')) > 0)
)
select top 200 *
from MyRows w
where w.LastEntryID = 1 and [tempdb_allocations_gb] >= 5
order by [tempdb_allocations_gb] desc
go

;with MyRows as (
	select	*, 
			LastEntryID = ROW_NUMBER() over (partition by session_id, program_name, login_name, database_name, host_name order by collection_time desc),
			[tempdb_allocations_gb] = convert(numeric(20,2),convert(bigint,replace(ltrim(rtrim(w.tempdb_allocations)),',',''))/128.0/1024)
	from dbo.WhoIsActive w
	where w.collection_time between '2022-11-28 05:00' and '2022-11-28 08:00'
	and (w.tempdb_allocations is not null and convert(bigint,replace(ltrim(rtrim(w.tempdb_allocations)),',','')) > 0)
)
select top 200 *
from MyRows w
where w.LastEntryID = 1 and [tempdb_allocations_gb] >= 5
order by [tempdb_allocations_gb] desc
go

select *
from dbo.vw_xevent_metrics rc
where rc.start_time between '2022-12-08 05:00' and '2022-12-08 08:00'
