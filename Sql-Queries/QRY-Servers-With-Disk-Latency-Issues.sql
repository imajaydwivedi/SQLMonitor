

declare @sql nvarchar(max);
declare @params nvarchar(max);
declare @server_status varchar(50);
declare @is_decommissioned bit;
declare @host varchar(255);
declare @server varchar(125);

set @server = case when '' <> '' then '' else null end;
set @host = case when '' <> '' then '' else null end;
set @server_status = 'Online';
set @is_decommissioned = case when @server_status = 'Online' then 0
                              when @server_status = 'Offline' then 1
                              when @server_status = 'All' then null
                              else null
                              end

set @params = N'@server varchar(255)';

set quoted_identifier off;
set @sql = "
/* DBA Inventory */
select srv_name, box_ram_gb, max_server_memory_mb, sql_ram_gb, avg_disk_latency_ms, avg_disk_latency_ms_pntile
from dbo.lama_computed_metrics lcm
where 1=1
"+(case when @server is not null then '' else '--' end)+"and lcm.srv_name = @server
order by avg_disk_latency_ms_pntile desc
";
set quoted_identifier off;

exec dbo.sp_executesql @sql, @params, @server;