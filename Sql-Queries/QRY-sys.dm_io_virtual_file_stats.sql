use master
go


--	How to examine IO subsystem latencies from within SQL Server (Disk Latency)
	--	https://www.sqlskills.com/blogs/paul/how-to-examine-io-subsystem-latencies-from-within-sql-server/
	--	https://sqlperformance.com/2015/03/io-subsystem/monitoring-read-write-latency
	--	https://www.brentozar.com/blitz/slow-storage-reads-writes/
SELECT
    [ReadLatency] =
        CASE WHEN [num_of_reads] = 0
            THEN 0 ELSE ([io_stall_read_ms] / [num_of_reads]) END,
    [WriteLatency] =
        CASE WHEN [num_of_writes] = 0
            THEN 0 ELSE ([io_stall_write_ms] / [num_of_writes]) END,
    [Latency] =
        CASE WHEN ([num_of_reads] = 0 AND [num_of_writes] = 0)
            THEN 0 ELSE ([io_stall] / ([num_of_reads] + [num_of_writes])) END,
    [AvgBPerRead] =
        CASE WHEN [num_of_reads] = 0
            THEN 0 ELSE ([num_of_bytes_read] / [num_of_reads]) END,
    [AvgBPerWrite] =
        CASE WHEN [num_of_writes] = 0
            THEN 0 ELSE ([num_of_bytes_written] / [num_of_writes]) END,
    [AvgBPerTransfer] =
        CASE WHEN ([num_of_reads] = 0 AND [num_of_writes] = 0)
            THEN 0 ELSE
                (([num_of_bytes_read] + [num_of_bytes_written]) /
                ([num_of_reads] + [num_of_writes])) END,
    LEFT ([mf].[physical_name], 2) AS [Drive],
    DB_NAME ([vfs].[database_id]) AS [DB],
    [mf].[physical_name]
FROM
    sys.dm_io_virtual_file_stats (NULL,NULL) AS [vfs]
JOIN sys.master_files AS [mf]
    ON [vfs].[database_id] = [mf].[database_id]
    AND [vfs].[file_id] = [mf].[file_id]
-- WHERE [vfs].[file_id] = 2 -- log files
ORDER BY [Latency] DESC
-- ORDER BY [ReadLatency] DESC
--ORDER BY [WriteLatency] DESC;
GO

/*	 Look at pending I/O requests by file	*/
SELECT DB_NAME(mf.database_id) AS [Database] , mf.physical_name ,r.io_pending , r.io_pending_ms_ticks , r.io_type , fs.num_of_reads , fs.num_of_writes
FROM sys.dm_io_pending_io_requests AS r INNER JOIN sys.dm_io_virtual_file_stats(NULL, NULL) AS fs ON r.io_handle = fs.file_handle INNER JOIN sys.master_files AS mf ON fs.database_id = mf.database_id
AND fs.file_id = mf.file_id
ORDER BY r.io_pending , r.io_pending_ms_ticks DESC ;
go

select db_name(vfs.database_id) as dbName, mf.physical_name, mf.name, [size_on_disk_gb] = vfs.size_on_disk_bytes*1.0/1024/1024/1024, vfs.*
FROM
    sys.dm_io_virtual_file_stats (NULL,NULL) AS [vfs]
JOIN sys.master_files AS [mf]
    ON [vfs].[database_id] = [mf].[database_id]
    AND [vfs].[file_id] = [mf].[file_id]
go




DROP TABLE IF EXISTS #Snapshot;
GO

CREATE TABLE #Snapshot
(
    database_id SMALLINT NOT NULL,
    file_id SMALLINT NOT NULL,
    num_of_reads BIGINT NOT NULL,
    num_of_bytes_read BIGINT NOT NULL,
    io_stall_read_ms BIGINT NOT NULL,
    num_of_writes BIGINT NOT NULL,
    num_of_bytes_written BIGINT NOT NULL,
    io_stall_write_ms BIGINT NOT NULL
);

INSERT INTO #Snapshot(database_id,file_id,num_of_reads,num_of_bytes_read
    ,io_stall_read_ms,num_of_writes,num_of_bytes_written,io_stall_write_ms)
    SELECT database_id,file_id,num_of_reads,num_of_bytes_read
        ,io_stall_read_ms,num_of_writes,num_of_bytes_written,io_stall_write_ms
    FROM sys.dm_io_virtual_file_stats(NULL,NULL)
OPTION (RECOMPILE);

-- Set test interval (1 minute). 
WAITFOR DELAY '00:00:10.000';

;WITH Stats(db_id, file_id, Reads, ReadBytes, Writes
    ,WrittenBytes, ReadStall, WriteStall)
as
(
    SELECT
        s.database_id, s.file_id
        ,fs.num_of_reads - s.num_of_reads
        ,fs.num_of_bytes_read - s.num_of_bytes_read
        ,fs.num_of_writes - s.num_of_writes
        ,fs.num_of_bytes_written - s.num_of_bytes_written
        ,fs.io_stall_read_ms - s.io_stall_read_ms
        ,fs.io_stall_write_ms - s.io_stall_write_ms
    FROM
        #Snapshot s JOIN sys.dm_io_virtual_file_stats(NULL, NULL) fs ON
            s.database_id = fs.database_id and s.file_id = fs.file_id
)
SELECT
    s.db_id AS [DB ID], d.name AS [Database]
    ,mf.name AS [File Name], mf.physical_name AS [File Path]
    ,mf.type_desc AS [Type], s.Reads 
    ,CONVERT(DECIMAL(12,3), s.ReadBytes / 1048576.) AS [Read MB]
    ,CONVERT(DECIMAL(12,3), s.WrittenBytes / 1048576.) AS [Written MB]
    ,s.Writes, s.Reads + s.Writes AS [IO Count]
    ,CONVERT(DECIMAL(5,2),100.0 * s.ReadBytes / 
            (s.ReadBytes + s.WrittenBytes)) AS [Read %]
    ,CONVERT(DECIMAL(5,2),100.0 * s.WrittenBytes / 
            (s.ReadBytes + s.WrittenBytes)) AS [Write %]
    ,s.ReadStall AS [Read Stall]
    ,s.WriteStall AS [Write Stall]
    ,CASE WHEN s.Reads = 0 
        THEN 0.000
        ELSE CONVERT(DECIMAL(12,3),1.0 * s.ReadStall / s.Reads) 
    END AS [Avg Read Stall] 
    ,CASE WHEN s.Writes = 0 
        THEN 0.000
        ELSE CONVERT(DECIMAL(12,3),1.0 * s.WriteStall / s.Writes) 
    END AS [Avg Write Stall] 
FROM
    Stats s JOIN sys.master_files mf WITH (NOLOCK) ON
        s.db_id = mf.database_id and
        s.file_id = mf.file_id
    JOIN sys.databases d WITH (NOLOCK) ON 
        s.db_id = d.database_id  
WHERE -- Only display files with more than 2MB throughput
    (s.ReadBytes + s.WrittenBytes) > 2 * 1048576
ORDER BY
    s.db_id, s.file_id
OPTION (RECOMPILE);
go
