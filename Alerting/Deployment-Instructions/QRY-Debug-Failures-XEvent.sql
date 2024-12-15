use DBA
go

select *
from dbo.vw_xevent_metrics vw
where 1=1
and vw.event_time >= DATEADD(minute,-120,getdate())

