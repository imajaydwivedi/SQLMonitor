/*
How to Tune as multi-terabyte database
https://www.youtube.com/watch?v=9j51bD0DPZE&ab_channel=GroupBy
https://learn.microsoft.com/en-us/azure/azure-local/manage/diskspd-overview

Measure Throughput

diskspd (formally sqlio) - Before Test - 64k Reads

diskspd -b64K -d300 -o32 -t10 -h -r -w0 -L -Z1G -c20G L:\test.dat

I/Os => 2755949
MiB/s => 1435
I/O per s => 22966
AvgLat => 13.935
*/

