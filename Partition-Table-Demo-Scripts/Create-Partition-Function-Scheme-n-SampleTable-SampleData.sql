use tempdb
go

/* ****** 1) Partition function for [datetime2] & [datetime] ******* */
--drop partition function pf_dba_datetime2_hourly
if not exists (select * from sys.partition_functions where name = 'pf_dba_datetime2_hourly') 
	exec ('create partition function pf_dba_datetime2_hourly (datetime2) as range right for values (convert(smalldatetime,cast(getdate() as date)))')
go
--drop partition function pf_dba_datetime2_daily
if not exists (select * from sys.partition_functions where name = 'pf_dba_datetime2_daily') 
	exec ('create partition function pf_dba_datetime2_daily (datetime2) as range right for values (convert(smalldatetime,cast(getdate() as date)))')
go

create partition function pf_dba_datetime2_daily (datetime2) as range right for values ('2023-12-19 00:00:00');
go

--drop partition function pf_dba_datetime2_monthly
if not exists (select * from sys.partition_functions where name = 'pf_dba_datetime2_monthly') 
	exec ('create partition function pf_dba_datetime2_monthly (datetime2) as range right for values (convert(smalldatetime,cast(getdate() as date)))')
go
--drop partition function pf_dba_datetime2_quarterly
if not exists (select * from sys.partition_functions where name = 'pf_dba_datetime2_quarterly') 
	exec ('create partition function pf_dba_datetime2_quarterly (datetime2) as range right for values (convert(smalldatetime,cast(getdate() as date)))')
go
--drop partition function pf_dba_datetime_hourly
declare @is_partitioned bit = 1;
if not exists (select * from sys.partition_functions where name = 'pf_dba_datetime_hourly') 
	exec ('create partition function pf_dba_datetime_hourly (datetime) as range right for values (convert(smalldatetime,cast(getdate() as date)))')
go
--drop partition function pf_dba_datetime_daily
if not exists (select * from sys.partition_functions where name = 'pf_dba_datetime_daily') 
	exec ('create partition function pf_dba_datetime_daily (datetime) as range right for values (convert(smalldatetime,cast(getdate() as date)))')
go
--drop partition function pf_dba_datetime_monthly
if not exists (select * from sys.partition_functions where name = 'pf_dba_datetime_monthly') 
	exec ('create partition function pf_dba_datetime_monthly (datetime) as range right for values (convert(smalldatetime,cast(getdate() as date)))')
go
--drop partition function pf_dba_datetime_quarterly
if not exists (select * from sys.partition_functions where name = 'pf_dba_datetime_quarterly') 
	exec ('create partition function pf_dba_datetime_quarterly (datetime) as range right for values (convert(smalldatetime,cast(getdate() as date)))')
go

/* ****** 2) Partition Scheme for [datetime2] & [datetime] ******* */
--drop partition scheme ps_dba_datetime2_hourly
if not exists (select * from sys.partition_schemes where name = 'ps_dba_datetime2_hourly') 
	exec ('create partition scheme ps_dba_datetime2_hourly as partition pf_dba_datetime2_hourly all to ([PRIMARY])')
go
--drop partition scheme ps_dba_datetime2_daily
if not exists (select * from sys.partition_schemes where name = 'ps_dba_datetime2_daily') 
	exec ('create partition scheme ps_dba_datetime2_daily as partition pf_dba_datetime2_daily all to ([PRIMARY])')
go
--drop partition scheme ps_dba_datetime2_monthly
if not exists (select * from sys.partition_schemes where name = 'ps_dba_datetime2_monthly') 
	exec ('create partition scheme ps_dba_datetime2_monthly as partition pf_dba_datetime2_monthly all to ([PRIMARY])')
go
--drop partition scheme ps_dba_datetime2_quarterly
if not exists (select * from sys.partition_schemes where name = 'ps_dba_datetime2_quarterly') 
	exec ('create partition scheme ps_dba_datetime2_quarterly as partition pf_dba_datetime2_quarterly all to ([PRIMARY])')
go
--drop partition scheme ps_dba_datetime_hourly
if not exists (select * from sys.partition_schemes where name = 'ps_dba_datetime_hourly') 
	exec ('create partition scheme ps_dba_datetime_hourly as partition pf_dba_datetime_hourly all to ([PRIMARY])')
go
--drop partition scheme ps_dba_datetime_daily
if not exists (select * from sys.partition_schemes where name = 'ps_dba_datetime_daily') 
	exec ('create partition scheme ps_dba_datetime_daily as partition pf_dba_datetime_daily all to ([PRIMARY])')
go
--drop partition scheme ps_dba_datetime_monthly
if not exists (select * from sys.partition_schemes where name = 'ps_dba_datetime_monthly') 
	exec ('create partition scheme ps_dba_datetime_monthly as partition pf_dba_datetime_monthly all to ([PRIMARY])')
go
--drop partition scheme ps_dba_datetime_quarterly
if not exists (select * from sys.partition_schemes where name = 'ps_dba_datetime_quarterly') 
	exec ('create partition scheme ps_dba_datetime_quarterly as partition pf_dba_datetime_quarterly all to ([PRIMARY])')
go

create table [dbo].[performance_counters]
(
	[collection_time_utc] [datetime2](7) NOT NULL,
	[host_name] [varchar](255) NOT NULL,
	--[path] [nvarchar](2000) NOT NULL,
	[object] [varchar](255) NOT NULL,
	[counter] [varchar](255) NOT NULL,
	[value] numeric(38,10) NULL,
	[instance] [varchar](255) NULL

	--,index ci_performance_counters clustered (collection_time_utc) on ps_dba_datetime2_daily ([collection_time_utc])
) on ps_dba_datetime2_daily ([collection_time_utc])
go

-- Boundaries

partition x in "Table A" (Source Paritition) -> partition y in "Table B" (Target Partition)

Table A => '2023-12-18' -> 230,231
	Method 01 => Truncate data from table for only (230, 231) -> SQL 2016+

	RMSTrade
	--------
	Method 02 => Switch out partitions (230, 231) "Table A" -> into a new table "Table B"
	Step 02 => Copy data from "Table B" into RMSTrade_History database using SSIS 
	Step 03 => Make RMSTrade_History READONLY 
		=> Backup this database once a year

All the indexes should be partition align
	=> Parition TableA [CX]
	=> Don't partition other indexes





--select * from dbo.TableA where TradeDT = '2023-12-18'


-- Add sample data for current month
insert into dbo.performance_counters
(collection_time_utc, host_name, object, counter, value, instance)
select collection_time_utc, host_name, object, counter, value, instance
from DBA.dbo.performance_counters pc
where pc.collection_time_utc between dateadd(hour,-3,getutcdate()) and getutcdate()
--(396752 rows affected)
go

-- Add sample data for last to last month
insert into dbo.performance_counters
(collection_time_utc, host_name, object, counter, value, instance)
select collection_time_utc = dateadd(month,-2,collection_time_utc), host_name, object, counter, value, instance
from DBA.dbo.performance_counters pc
where pc.collection_time_utc between dateadd(hour,-6,getutcdate()) and dateadd(hour,-3,getutcdate())
--(398944 rows affected)
go

-- Add sample data for last year
insert into dbo.performance_counters
(collection_time_utc, host_name, object, counter, value, instance)
select collection_time_utc = dateadd(YEAR,-1,collection_time_utc), host_name, object, counter, value, instance
from DBA.dbo.performance_counters pc
where pc.collection_time_utc between dateadd(hour,-9,getutcdate()) and dateadd(hour,-6,getutcdate())
--(397848 rows affected)
go
