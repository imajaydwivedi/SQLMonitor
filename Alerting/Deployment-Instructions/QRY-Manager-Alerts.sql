use DBA;
select *
-- update a set state = 'Resolved'
from DBA.dbo.sma_alert a
where a.state <> 'Resolved'

