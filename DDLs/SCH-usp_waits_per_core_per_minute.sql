IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
SET ARITHABORT ON;
GO

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_waits_per_core_per_minute')
    EXEC ('CREATE PROC dbo.usp_waits_per_core_per_minute AS SELECT ''stub version, to be replaced''')
GO

ALTER PROCEDURE dbo.usp_waits_per_core_per_minute
	@waits_seconds__per_core_per_minute decimal(20,2) = -1.0 output,
	@snapshot_interval_minutes int = 5,
	@verbose tinyint = 0
--WITH RECOMPILE, EXECUTE AS OWNER 
AS 
BEGIN

	/*
		Version:		1.6.4
		Modifications:	2022-11-26 - Initial Draft
						2023-08-29 - Fix Divide by Zero Error
						2023-12-30 - #21 - Add exception for some waits through Wait Stats table

		declare @waits_seconds__per_core_per_minute bigint;
		exec usp_waits_per_core_per_minute @waits_seconds__per_core_per_minute = @waits_seconds__per_core_per_minute output;
		select [waits_seconds__per_core_per_minute] = @waits_seconds__per_core_per_minute;
	*/
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET LOCK_TIMEOUT 30000; -- 30 seconds
	
	DECLARE @passed_waits_seconds__per_core_per_minute smallint = @waits_seconds__per_core_per_minute;

	declare @schedulers smallint;
	select @schedulers = count(*) from sys.dm_os_schedulers where status = 'VISIBLE ONLINE' and is_online = 1;
	if @verbose >= 1
		print '@schedulers = '+convert(varchar,@schedulers);

	declare @collect_time_utc_snap1 datetime2;
	declare @collect_time_utc_snap2 datetime2;

	select top 1 @collect_time_utc_snap2 = collection_time_utc
	from dbo.wait_stats s
	order by collection_time_utc desc;

	select top 1 @collect_time_utc_snap1 = collection_time_utc
	from dbo.wait_stats s where collection_time_utc < dateadd(minute,-@snapshot_interval_minutes,@collect_time_utc_snap2) -- 2 snapshots with a gap
	order by collection_time_utc desc;

	if @verbose >= 1
	begin
		print '@collect_time_utc_snap1 = '+convert(varchar,@collect_time_utc_snap1,121);
		print '@collect_time_utc_snap2 = '+convert(varchar,@collect_time_utc_snap2,121);
	end

	--select @collect_time_utc_snap1, @collect_time_utc_snap2;

	if @verbose >= 1
		print 'Compute delta wait stats..'
	;with wait_snap1 as (
		select sum(wait_time_ms)/1000 as wait_time_s
		from dbo.wait_stats s1
		where s1.collection_time_utc = @collect_time_utc_snap1
		and [wait_type] NOT IN ( select wc.[WaitType] from [dbo].[BlitzFirst_WaitStats_Categories] wc where coalesce(wc.IgnorableOnPerCoreMetric,wc.Ignorable,0) = 1 )
		AND [waiting_tasks_count] > 0
	)
	,wait_snap2 as (
		select sum(wait_time_ms)/1000 as wait_time_s
		from dbo.wait_stats s2
		where s2.collection_time_utc = @collect_time_utc_snap2
		and [wait_type] NOT IN ( select wc.[WaitType] from [dbo].[BlitzFirst_WaitStats_Categories] wc where coalesce(wc.IgnorableOnPerCoreMetric,wc.Ignorable,0) = 1 )
		AND [waiting_tasks_count] > 0
	)
	select @waits_seconds__per_core_per_minute = CEILING(
				case when datediff(minute,@collect_time_utc_snap1,@collect_time_utc_snap2) = 0
					 then 0
					 else convert(numeric(20,2), (s2.wait_time_s - s1.wait_time_s)*1.0 / @schedulers / datediff(minute,@collect_time_utc_snap1,@collect_time_utc_snap2))
					 end)
	from wait_snap1 s1, wait_snap2 s2;

	--IF @passed_waits_seconds__per_core_per_minute = -1.0
	SELECT [waits_seconds__per_core_per_minute] = @waits_seconds__per_core_per_minute;
END
GO

IF APP_NAME() = 'Microsoft SQL Server Management Studio - Query'
BEGIN
	--declare @waits_seconds__per_core_per_minute decimal(20,2);
	exec usp_waits_per_core_per_minute @verbose = 0 --@waits_seconds__per_core_per_minute = @waits_seconds__per_core_per_minute output;
	--select [waits_seconds__per_core_per_minute] = @waits_seconds__per_core_per_minute;
END
go