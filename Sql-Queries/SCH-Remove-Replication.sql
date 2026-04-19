-- Purpose:
--   Cleanup replication/distribution leftovers only.
--
-- Usage:
--   Run each section on the server noted in the header.
--   Review results before executing destructive statements.

-------------------------------------------------------------------------------
-- [Run on: Experiment]
-------------------------------------------------------------------------------
use [master]
go

if db_id(N'DBATools') is not null exec master.dbo.sp_removedbreplication N'DBATools';
if db_id(N'DBA') is not null exec master.dbo.sp_removedbreplication N'DBA';
exec master.dbo.sp_dropdistributor @no_checks = 1, @ignore_distributor = 1;
go

-------------------------------------------------------------------------------
-- [Run on: DEMO\SQL2019]
-------------------------------------------------------------------------------
use [master]
go

if db_id(N'DBA') is not null exec master.dbo.sp_removedbreplication N'DBA';
if db_id(N'DBATools') is not null exec master.dbo.sp_removedbreplication N'DBATools';
exec master.dbo.sp_dropdistributor @no_checks = 1, @ignore_distributor = 1;
go

-------------------------------------------------------------------------------
-- [Run on: localhost / distributor] Inventory before cleanup.
-------------------------------------------------------------------------------
use [master]
go

set nocount on;
select @@servername as server_name,
       serverproperty('IsDistributor') as is_distributor,
       serverproperty('IsPublisher') as is_publisher,
       serverproperty('IsSubscriber') as is_subscriber;

select name, is_distributor, is_published, is_subscribed, is_merge_published
from sys.databases
order by name;
go

-------------------------------------------------------------------------------
-- [Run on: localhost / distributor] Remove orphaned distpublisher row.
-------------------------------------------------------------------------------
begin tran;
delete from msdb.dbo.MSdistpublishers where name = N'EXPERIMENT';
commit tran;
go

-------------------------------------------------------------------------------
-- [Run on: localhost / distributor] Find blocking sessions on distribution.
-------------------------------------------------------------------------------
select s.session_id,
       s.login_name,
       s.host_name,
       s.program_name,
       db_name(c.database_id) as db_name,
       s.status
from sys.dm_exec_sessions s
join sys.dm_exec_connections c on s.session_id = c.session_id
where c.database_id = db_id(N'distribution');
go

-- Example if distribution drop is blocked:
-- kill 85;
go

-------------------------------------------------------------------------------
-- [Run on: localhost / distributor] Drop distribution DB and distributor.
-------------------------------------------------------------------------------
if db_id(N'distribution') is not null
begin
    alter database [distribution] set single_user with rollback immediate;
    exec master.dbo.sp_dropdistributiondb @database = N'distribution';
end
go

exec master.dbo.sp_dropdistributor @no_checks = 1, @ignore_distributor = 1;
go

-------------------------------------------------------------------------------
-- [Run on: localhost] Remove replication SQL Agent jobs.
-------------------------------------------------------------------------------
declare @job_name sysname;

declare cur_repl_jobs cursor local fast_forward for
    select j.name
    from msdb.dbo.sysjobs j
    join msdb.dbo.syscategories c on j.category_id = c.category_id
    where c.category_class = 1
      and c.name like N'REPL%';

open cur_repl_jobs;
fetch next from cur_repl_jobs into @job_name;
while @@fetch_status = 0
begin
    exec msdb.dbo.sp_delete_job @job_name = @job_name;
    fetch next from cur_repl_jobs into @job_name;
end
close cur_repl_jobs;
deallocate cur_repl_jobs;
go

-------------------------------------------------------------------------------
-- [Run on: localhost] Remove jobs owned by distributor_admin and drop login.
-------------------------------------------------------------------------------
declare @owned_job sysname;

declare cur_owned_jobs cursor local fast_forward for
    select name from msdb.dbo.sysjobs where suser_sname(owner_sid) = N'distributor_admin';

open cur_owned_jobs;
fetch next from cur_owned_jobs into @owned_job;
while @@fetch_status = 0
begin
    exec msdb.dbo.sp_delete_job @job_name = @owned_job;
    fetch next from cur_owned_jobs into @owned_job;
end
close cur_owned_jobs;
deallocate cur_owned_jobs;

if exists (select 1 from sys.server_principals where name = N'distributor_admin')
    drop login [distributor_admin];
go

-------------------------------------------------------------------------------
-- [Run on each host after cleanup] Final verification.
-------------------------------------------------------------------------------
set nocount on;
select @@servername as server_name,
       serverproperty('IsDistributor') as is_distributor,
       serverproperty('IsPublisher') as is_publisher,
       serverproperty('IsSubscriber') as is_subscriber;

select d.name, d.is_distributor, d.is_published, d.is_subscribed, d.is_merge_published
from sys.databases d
where d.is_distributor = 1 or d.is_published = 1 or d.is_subscribed = 1 or d.is_merge_published = 1;

select count(*) as repl_jobs
from msdb.dbo.sysjobs j
join msdb.dbo.syscategories c on j.category_id = c.category_id
where c.category_class = 1 and c.name like N'REPL%';

select count(*) as distributor_admin_owned_jobs
from msdb.dbo.sysjobs
where suser_sname(owner_sid) = N'distributor_admin';
go