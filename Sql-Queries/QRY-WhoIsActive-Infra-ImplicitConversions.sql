use DBA
go

select top 500 *
from dbo.WhoIsActive w
where 1=1
and w.collection_time >= '2023-09-29 13:00'
and w.database_name not in ('DBA')
and (w.query_plan is not null and convert(varchar(max),w.query_plan) like '%PlanAffectingConvert%')
order by reads desc
