<#
********** Troubleshoot SQL Server slow performance caused by IO **************
-------------------------------------------------------------------------------
https://learn.microsoft.com/en-us/troubleshoot/sql/database-engine/performance/troubleshoot-sql-io-performance
Threshold latency => 10-15 ms as per document


Script to check disk performance or disk Throughput using tool DiskSpd
This is commandline tool similar to CrystalDiskMark
-------------------------------------------------------------------------
How to Tune as multi-terabyte database
https://www.youtube.com/watch?v=9j51bD0DPZE&ab_channel=GroupBy
https://learn.microsoft.com/en-us/azure/azure-local/manage/diskspd-overview

Parameters
https://github.com/Microsoft/diskspd/wiki/Command-line-and-parameters

Customize Tests
https://github.com/Microsoft/diskspd/wiki/Customizing-tests

Measure Throughput

diskspd (formally sqlio) - Before Test - 64k Reads

cd S:\
diskspd -b64K -d300 -t20 -o20 -Sh -r -w90 -L -Z1G -c20G file1.dat file2.dat file3.dat file4.dat > DiskSpd_result.txt

-d => duration in seconds
-t => Number of threads per target.
-o => Number of outstanding I/O requests per-target per-thread.
-Sh => Disable cache
-r => test random IO. Block aligned
-W => Percent of Write Operation
-L => Measure latency statistics.
-Z => Separate read and write buffers and initialize a per-target write source buffer sized to the specified number of bytes or KiB, MiB, GiB, or blocks.


I/Os => 2755949
MiB/s => 1435
I/O per s => 22966
AvgLat => 13.935
#>
