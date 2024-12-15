use DBA
go
;with t_top_io_pending as (
    select database_name, collection_time_utc, io_pending_count = sum(io_pending_count)
            ,rank_id = ROW_NUMBER()over(partition by database_name order by sum(io_pending_count) desc, collection_time_utc desc)
    from dbo.file_io_stats fis
    where fis.io_pending_count is not null
    group by database_name, collection_time_utc
)
select *
from t_top_io_pending
where rank_id <= 5
order by io_pending_count DESC