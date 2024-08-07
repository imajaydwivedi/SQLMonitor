;with cte_history as (
	select	srv_name, avg_disk_wait_ms, collection_time
			,row_id = ROW_NUMBER() over (partition by srv_name order by avg_disk_wait_ms desc)
			,row_counts = count(srv_name) over (partition by srv_name)
	from dbo.all_server_volatile_info_history h
	where h.avg_disk_wait_ms > 15
)
select srv_name, avg_disk_wait_ms, collection_time, row_counts
from cte_history h where h.row_id = 1 and row_counts > 10 order by srv_name