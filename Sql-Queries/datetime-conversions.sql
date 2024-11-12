DECLARE @db_name varchar(50);
set @db_name = DB_NAME();

declare @start_time datetime = dateadd(MINUTE,-45,getdate());
declare @end_time datetime = getdate();
declare @start_time_utc datetime = dateadd(MINUTE,-45,getutcdate());
declare @end_time_utc datetime = getutcdate();

select [@start_time] = @start_time, [@end_time] = @end_time, [@start_time_utc] = @start_time_utc, [@end_time_utc] = @end_time_utc;

select	[SYSDATETIMEOFFSET] = SYSDATETIMEOFFSET(), 
		[SYSDATETIME] = SYSDATETIME(), 
		[SYSUTCDATETIME] = SYSUTCDATETIME(), 
		[datetime2-converted] = CONVERT(datetime2,SYSDATETIMEOFFSET()),
		[datetimeoffset-converted] = TODATETIMEOFFSET(SYSDATETIME(),DATEPART(TZOFFSET, SYSDATETIMEOFFSET())),
		[datetime2-conversion-valid] = case when CONVERT(datetime2,SYSDATETIMEOFFSET()) = SYSDATETIME() then 'true' else 'false' end,
		[datetimeoffset-conversion-valid] = case when TODATETIMEOFFSET(SYSDATETIME(),DATEPART(TZOFFSET, SYSDATETIMEOFFSET())) = SYSDATETIMEOFFSET() then 'true' else 'false' end,
		[@start_time_utc-to-local] = DATEADD(mi, DATEDIFF(mi, GETUTCDATE(), GETDATE()), @start_time_utc),
		[@start_time-to-utc] = DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), @start_time);
go

use DBA
go

;with t_Services as (
	select *, [uptime_ms] = datediff(MILLISECOND, last_startup_time, SYSDATETIME())
			,[uptime_s] = datediff(SECOND, last_startup_time, SYSDATETIME())
	from sys.dm_server_services
	where servicename like 'SQL Server (%'
)
select [ddd hh:mm:ss.mss] = right('0000'+convert(varchar, uptime_ms/86400000),3)+ ' '+convert(varchar,dateadd(MILLISECOND,uptime_ms,'1900-01-01 00:00:00'),114),
		[uptime] = right('   0'+convert(varchar, [uptime_s]/86400),4)+ ' '+convert(varchar,dateadd(SECOND,[uptime_s],'1900-01-01 00:00:00'),114),
		*
from t_Services
go

/*
Grafana Variables
$__timeFrom()
$__timeTo()

https://grafana.com/docs/grafana/latest/variables/advanced-variable-format-options/


*/
