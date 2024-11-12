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

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_avg_disk_latency_ms')
    EXEC ('CREATE PROC dbo.usp_avg_disk_latency_ms AS SELECT ''stub version, to be replaced''')
GO 

ALTER PROCEDURE dbo.usp_avg_disk_latency_ms
	@avg_disk_latency_ms int = -1.0 output,
	@snapshot_interval_minutes int = 15,
	@type varchar(20) = 'read_write', /* read, write, read_write */
	@verbose tinyint = 0
--WITH RECOMPILE, EXECUTE AS OWNER 
AS 
BEGIN

	/*
		Version:		2024-10-22
		Date:			2024-10-22 - Enhancement#10 - Required for alerting

		declare @avg_disk_latency_ms bigint;
		exec usp_avg_disk_latency_ms @avg_disk_latency_ms = @avg_disk_latency_ms output;
		select [avg_disk_latency_ms] = @avg_disk_latency_ms;
	*/
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET LOCK_TIMEOUT 30000; -- 30 seconds
	
	DECLARE @passed_avg_disk_latency_ms smallint = @avg_disk_latency_ms;

	declare @collect_time_utc_snap1 datetime2;
	declare @collect_time_utc_snap2 datetime2;

	select top 1 @collect_time_utc_snap2 = collection_time_utc
	from dbo.file_io_stats s
	order by collection_time_utc desc;

	select top 1 @collect_time_utc_snap1 = collection_time_utc
	from dbo.file_io_stats s where collection_time_utc <= dateadd(minute,-@snapshot_interval_minutes,@collect_time_utc_snap2) -- 2 snapshots with a gap
	order by collection_time_utc desc;

	if @verbose >= 1
	begin
		print '@collect_time_utc_snap1 = '+convert(varchar,@collect_time_utc_snap1,121);
		print '@collect_time_utc_snap2 = '+convert(varchar,@collect_time_utc_snap2,121);
	end

	if @verbose >= 1
		print 'Compute delta file io stats..'
	;with iostats_snap1 as (
		select	sample_ms = max(sample_ms),
				io_stall_read_ms = sum(io_stall_read_ms),
				num_of_reads = sum(num_of_reads),
				io_stall_write_ms = sum(io_stall_write_ms),
				num_of_writes = sum(num_of_writes),
				io_stall = SUM(io_stall)
		from dbo.file_io_stats s1
		where s1.collection_time_utc = @collect_time_utc_snap1
		AND (num_of_reads > 0 or num_of_writes > 0)
	)
	,iostats_snap2 as (
		select	sample_ms = max(sample_ms),
				io_stall_read_ms = sum(io_stall_read_ms),
				num_of_reads = sum(num_of_reads),
				io_stall_write_ms = sum(io_stall_write_ms),
				num_of_writes = sum(num_of_writes),
				io_stall = SUM(io_stall)
		from dbo.file_io_stats s2
		where s2.collection_time_utc = @collect_time_utc_snap2
		AND (num_of_reads > 0 or num_of_writes > 0)
	)
	select @avg_disk_latency_ms = case when (s2.num_of_reads+s2.num_of_writes) > (s1.num_of_reads+s1.num_of_writes)
										then (s2.io_stall-s1.io_stall) / ((s2.num_of_reads+s2.num_of_writes) - (s1.num_of_reads+s1.num_of_writes))
										else 0
										end
	from iostats_snap1 s1, iostats_snap2 s2;

	SELECT [avg_disk_latency_ms] = isnull(@avg_disk_latency_ms,0);
END
GO

IF APP_NAME() = 'Microsoft SQL Server Management Studio - Query'
BEGIN
	declare @avg_disk_latency_ms int;
	exec usp_avg_disk_latency_ms @avg_disk_latency_ms = @avg_disk_latency_ms output;
	select [@avg_disk_latency_ms] = @avg_disk_latency_ms;
END
go