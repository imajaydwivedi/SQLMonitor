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

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_avg_disk_wait_ms')
    EXEC ('CREATE PROC dbo.usp_avg_disk_wait_ms AS SELECT ''stub version, to be replaced''')
GO 

ALTER PROCEDURE dbo.usp_avg_disk_wait_ms
	@avg_disk_wait_ms decimal(20,2) = -1.0 output,
	@snapshot_interval_minutes int = 10,
	@consider_other_disk_io_waits bit = 1,
	@consider_tran_log_io_waits bit = 1,
	@verbose tinyint = 0
--WITH RECOMPILE, EXECUTE AS OWNER 
AS 
BEGIN

	/*
		Version:		2024-06-05
		Date:			2024-06-05 - Enhancement#42 - Get [avg_disk_wait_ms]

		declare @avg_disk_wait_ms bigint;
		exec usp_avg_disk_wait_ms @avg_disk_wait_ms = @avg_disk_wait_ms output;
		select [avg_disk_wait_ms] = @avg_disk_wait_ms;
	*/
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET LOCK_TIMEOUT 30000; -- 30 seconds
	
	DECLARE @passed_avg_disk_wait_ms smallint = @avg_disk_wait_ms;

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

	if @verbose >= 1
		print 'Compute delta wait stats..'
	;with wait_snap1 as (
		select	wait_time_ms = sum(convert(bigint,wait_time_ms)), 
				waiting_tasks_count = sum(convert(bigint,waiting_tasks_count))
		from dbo.wait_stats s1
		where s1.collection_time_utc = @collect_time_utc_snap1
		and [wait_type] IN ( select wc.[WaitType] from [dbo].[BlitzFirst_WaitStats_Categories] wc 
								where wc.Ignorable = 0 
								and (	wc.WaitCategory = 'Buffer IO'
									or	( @consider_other_disk_io_waits = 1 and wc.WaitCategory = 'Other Disk IO' )
									or	( @consider_tran_log_io_waits = 1 and wc.WaitCategory = 'Tran Log IO' )
									)
							)
		AND [waiting_tasks_count] > 0
	)
	,wait_snap2 as (
		select	wait_time_ms = sum(convert(bigint,wait_time_ms)), 
				waiting_tasks_count = sum(convert(bigint,waiting_tasks_count))
		from dbo.wait_stats s2
		where s2.collection_time_utc = @collect_time_utc_snap2
		and [wait_type] IN ( select wc.[WaitType] from [dbo].[BlitzFirst_WaitStats_Categories] wc 
								where wc.Ignorable = 0 
								and (	wc.WaitCategory = 'Buffer IO'
									or	( @consider_other_disk_io_waits = 1 and wc.WaitCategory = 'Other Disk IO' )
									or	( @consider_tran_log_io_waits = 1 and wc.WaitCategory = 'Tran Log IO' )
									)
							)
		AND [waiting_tasks_count] > 0
	)
	select	@avg_disk_wait_ms = (s2.wait_time_ms - s1.wait_time_ms) / (s2.waiting_tasks_count - s1.waiting_tasks_count)
	from wait_snap1 s1, wait_snap2 s2;

	SELECT [avg_disk_wait_ms] = @avg_disk_wait_ms;
END
GO

IF APP_NAME() = 'Microsoft SQL Server Management Studio - Query'
BEGIN
	--declare @avg_disk_wait_ms decimal(20,2);
	exec usp_avg_disk_wait_ms @verbose = 0 --@avg_disk_wait_ms = @avg_disk_wait_ms output;
	exec usp_avg_disk_wait_ms @consider_other_disk_io_waits = 0, @consider_tran_log_io_waits = 0
	exec usp_avg_disk_wait_ms @snapshot_interval_minutes = 25
	--select [waits_seconds__per_core_per_minute] = @avg_disk_wait_ms;
END
go