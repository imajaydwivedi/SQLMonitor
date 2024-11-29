/*
	Version -> 2024-08-10
	2024-08-10 = #35 - Add Debugging parameter
	2024-04-26 - #38 - Add Infra to Track AG State Change
	2023-12-30 - #21 - Add exception for some waits through Wait Stats table
	-----------------

	https://www.sommarskog.se/grantperm.html

	*** Self Pre Steps ***
	----------------------
	1) Create a public & default mail profile. https://github.com/imajaydwivedi/SQLDBA-SSMS-Solution/../SQLDBATools-Inventory/DatabaseMail_Using_GMail.sql
	2) Create sp_WhoIsActive in [master] database. https://github.com/imajaydwivedi/SQLDBA-SSMS-Solution/../BlitzQueries/SCH-sp_WhoIsActive_v12_00(Modified).sql
	3) Create sp_WhatIsRunning in [DBA] database. 
			DDLs\SCH-sp_WhatIsRunning.sql
	4) Install Brent Ozar's First Responder Kit. https://raw.githubusercontent.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/dev/Install-All-Scripts.sql
			Install-DbaFirstResponderKit -SqlInstance workstation -Force -Verbose
	5) Install PowerShell modules
		Update-Module -Force -ErrorAction Continue -Verbose
		Update-Help -Force -ErrorAction Continue -Verbose
		Install-Module dbatools, enhancedhtml2, sqlserver, poshrsjob -Scope AllUsers -Force -ErrorAction Continue -Verbose

	*** Steps in this Script ****
	-----------------------------
	1) Create Partition function for [datetime2], [datetime] & [bigint]
	2) Create Partition Scheme for [datetime2], [datetime] & [bigint]
	3) Create table dbo.purge_table
	4) Create table dbo.instance_hosts
	5) Create table dbo.instance_details
	6) Create table [dbo].[performance_counters] using Partition scheme
	7) Create View [dbo].[vw_performance_counters] for Multi SqlCluster on same nodes Architecture
	8) Create dbo.perfmon_files table using Partition scheme
	9) Create table [dbo].[os_task_list] using Partition scheme
	10) Create View [dbo].[vw_os_task_list] for Multi SqlCluster on same nodes Architecture
	11) Create table  [dbo].[wait_stats] using Partition scheme
	12) Create table  [dbo].[BlitzFirst_WaitStats_Categories]
	13) Create view  [dbo].[vw_wait_stats]
	14) Create table [dbo].[file_io_stats]
	15) Create required schemas
	16) Create procedure dbo.usp_extended_results
	17) Create table [dbo].[xevent_metrics]
	18) Create table [dbo].[xevent_metrics_queries]
	19) Create view  [dbo].[vw_xevent_metrics]
	20) Create Trigger [tgr_insert_xevent_metrics]
	21) Create table [dbo].[xevent_metrics_Processed_XEL_Files]
	22) Create table [dbo].[disk_space] using Partition scheme
	23) Create View [dbo].[vw_disk_space] for Multi SqlCluster on same nodes Architecture
	24) Create view  [dbo].[vw_file_io_stats_deltas]
	25) Create table [dbo].[memory_clerks]
	26) Create table [dbo].[server_privileged_info]
	27) Create table [dbo].[ag_health_state] using Partition scheme
	28) Create table [dbo].[alert_categories]
	29) Create table [dbo].[alert_history]
	30) Add boundaries to partition. 1 boundary per hour
	31) Remove boundaries with retention of 3 months
	32) Populate [dbo].[BlitzFirst_WaitStats_Categories]
*/

IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

/* ****** 1) Create Partition function for [datetime2], [datetime] & [bigint] ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '1) Create Partition function for [datetime2], [datetime] & [bigint]';

--drop partition function pf_dba_datetime2_hourly
declare @is_partitioned bit = 1;
if not exists (select * from sys.partition_functions where name = 'pf_dba_datetime2_hourly') and @is_partitioned = 1
	exec ('create partition function pf_dba_datetime2_hourly (datetime2) as range right for values (convert(smalldatetime,cast(getdate() as date)))')
go
--drop partition function pf_dba_datetime2_daily
declare @is_partitioned bit = 1;
if not exists (select * from sys.partition_functions where name = 'pf_dba_datetime2_daily') and @is_partitioned = 1
	exec ('create partition function pf_dba_datetime2_daily (datetime2) as range right for values (convert(smalldatetime,cast(getdate() as date)))')
go
--drop partition function pf_dba_datetime2_monthly
declare @is_partitioned bit = 1;
if not exists (select * from sys.partition_functions where name = 'pf_dba_datetime2_monthly') and @is_partitioned = 1
	exec ('create partition function pf_dba_datetime2_monthly (datetime2) as range right for values (convert(smalldatetime,cast(getdate() as date)))')
go
--drop partition function pf_dba_datetime2_quarterly
declare @is_partitioned bit = 1;
if not exists (select * from sys.partition_functions where name = 'pf_dba_datetime2_quarterly') and @is_partitioned = 1
	exec ('create partition function pf_dba_datetime2_quarterly (datetime2) as range right for values (convert(smalldatetime,cast(getdate() as date)))')
go
--drop partition function pf_dba_datetime_hourly
declare @is_partitioned bit = 1;
if not exists (select * from sys.partition_functions where name = 'pf_dba_datetime_hourly') and @is_partitioned = 1
	exec ('create partition function pf_dba_datetime_hourly (datetime) as range right for values (convert(smalldatetime,cast(getdate() as date)))')
go
--drop partition function pf_dba_datetime_daily
declare @is_partitioned bit = 1;
if not exists (select * from sys.partition_functions where name = 'pf_dba_datetime_daily') and @is_partitioned = 1
	exec ('create partition function pf_dba_datetime_daily (datetime) as range right for values (convert(smalldatetime,cast(getdate() as date)))')
go
--drop partition function pf_dba_datetime_monthly
declare @is_partitioned bit = 1;
if not exists (select * from sys.partition_functions where name = 'pf_dba_datetime_monthly') and @is_partitioned = 1
	exec ('create partition function pf_dba_datetime_monthly (datetime) as range right for values (convert(smalldatetime,cast(getdate() as date)))')
go
--drop partition function pf_dba_datetime_quarterly
declare @is_partitioned bit = 1;
if not exists (select * from sys.partition_functions where name = 'pf_dba_datetime_quarterly') and @is_partitioned = 1
	exec ('create partition function pf_dba_datetime_quarterly (datetime) as range right for values (convert(smalldatetime,cast(getdate() as date)))')
go
--drop partition function pf_dba_bigint_10part
declare @is_partitioned bit = 1;
if not exists (select * from sys.partition_functions where name = 'pf_dba_bigint_10part') and @is_partitioned = 1
	exec ('create partition function pf_dba_bigint_10part (bigint) as range left for values (0,1,2,3,4,5,6,7,8,9)')
go

/* ****** 2) Create Partition Scheme for [datetime2], [datetime] & [bigint] ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '2) Create Partition Scheme for [datetime2], [datetime] & [bigint]';

--drop partition scheme ps_dba_datetime2_hourly
declare @is_partitioned bit = 1;
if not exists (select * from sys.partition_schemes where name = 'ps_dba_datetime2_hourly') and @is_partitioned = 1
	exec ('create partition scheme ps_dba_datetime2_hourly as partition pf_dba_datetime2_hourly all to ([PRIMARY])')
go
--drop partition scheme ps_dba_datetime2_daily
declare @is_partitioned bit = 1;
if not exists (select * from sys.partition_schemes where name = 'ps_dba_datetime2_daily') and @is_partitioned = 1
	exec ('create partition scheme ps_dba_datetime2_daily as partition pf_dba_datetime2_daily all to ([PRIMARY])')
go
--drop partition scheme ps_dba_datetime2_monthly
declare @is_partitioned bit = 1;
if not exists (select * from sys.partition_schemes where name = 'ps_dba_datetime2_monthly') and @is_partitioned = 1
	exec ('create partition scheme ps_dba_datetime2_monthly as partition pf_dba_datetime2_monthly all to ([PRIMARY])')
go
--drop partition scheme ps_dba_datetime2_quarterly
declare @is_partitioned bit = 1;
if not exists (select * from sys.partition_schemes where name = 'ps_dba_datetime2_quarterly') and @is_partitioned = 1
	exec ('create partition scheme ps_dba_datetime2_quarterly as partition pf_dba_datetime2_quarterly all to ([PRIMARY])')
go
--drop partition scheme ps_dba_datetime_hourly
declare @is_partitioned bit = 1;
if not exists (select * from sys.partition_schemes where name = 'ps_dba_datetime_hourly') and @is_partitioned = 1
	exec ('create partition scheme ps_dba_datetime_hourly as partition pf_dba_datetime_hourly all to ([PRIMARY])')
go
--drop partition scheme ps_dba_datetime_daily
declare @is_partitioned bit = 1;
if not exists (select * from sys.partition_schemes where name = 'ps_dba_datetime_daily') and @is_partitioned = 1
	exec ('create partition scheme ps_dba_datetime_daily as partition pf_dba_datetime_daily all to ([PRIMARY])')
go
--drop partition scheme ps_dba_datetime_monthly
declare @is_partitioned bit = 1;
if not exists (select * from sys.partition_schemes where name = 'ps_dba_datetime_monthly') and @is_partitioned = 1
	exec ('create partition scheme ps_dba_datetime_monthly as partition pf_dba_datetime_monthly all to ([PRIMARY])')
go
--drop partition scheme ps_dba_datetime_quarterly
declare @is_partitioned bit = 1;
if not exists (select * from sys.partition_schemes where name = 'ps_dba_datetime_quarterly') and @is_partitioned = 1
	exec ('create partition scheme ps_dba_datetime_quarterly as partition pf_dba_datetime_quarterly all to ([PRIMARY])')
go
--drop partition scheme ps_dba_bigint_10part
declare @is_partitioned bit = 1;
if not exists (select * from sys.partition_schemes where name = 'ps_dba_bigint_10part') and @is_partitioned = 1
	exec ('create partition scheme ps_dba_bigint_10part as partition pf_dba_bigint_10part all to ([PRIMARY])')
go



/* ***** 3) Create table dbo.purge_table ***************************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '3) Create table dbo.purge_table';

-- drop table dbo.purge_table;
if object_id('dbo.purge_table') is null
begin
	create table dbo.purge_table
	(
		table_name sysname not null,
		date_key sysname not null,
		retention_days smallint not null default 15,
		purge_row_size int not null default 100000,
		created_by sysname not null default suser_name(),
		created_date datetime2 not null default sysdatetime(),
		reference varchar(255) null,
		latest_purge_datetime datetime2 null,
		constraint pk_purge_table primary key (table_name)
	);
end
go

if not exists (select * from sys.indexes where [object_id] = OBJECT_ID('[dbo].[purge_table]') and type_desc = 'CLUSTERED')
begin
	alter table [dbo].[purge_table] add constraint pk_purge_table primary key ([table_name])
end
go

if not exists (select 1 from dbo.purge_table where table_name = 'dbo.BlitzIndex')
begin
	insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.BlitzIndex', 
			date_key = 'run_datetime', 
			retention_days = 180, 
			purge_row_size = 100000,
			reference = 'SQLMonitor Data Collection'
end
go

if not exists (select 1 from dbo.purge_table where table_name = 'dbo.BlitzIndex_Mode0')
begin
	insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.BlitzIndex_Mode0', 
			date_key = 'run_datetime', 
			retention_days = 365, 
			purge_row_size = 100000,
			reference = 'SQLMonitor Data Collection'
end
go

if not exists (select 1 from dbo.purge_table where table_name = 'dbo.BlitzIndex_Mode1')
begin
	insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.BlitzIndex_Mode1', 
			date_key = 'run_datetime', 
			retention_days = 365, 
			purge_row_size = 100000,
			reference = 'SQLMonitor Data Collection'
end
go

if not exists (select 1 from dbo.purge_table where table_name = 'dbo.BlitzIndex_Mode4')
begin
	insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.BlitzIndex_Mode4', 
			date_key = 'run_datetime', 
			retention_days = 180, 
			purge_row_size = 100000,
			reference = 'SQLMonitor Data Collection'
end
go

if not exists (select 1 from dbo.purge_table where table_name = 'dbo.Blitz')
begin
	insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.Blitz', 
			date_key = 'CheckDate', 
			retention_days = 365,
			purge_row_size = 100000,
			reference = 'SQLMonitor Data Collection'
end
go



/* ***** 4) Create table dbo.instance_hosts ***************************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '4) Create table dbo.instance_hosts';

-- drop table dbo.instance_hosts;
if object_id('dbo.instance_hosts') is null
begin
	create table dbo.instance_hosts
	(
		[host_name] varchar(255) not null,
		constraint pk_instance_hosts primary key clustered ([host_name])
	)
end
go


if ( (APP_NAME() = 'Microsoft SQL Server Management Studio - Query') and (not exists (select * from dbo.instance_hosts where host_name = CONVERT(varchar,SERVERPROPERTY('ComputerNamePhysicalNetBIOS')))) )
begin
	insert dbo.instance_hosts 
	select [host_name] = CONVERT(varchar,SERVERPROPERTY('ComputerNamePhysicalNetBIOS'));
end
go


/* ***** 5) Create table dbo.instance_details ***************************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '5) Create table dbo.instance_details';

-- drop table dbo.instance_details;
if object_id('dbo.instance_details') is null
begin
	create table dbo.instance_details
	(
		[sql_instance] varchar(255) not null,
		[sql_instance_port] varchar(10) null,
		[is_alias] bit default 0 not null,
		[source_sql_instance] varchar(255) null,
		[host_name] varchar(255) not null,
		[database] varchar(255) not null,
		[collector_tsql_jobs_server] varchar(255) null default convert(varchar,serverproperty('MachineName')),
		[collector_powershell_jobs_server] varchar(255) null default convert(varchar,serverproperty('MachineName')),
		[data_destination_sql_instance] varchar(255) null default convert(varchar,serverproperty('MachineName')),
		[dba_group_mail_id] varchar(2000) not null default 'dba_team@gmail.com',
		[sqlmonitor_script_path] varchar(2000) not null default 'C:\SQLMonitor',
		[sqlmonitor_version] varchar(20) not null default '1.1.0',		

		constraint pk_instance_details primary key clustered ([sql_instance], [host_name]), 
		constraint fk_host_name foreign key ([host_name]) references dbo.instance_hosts ([host_name])
	)
end
go

if ( (APP_NAME() = 'Microsoft SQL Server Management Studio - Query') and (not exists (select * from dbo.instance_details where sql_instance = convert(varchar,serverproperty('MachineName')))) )
begin
	insert dbo.instance_details 
		(	[sql_instance], [host_name], [database], [collector_tsql_jobs_server], 
			[collector_powershell_jobs_server], [data_destination_sql_instance],
			[dba_group_mail_id], [sqlmonitor_script_path]
		)
	select	[sql_instance] = convert(varchar,serverproperty('MachineName')),
			--[ip] = convert(varchar,CONNECTIONPROPERTY('local_net_address')),
			[host_name] = CONVERT(varchar,SERVERPROPERTY('ComputerNamePhysicalNetBIOS')),
			[database] = DB_NAME(),
			--[service_name] = case when @@servicename = 'MSSQLSERVER' then @@servicename else 'MSSQL$'+@@servicename end,
			[collector_tsql_jobs_server] = convert(varchar,serverproperty('MachineName')),
			--[collector_tsql_jobs_server] = convert(varchar,CONNECTIONPROPERTY('local_net_address')),
			[collector_powershell_jobs_server] = convert(varchar,serverproperty('MachineName')),
			--[collector_powershell_jobs_server] = convert(varchar,CONNECTIONPROPERTY('local_net_address')),
			[data_destination_sql_instance] = convert(varchar,serverproperty('MachineName')),
			--[data_destination_sql_instance] = convert(varchar,CONNECTIONPROPERTY('local_net_address')),
			[dba_group_mail_id] = 'dba_team@gmail.com',
			[sqlmonitor_script_path] = 'C:\SQLMonitor'
end
go


/* ***** 6) Create table [dbo].[performance_counters] using Partition scheme ***************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '6) Create table [dbo].[performance_counters] using Partition scheme';

-- drop table [dbo].[performance_counters]
if object_id('[dbo].[performance_counters]') is null
begin
	create table [dbo].[performance_counters]
	(
		[collection_time_utc] [datetime2](7) NOT NULL,
		[host_name] [varchar](255) NOT NULL,
		--[path] [nvarchar](2000) NOT NULL,
		[object] [varchar](255) NOT NULL,
		[counter] [varchar](255) NOT NULL,
		[value] numeric(38,10) NULL,
		[instance] [varchar](255) NULL
	) on ps_dba_datetime2_hourly ([collection_time_utc])
end
go

if not exists (select * from sys.indexes where [object_id] = OBJECT_ID('[dbo].[performance_counters]') and name = 'ci_performance_counters')
begin
	create clustered index ci_performance_counters on [dbo].[performance_counters] 
	([collection_time_utc], [host_name]) on ps_dba_datetime2_hourly ([collection_time_utc])
end
go
if not exists (select * from sys.indexes where [object_id] = OBJECT_ID('[dbo].[performance_counters]') and name = 'nci_counter_collection_time_utc')
begin
	create nonclustered index nci_counter_collection_time_utc
	on [dbo].[performance_counters] ([counter],[collection_time_utc]) on ps_dba_datetime2_hourly ([collection_time_utc])
end
GO

if not exists (select 1 from dbo.purge_table where table_name = 'dbo.performance_counters')
begin
	insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.performance_counters', 
			date_key = 'collection_time_utc', 
			retention_days = 15, 
			purge_row_size = 100000,
			reference = 'SQLMonitor Data Collection'
end
go


/* ***** 7) Create View [dbo].[vw_performance_counters] for Multi SqlCluster on same nodes Architecture */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '7) Create View [dbo].[vw_performance_counters] for Multi SqlCluster on same nodes Architecture';

-- drop view dbo.vw_performance_counters
if OBJECT_ID('dbo.vw_performance_counters') is null
	exec ('create view dbo.vw_performance_counters as select 1 as dummy;');
go

declare @recreate_multi_server_views bit = 1;
declare @sql nvarchar(max);
if @recreate_multi_server_views = 1
begin
	set quoted_identifier off;
	set @sql = "alter view dbo.vw_performance_counters
--with schemabinding
as
with cte_counters_local as (select collection_time_utc, host_name, object, counter, value, instance from dbo.performance_counters)
--,cte_counters_datasource as (select collection_time_utc, host_name, object, counter, value, instance from [SQL2019].DBA.dbo.performance_counters)

select collection_time_utc, host_name, object, counter, value, instance from cte_counters_local --with (forceseek)
--union all
--select collection_time_utc, host_name, object, counter, value, instance from cte_counters_datasource"
	set quoted_identifier on;

	exec (@sql);
end
go


/* ***** 8) Create dbo.perfmon_files table using Partition scheme ***************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '8) Create dbo.perfmon_files table using Partition scheme';

-- drop table [dbo].[perfmon_files]
if OBJECT_ID('[dbo].[perfmon_files]') is null
begin
	CREATE TABLE [dbo].[perfmon_files]
	(
		[host_name] [varchar](255) NOT NULL,
		[file_name] [varchar](255) NOT NULL,
		[file_path] [varchar](255) NOT NULL,
		[collection_time_utc] [datetime2](7) NOT NULL default sysutcdatetime(),
		CONSTRAINT [pk_perfmon_files] PRIMARY KEY CLUSTERED 
		(
			[file_name] ASC,
			[collection_time_utc] ASC
		) on ps_dba_datetime2_daily ([collection_time_utc])
	) on ps_dba_datetime2_daily ([collection_time_utc])
end
GO

if not exists (select 1 from dbo.purge_table where table_name = 'dbo.perfmon_files')
begin
	insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.perfmon_files', 
			date_key = 'collection_time_utc', 
			retention_days = 15, 
			purge_row_size = 100000,
			reference = 'SQLMonitor Data Collection'
end
go


/* ***** 9) Create table [dbo].[os_task_list] using Partition scheme ***************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '9) Create table [dbo].[os_task_list] using Partition scheme';

-- drop table [dbo].[os_task_list]
if OBJECT_ID('[dbo].[os_task_list]') is null
begin
	CREATE TABLE [dbo].[os_task_list]
	(	
		[collection_time_utc] [datetime2](7) NOT NULL,
		[host_name] [varchar](255) NOT NULL,
		[task_name] [nvarchar](100) not null,
		[pid] bigint not null,
		[session_name] [varchar](20) null,
		[memory_kb] bigint NULL,
		[status] [varchar](30) NULL,
		[user_name] [varchar](200) NOT NULL,
		[cpu_time] [char](14) NOT NULL,
		[cpu_time_seconds] bigint NOT NULL,
		[window_title] [nvarchar](2000) NULL
	) on ps_dba_datetime2_daily ([collection_time_utc])
end
go

if not exists (select * from sys.indexes where [object_id] = OBJECT_ID('[dbo].[os_task_list]') and name = 'ci_os_task_list')
begin
	create clustered index ci_os_task_list on [dbo].[os_task_list] ([collection_time_utc], [host_name], [task_name]) on ps_dba_datetime2_daily ([collection_time_utc])
end
go

if not exists (select 1 from dbo.purge_table where table_name = 'dbo.os_task_list')
begin
	insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.os_task_list', 
			date_key = 'collection_time_utc', 
			retention_days = 15, 
			purge_row_size = 100000,
			reference = 'SQLMonitor Data Collection'
end
go


/* ***** 10) Create View [dbo].[vw_os_task_list] for Multi SqlCluster on same nodes Architecture */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '10) Create View [dbo].[vw_os_task_list] for Multi SqlCluster on same nodes Architecture';

-- drop view dbo.vw_os_task_list
if OBJECT_ID('dbo.vw_os_task_list') is null
	exec ('create view dbo.vw_os_task_list as select 1 as dummy;')
go
declare @recreate_multi_server_views bit = 1;
declare @sql nvarchar(max);
if @recreate_multi_server_views = 1
begin
	set quoted_identifier off;
	set @sql = "alter view dbo.vw_os_task_list
--with schemabinding
as
with cte_os_tasks_local as (select [collection_time_utc], [host_name], [task_name], [pid], [session_name], [memory_kb], [status], [user_name], [cpu_time], [cpu_time_seconds], [window_title] from dbo.os_task_list)
--,cte_os_tasks_datasource as (select [collection_time_utc], [host_name], [task_name], [pid], [session_name], [memory_kb], [status], [user_name], [cpu_time], [cpu_time_seconds], [window_title] from [SQL2019].DBA.dbo.os_task_list)

select [collection_time_utc], [host_name], [task_name], [pid], [session_name], [memory_kb], [status], [user_name], [cpu_time], [cpu_time_seconds], [window_title] from cte_os_tasks_local
--union all
--select [collection_time_utc], [host_name], [task_name], [pid], [session_name], [memory_kb], [status], [user_name], [cpu_time], [cpu_time_seconds], [window_title] from cte_os_tasks_datasource"
	set quoted_identifier on;

	exec (@sql);
end
go



/* ***** 11) Create table  [dbo].[wait_stats] using Partition scheme ***************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '11) Create table  [dbo].[wait_stats] using Partition scheme';

-- drop table [dbo].[wait_stats]
if OBJECT_ID('[dbo].[wait_stats]') is null
begin
	CREATE TABLE [dbo].[wait_stats]
	(
		[collection_time_utc] datetime2 not null,
		[wait_type] [nvarchar](60) NOT NULL,
		[waiting_tasks_count] [bigint] NOT NULL,
		[wait_time_ms] [bigint] NOT NULL,
		[max_wait_time_ms] [bigint] NOT NULL,
		[signal_wait_time_ms] [bigint] NOT NULL,
		constraint pk_wait_stats primary key ([collection_time_utc], [wait_type]) on ps_dba_datetime2_daily ([collection_time_utc])
	) on ps_dba_datetime2_daily ([collection_time_utc])
end
GO

if not exists (select * from sys.indexes where [object_id] = OBJECT_ID('[dbo].[wait_stats]') and type_desc = 'CLUSTERED')
begin
	alter table [dbo].[wait_stats] add constraint pk_wait_stats primary key ([collection_time_utc], [wait_type]) on ps_dba_datetime2_daily ([collection_time_utc])
end
go

if not exists (select 1 from dbo.purge_table where table_name = 'dbo.wait_stats')
begin
	insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.wait_stats', 
			date_key = 'collection_time_utc', 
			retention_days = 365, 
			purge_row_size = 100000,
			reference = 'SQLMonitor Data Collection'
end
go



/* ***** 12) Create table  [dbo].[BlitzFirst_WaitStats_Categories] ***************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '12) Create table  [dbo].[BlitzFirst_WaitStats_Categories]';

-- drop table [dbo].[BlitzFirst_WaitStats_Categories]
if OBJECT_ID('[dbo].[BlitzFirst_WaitStats_Categories]') is null
begin
	CREATE TABLE [dbo].[BlitzFirst_WaitStats_Categories]
	(
		[WaitType] [nvarchar](60) NOT NULL,
		[WaitCategory] [nvarchar](128) NOT NULL,
		[Ignorable] [bit] NULL default 0, -- Default settings of First-Responder-Kit
		[IgnorableOnPerCoreMetric] [bit] NULL default 0, -- Custom settings for PerCorePerMinutes on Central Dashboard
		[IgnorableOnDashboard] [bit] NULL default 0, -- Custom settings for Wait Stats Dashboard
		PRIMARY KEY CLUSTERED (	[WaitType] ASC )
	);
end
GO
if OBJECT_ID('[dbo].[BlitzFirst_WaitStats_Categories]') is not null
begin
	declare @sql nvarchar(max);
	
	if not exists (SELECT 1/0 FROM sys.columns c where c.object_id = OBJECT_ID('[dbo].[BlitzFirst_WaitStats_Categories]') and c.name = 'IgnorableOnPerCoreMetric')
	begin
		set @sql ='alter table [dbo].[BlitzFirst_WaitStats_Categories] add [IgnorableOnPerCoreMetric] [bit] NULL default 0';
		exec (@sql);
	end

	if not exists (SELECT 1/0 FROM sys.columns c where c.object_id = OBJECT_ID('[dbo].[BlitzFirst_WaitStats_Categories]') and c.name = 'IgnorableOnDashboard')
	begin
		set @sql ='alter table [dbo].[BlitzFirst_WaitStats_Categories] add [IgnorableOnDashboard] [bit] NULL default 0';
		exec (@sql);
	end
end
go


/* ***** 13) Create view  [dbo].[vw_wait_stats_deltas] ***************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '13) Create view  [dbo].[vw_wait_stats_deltas]';

-- DROP VIEW [dbo].[vw_wait_stats_deltas];
if OBJECT_ID('[dbo].[vw_wait_stats_deltas]') is null
	exec ('CREATE VIEW [dbo].[vw_wait_stats_deltas] AS SELECT 1 as Dummy');
go
ALTER VIEW [dbo].[vw_wait_stats_deltas]
WITH SCHEMABINDING 
AS
WITH RowDates as ( 
	SELECT ROW_NUMBER() OVER (ORDER BY [collection_time_utc]) ID, [collection_time_utc]
	FROM [dbo].[wait_stats] 
	--WHERE [collection_time_utc] between @start_time and @end_time
	GROUP BY [collection_time_utc]
)
, collection_time_utcs as
(	SELECT ThisDate.collection_time_utc, LastDate.collection_time_utc as Previouscollection_time_utc
    FROM RowDates ThisDate
    JOIN RowDates LastDate
    ON ThisDate.ID = LastDate.ID + 1
)
--select * from collection_time_utcs
SELECT	w.collection_time_utc, w.wait_type, 
		COALESCE(wc.WaitCategory, 'Other') AS WaitCategory, 
		COALESCE(wc.Ignorable,0) AS Ignorable,
		COALESCE(wc.IgnorableOnPerCoreMetric,wc.Ignorable,0) AS IgnorableOnPerCoreMetric,
		COALESCE(wc.IgnorableOnDashboard,wc.Ignorable,0) AS IgnorableOnDashboard
		,DATEDIFF(ss, wPrior.collection_time_utc, w.collection_time_utc) AS ElapsedSeconds
		,(w.wait_time_ms - wPrior.wait_time_ms) AS wait_time_ms_delta
		,(w.wait_time_ms - wPrior.wait_time_ms) / 60000.0 AS wait_time_minutes_delta
		,(w.wait_time_ms - wPrior.wait_time_ms) / 1000.0 / DATEDIFF(ss, wPrior.collection_time_utc, w.collection_time_utc) AS wait_time_minutes_per_minute
		,(w.signal_wait_time_ms - wPrior.signal_wait_time_ms) AS signal_wait_time_ms_delta
		,(w.waiting_tasks_count - wPrior.waiting_tasks_count) AS waiting_tasks_count_delta
FROM [dbo].[wait_stats] w
--INNER HASH JOIN collection_time_utcs Dates
INNER JOIN collection_time_utcs Dates
ON Dates.collection_time_utc = w.collection_time_utc
INNER JOIN [dbo].[wait_stats] wPrior ON w.wait_type = wPrior.wait_type AND Dates.Previouscollection_time_utc = wPrior.collection_time_utc
LEFT OUTER JOIN [dbo].[BlitzFirst_WaitStats_Categories] wc ON w.wait_type = wc.WaitType
WHERE [w].[wait_time_ms] >= [wPrior].[wait_time_ms]
--ORDER BY w.collection_time_utc, wait_time_ms_delta desc
GO


/* ***** 14) Create table  [dbo].[file_io_stats] using Partition scheme ***************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '14) Create table  [dbo].[file_io_stats] using Partition scheme';

-- drop table [dbo].[file_io_stats]
if OBJECT_ID('[dbo].[file_io_stats]') is null
begin
	CREATE TABLE [dbo].[file_io_stats]
	(
		[collection_time_utc] [datetime2](7) NOT NULL,
		[database_name] [sysname] NOT NULL,
		[database_id] [int] NOT NULL,
		[file_logical_name] [sysname] NOT NULL,
		[file_id] [int] NOT NULL,
		[file_location] [nvarchar](260) NOT NULL,
		[sample_ms] [bigint] NOT NULL,
		[num_of_reads] [bigint] NOT NULL,
		[num_of_bytes_read] [bigint] NOT NULL,
		[io_stall_read_ms] [bigint] NOT NULL,
		[io_stall_queued_read_ms] [bigint] NOT NULL,
		[num_of_writes] [bigint] NOT NULL,
		[num_of_bytes_written] [bigint] NOT NULL,
		[io_stall_write_ms] [bigint] NOT NULL,
		[io_stall_queued_write_ms] [bigint] NOT NULL,
		[io_stall] [bigint] NOT NULL,
		[size_on_disk_bytes] [bigint] NOT NULL,
		[io_pending_count] [bigint] NULL DEFAULT 0,
		[io_pending_ms_ticks_total] [bigint] NULL DEFAULT 0,
		[io_pending_ms_ticks_avg] [bigint] NULL DEFAULT 0,
		[io_pending_ms_ticks_max] [bigint] NULL DEFAULT 0,
		[io_pending_ms_ticks_min] [bigint] NULL DEFAULT 0
	) on ps_dba_datetime2_daily ([collection_time_utc]);
end
GO

if not exists (select * from sys.indexes where [object_id] = OBJECT_ID('[dbo].[file_io_stats]') and type_desc = 'CLUSTERED')
begin
	alter table [dbo].[file_io_stats] add constraint pk_file_io_stats primary key clustered ([collection_time_utc], [database_id], [file_id]) on ps_dba_datetime2_daily ([collection_time_utc])
end
go

if not exists (select 1 from dbo.purge_table where table_name = 'dbo.file_io_stats')
begin
	insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.file_io_stats', 
			date_key = 'collection_time_utc', 
			retention_days = 365, 
			purge_row_size = 100000,
			reference = 'SQLMonitor Data Collection'
end
go


/* ***** 15) Create required schemas ***************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '15) Create required schemas';

if not exists (select * from sys.schemas where name = 'bkp')
	exec ('CREATE SCHEMA [bkp]')
GO
if not exists (select * from sys.schemas where name = 'poc')
	exec ('CREATE SCHEMA [poc]')
GO
if not exists (select * from sys.schemas where name = 'stg')
	exec ('CREATE SCHEMA [stg]')
GO
if not exists (select * from sys.schemas where name = 'tst')
	exec ('CREATE SCHEMA [tst]')
GO


/* ***** 16) Create procedure dbo.usp_extended_results ***************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '16) Create procedure dbo.usp_extended_results';

-- drop procedure usp_extended_results
if OBJECT_ID('dbo.usp_extended_results') is null
	exec('create procedure dbo.usp_extended_results as select 1 as dummy;')
go
alter procedure dbo.usp_extended_results @processor_name nvarchar(500) = null output, @host_distribution nvarchar(500) = null output, @fqdn nvarchar(100) = null output
--with execute as owner
as
begin
	set nocount on;
	
	-- Processor Name
	exec xp_instance_regread 'HKEY_LOCAL_MACHINE', 'HARDWARE\DESCRIPTION\System\CentralProcessor\0', 'ProcessorNameString', @value = @processor_name output;

	-- Windows Version
	EXEC xp_instance_regread 'HKEY_LOCAL_MACHINE', 'SOFTWARE\Microsoft\Windows NT\CurrentVersion', 'ProductName', @value = @host_distribution OUTPUT;

	-- FQDN
	EXEC master.dbo.xp_regread 'HKEY_LOCAL_MACHINE', 'SYSTEM\CurrentControlSet\services\Tcpip\Parameters', N'Domain', @fqdn OUTPUT;     
	SET @fqdn = Cast(SERVERPROPERTY('MachineName') as nvarchar) + '.' + @fqdn;
end
go


/* ***** 17) Create table [dbo].[xevent_metrics] ***************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '17) Create table [dbo].[xevent_metrics]';

-- DROP TABLE [dbo].[xevent_metrics]
IF OBJECT_ID('[dbo].[xevent_metrics]') IS NULL
BEGIN
	CREATE TABLE [dbo].[xevent_metrics]
	(
		[row_id] [bigint] NOT NULL,
		[start_time] [datetime2](7) NOT NULL,
		[event_time] [datetime2](7) NOT NULL,
		[event_name] [nvarchar](60) NOT NULL,
		[session_id] [int] NOT NULL,
		[request_id] [int] NOT NULL,
		[result] [varchar](50) NULL,
		[database_name] [varchar](255) NULL,
		[client_app_name] [varchar](255) NULL,
		[username] [varchar](255) NULL,
		[cpu_time_ms] [bigint] NULL,
		[duration_seconds] [bigint] NULL,
		[logical_reads] [bigint] NULL,
		[physical_reads] [bigint] NULL,
		[row_count] [bigint] NULL,
		[writes] [bigint] NULL,
		[spills] [bigint] NULL,
		--[sql_text] [varchar](max) NULL,
		--[query_hash] [varbinary](255) NULL,
		--[query_plan_hash] [varbinary](255) NULL,
		[client_hostname] [varchar](255) NULL,
		[session_resource_pool_id] [int] NULL,
		[session_resource_group_id] [int] NULL,
		[scheduler_id] [int] NULL
		,constraint pk_xevent_metrics primary key clustered (event_time,start_time,[row_id]) on ps_dba_datetime2_daily ([event_time])
	) on ps_dba_datetime2_daily ([event_time])
END
GO

if not exists (select * from sys.indexes where [object_id] = OBJECT_ID('[dbo].[xevent_metrics]') and name = 'uq_xevent_metrics')
begin
	create unique index uq_xevent_metrics on [dbo].[xevent_metrics]  ([start_time], [event_time], [row_id]) on ps_dba_datetime2_daily ([start_time])
end
GO

if not exists (select 1 from dbo.purge_table where table_name = 'dbo.xevent_metrics')
begin
	insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.xevent_metrics', 
			date_key = 'event_time', 
			retention_days = 180, 
			purge_row_size = 100000,
			reference = 'SQLMonitor Data Collection'
end
go


/* ***** 18) Create table [dbo].[xevent_metrics_queries] ***************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '18) Create table [dbo].[xevent_metrics_queries]';

-- DROP TABLE [dbo].[xevent_metrics_queries]
IF OBJECT_ID('[dbo].[xevent_metrics_queries]') IS NULL
BEGIN
	CREATE TABLE [dbo].[xevent_metrics_queries]
	(
		[row_id] [bigint] NOT NULL,
		[start_time] [datetime2](7) NOT NULL,
		[event_time] [datetime2](7) NOT NULL,
		[sql_text] [varchar](max) NULL
		,constraint pk_xevent_metrics_queries primary key clustered (event_time,start_time,[row_id]) on ps_dba_datetime2_daily ([event_time])
	) on ps_dba_datetime2_daily ([event_time])
END
GO

if not exists (select 1 from dbo.purge_table where table_name = 'dbo.xevent_metrics_queries')
begin
	insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.xevent_metrics_queries', 
			date_key = 'event_time', 
			retention_days = 30, 
			purge_row_size = 100000,
			reference = 'SQLMonitor Data Collection'
end
go


/* ***** 19) Create view  [dbo].[vw_xevent_metrics] ***************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '19) Create view  [dbo].[vw_xevent_metrics]';

-- DROP VIEW [dbo].[vw_xevent_metrics];
if OBJECT_ID('[dbo].[vw_xevent_metrics]') is null
	exec ('CREATE VIEW [dbo].[vw_xevent_metrics] AS SELECT 1 as Dummy');
go
ALTER VIEW [dbo].[vw_xevent_metrics]
WITH SCHEMABINDING 
AS
SELECT rc.[row_id], rc.[start_time], rc.[event_time], rc.[event_name], rc.[session_id], rc.[request_id], rc.[result], rc.[database_name], rc.[client_app_name], rc.[username], rc.[cpu_time_ms], rc.[duration_seconds], rc.[logical_reads], rc.[physical_reads], rc.[row_count], rc.[writes], rc.[spills], txt.[sql_text], /* rc.[query_hash], rc.[query_plan_hash], */ rc.[client_hostname], rc.[session_resource_pool_id], rc.[session_resource_group_id], rc.[scheduler_id]
FROM [dbo].[xevent_metrics] rc
LEFT JOIN [dbo].[xevent_metrics_queries] txt
	ON rc.event_time = txt.event_time
	AND rc.start_time = txt.start_time
	AND rc.row_id = txt.row_id
GO


/* ***** 20) Create Trigger [tgr_insert_xevent_metrics] on View  [dbo].[vw_xevent_metrics] ***************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '20) Create Trigger [tgr_insert_xevent_metrics] on View  [dbo].[vw_xevent_metrics]';

if exists (select * from sys.objects where [name] = N'tgr_insert_xevent_metrics' and [type] = 'TR')
	drop trigger [dbo].tgr_insert_xevent_metrics
GO
create trigger dbo.tgr_insert_xevent_metrics on dbo.vw_xevent_metrics
instead of insert as
begin
	set nocount on;

	insert dbo.xevent_metrics
	(	[row_id], [start_time], [event_time], [event_name], [session_id], [request_id], [result], [database_name], 
		[client_app_name], [username], [cpu_time_ms], [duration_seconds], [logical_reads], [physical_reads], [row_count], 
		[writes], [spills], [client_hostname], [session_resource_pool_id], [session_resource_group_id], [scheduler_id] )
	select [row_id], [start_time], [event_time], [event_name], [session_id], [request_id], [result], [database_name], 
		[client_app_name], [username], [cpu_time_ms], [duration_seconds], [logical_reads], [physical_reads], [row_count], 
		[writes], [spills], [client_hostname], [session_resource_pool_id], [session_resource_group_id], [scheduler_id]
	from inserted;

	insert dbo.xevent_metrics_queries
	(	[row_id], [start_time], [event_time], [sql_text] )
	select [row_id], [start_time], [event_time], [sql_text]
	from inserted;
end
go



/* ***** 21) Create table [dbo].[xevent_metrics_Processed_XEL_Files] ***************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '21) Create table [dbo].[xevent_metrics_Processed_XEL_Files]';

-- drop table dbo.xevent_metrics_Processed_XEL_Files
if OBJECT_ID('dbo.xevent_metrics_Processed_XEL_Files') is null
begin
	create table dbo.xevent_metrics_Processed_XEL_Files
	( file_path varchar(2000) not null, collection_time_utc datetime2 not null default SYSUTCDATETIME(), is_processed bit default 0 not null, is_removed_from_disk bit default 0 not null );
end
go

if not exists (select * from sys.indexes where [object_id] = OBJECT_ID('[dbo].[xevent_metrics_Processed_XEL_Files]') and name = 'pk_xevent_metrics_Processed_XEL_Files')
begin
	alter table dbo.xevent_metrics_Processed_XEL_Files add constraint pk_xevent_metrics_Processed_XEL_Files primary key clustered (file_path,  collection_time_utc);
end
GO

if not exists (select 1 from dbo.purge_table where table_name = 'dbo.xevent_metrics_Processed_XEL_Files')
begin
	insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.xevent_metrics_Processed_XEL_Files', 
			date_key = 'collection_time_utc', 
			retention_days = 7, 
			purge_row_size = 100000,
			reference = 'SQLMonitor Data Collection'
end
go


/* ***** 22) Create table [dbo].[disk_space] using Partition scheme *********** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '22) Create table [dbo].[disk_space] using Partition scheme';

if OBJECT_ID('[dbo].[disk_space]') is null
begin
	CREATE TABLE [dbo].[disk_space]
	(
		[collection_time_utc] [datetime2](7) NOT NULL,
		[host_name] [varchar](125) NOT NULL,
		[disk_volume] [varchar](255) NOT NULL,
		[label] [varchar](125) NULL,
		[capacity_mb] [decimal](20,2) NOT NULL,
		[free_mb] [decimal](20,2) NOT NULL,
		[block_size] [int] NULL,
		[filesystem] [varchar](125) NULL,

		constraint pk_disk_space primary key ([collection_time_utc],[host_name],[disk_volume]) on ps_dba_datetime2_daily ([collection_time_utc])
	) on ps_dba_datetime2_daily ([collection_time_utc]);
end
go

if not exists (select 1 from dbo.purge_table where table_name = 'dbo.disk_space')
begin
	insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.disk_space', 
			date_key = 'collection_time_utc', 
			retention_days = 365, 
			purge_row_size = 100000,
			reference = 'SQLMonitor Data Collection'
end
go

/* ***** 23) Create View [dbo].[vw_disk_space] for Multi SqlCluster on same nodes Architecture */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '23) Create View [dbo].[vw_disk_space] for Multi SqlCluster on same nodes Architecture';

-- drop view dbo.vw_disk_space
if OBJECT_ID('dbo.vw_disk_space') is null
	exec ('create view dbo.vw_disk_space as select 1 as dummy;')
go
declare @recreate_multi_server_views bit = 1;
declare @sql nvarchar(max);
if @recreate_multi_server_views = 1
begin
	set quoted_identifier off;
	set @sql = "alter view dbo.vw_disk_space
--with schemabinding
as
with cte_disk_space_local as (select collection_time_utc, host_name, disk_volume, label, capacity_mb, free_mb, block_size, filesystem from dbo.disk_space)
--,cte_disk_space_datasource as (select collection_time_utc, host_name, disk_volume, label, capacity_mb, free_mb, block_size, filesystem from [SQL2019].DBA.dbo.disk_space)

select collection_time_utc, host_name, disk_volume, label, capacity_mb, free_mb, block_size, filesystem from cte_disk_space_local
--union all
--select collection_time_utc, host_name, disk_volume, label, capacity_mb, free_mb, block_size, filesystem from cte_disk_space_datasource"
	set quoted_identifier on;

	exec (@sql);
end
go


/* ***** 24) Create view  [dbo].[vw_file_io_stats_deltas] ***************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '24) Create view  [dbo].[vw_file_io_stats_deltas]';

-- DROP VIEW [dbo].[vw_file_io_stats_deltas];
if OBJECT_ID('[dbo].[vw_file_io_stats_deltas]') is null
	exec ('CREATE VIEW [dbo].[vw_file_io_stats_deltas] AS SELECT 1 as Dummy');
go
ALTER VIEW [dbo].[vw_file_io_stats_deltas]
WITH SCHEMABINDING 
AS
WITH RowDates as ( 
	SELECT ROW_NUMBER() OVER (ORDER BY [collection_time_utc]) ID, [collection_time_utc]
	FROM [dbo].[file_io_stats] 
	--WHERE [collection_time_utc] between @start_time and @end_time
	GROUP BY [collection_time_utc]
)
, collection_time_utcs as
(	SELECT ThisDate.collection_time_utc, LastDate.collection_time_utc as Previouscollection_time_utc
    FROM RowDates ThisDate
    JOIN RowDates LastDate
    ON ThisDate.ID = LastDate.ID + 1
)
, [t_DiskDrives] AS 
(	select ds.disk_volume
	from dbo.disk_space ds
	where ds.collection_time_utc = (select max(i.collection_time_utc) from dbo.disk_space i)
)
--select * from collection_time_utcs
SELECT s.collection_time_utc, s.database_name, dv.disk_volume, s.[file_logical_name], s.[file_location],
		[sample_ms_delta] = s.sample_ms - sPrior.sample_ms,
		[elapsed_seconds] = DATEDIFF(ss, sPrior.collection_time_utc, s.collection_time_utc),
		[read_write_bytes_delta] = ( (s.[num_of_bytes_read]+s.[num_of_bytes_written]) - (sPrior.[num_of_bytes_read]+sPrior.[num_of_bytes_written]) ),
		[read_writes_delta] = ( (s.[num_of_reads]+s.[num_of_writes]) - (sPrior.[num_of_reads]+sPrior.[num_of_writes]) ),  
		[read_bytes_delta] = s.[num_of_bytes_read] - sPrior.[num_of_bytes_read],
		[writes_bytes_delta] = s.[num_of_bytes_read] - sPrior.[num_of_bytes_read],
		[num_of_reads_delta] = s.[num_of_reads] - sPrior.[num_of_reads],
		[num_of_writes_delta] = s.[num_of_writes] - sPrior.[num_of_writes],
		[io_stall_delta] = s.[io_stall]- sPrior.[io_stall]
FROM [dbo].[file_io_stats] s
INNER JOIN collection_time_utcs Dates
	ON Dates.collection_time_utc = s.collection_time_utc
INNER JOIN [dbo].[file_io_stats] sPrior 
	ON s.[database_name] = sPrior.[database_name] 
	AND s.[file_logical_name] = sPrior.[file_logical_name] 
	AND Dates.Previouscollection_time_utc = sPrior.collection_time_utc
OUTER APPLY (
			select top 1 dd.disk_volume
			from [t_DiskDrives] dd
			where s.file_location like (dd.disk_volume+'%')
			order by len(dd.disk_volume) desc
		) dv
WHERE [s].[io_stall] >= [sPrior].[io_stall]
--ORDER BY s.collection_time_utc, wait_time_ms_delta desc
GO


/* ***** 25) Create table [dbo].[memory_clerks] *************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '25) Create table [dbo].[memory_clerks]';

-- drop table [dbo].[memory_clerks]
if OBJECT_ID('[dbo].[memory_clerks]') is null
begin
	CREATE TABLE [dbo].[memory_clerks]
	(
		[collection_time_utc] datetime2 not null default sysutcdatetime(),
		[memory_clerk] [varchar](255) NOT NULL,
		[name] [varchar](255) NOT NULL,
		[size_mb] [bigint] NOT NULL,
		constraint pk_memory_clerks primary key ([collection_time_utc], [memory_clerk]) on ps_dba_datetime2_daily ([collection_time_utc])
	) on ps_dba_datetime2_daily ([collection_time_utc])
end
GO

if not exists (select * from sys.indexes where [object_id] = OBJECT_ID('[dbo].[memory_clerks]') and type_desc = 'CLUSTERED')
begin
	alter table [dbo].[memory_clerks] add constraint pk_memory_clerks primary key ([collection_time_utc], [memory_clerk]) on ps_dba_datetime2_daily ([collection_time_utc])
end
go

if not exists (select 1 from dbo.purge_table where table_name = 'dbo.memory_clerks')
begin
	insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.memory_clerks', 
			date_key = 'collection_time_utc', 
			retention_days = 180, 
			purge_row_size = 100000,
			reference = 'SQLMonitor Data Collection'
end
go


/* **** 26) Create table [dbo].[server_privileged_info] ************* */
-- drop table [dbo].[server_privileged_info]
if OBJECT_ID('[dbo].[server_privileged_info]') is null
begin
	CREATE TABLE [dbo].[server_privileged_info]
	(
		[collection_time_utc] datetime2 not null default sysutcdatetime(),
		[host_name] varchar(125) not null,
		[host_distribution] varchar(200) null,
		[processor_name] varchar(200) null,
		[fqdn] varchar(255) null,

		constraint pk_server_privileged_info primary key ([collection_time_utc], [host_name])
	);
end
GO

if not exists (select * from sys.indexes where [object_id] = OBJECT_ID('[dbo].[server_privileged_info]') and type_desc = 'CLUSTERED')
begin
	alter table [dbo].[server_privileged_info] add constraint pk_server_privileged_info primary key ([collection_time_utc], [host_name])
end
go

if not exists (select 1 from dbo.purge_table where table_name = 'dbo.server_privileged_info')
begin
	insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.server_privileged_info', 
			date_key = 'collection_time_utc', 
			retention_days = 180, 
			purge_row_size = 100000,
			reference = 'SQLMonitor Data Collection'
end
go


/* ***** 27) Create table [dbo].[ag_health_state] using Partition scheme ***************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '27) Create table [dbo].[ag_health_state] using Partition scheme';

-- drop table [dbo].[ag_health_state]
if OBJECT_ID('[dbo].[ag_health_state]') is null
begin
	create table [dbo].[ag_health_state]
	(
		[collection_time_utc] [datetime2](7) NOT NULL default sysutcdatetime(),
		[replica_server_name] [nvarchar](256) NULL,
		[is_primary_replica] [bit] NULL,
		[database_name] [sysname] NULL,
		[ag_name] [sysname] NULL,
		[ag_listener] [nvarchar](114) NULL,
		[is_local] [bit] NULL,
		[is_distributed] [bit] NULL,
		[synchronization_state_desc] [nvarchar](60) NULL,
		[synchronization_health_desc] [nvarchar](60) NULL,
		[latency_seconds] [int] NULL,
		[redo_queue_size] [bigint] NULL,
		[log_send_queue_size] [bigint] NULL,
		[last_redone_time] [datetime] NULL,
		[log_send_rate] [bigint] NULL,
		[redo_rate] [bigint] NULL,
		[estimated_redo_completion_time_min] [numeric](26, 6) NULL,
		[last_commit_time] [datetime] NULL,
		[is_suspended] [bit] NULL,
		[suspend_reason_desc] [nvarchar](60) NULL
	) on ps_dba_datetime2_daily ([collection_time_utc]);
end
go

if not exists (select * from sys.indexes where [object_id] = OBJECT_ID('[dbo].[ag_health_state]') and name = 'ci_ag_health_state')
begin
	create clustered index ci_ag_health_state on [dbo].[ag_health_state] ([collection_time_utc], [replica_server_name], [database_name]) on ps_dba_datetime2_daily ([collection_time_utc])
end
go

if not exists (select 1 from dbo.purge_table where table_name = 'dbo.ag_health_state')
begin
	insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.ag_health_state', 
			date_key = 'collection_time_utc', 
			retention_days = 90, 
			purge_row_size = 100000,
			reference = 'SQLMonitor Data Collection'
end
go


/* ***** 28) Create table [dbo].[alert_categories] **************************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '28) Create table [dbo].[alert_categories]';

-- drop table [dbo].[alert_categories]
if OBJECT_ID('[dbo].[alert_categories]') is null
begin
	create table [dbo].[alert_categories]
	(
		[error_number] [int] NOT NULL,
		[error_severity] [int] NULL,
		[category] [varchar](128) NOT NULL,
		[sub_category] [varchar](128) NULL,
		[alert_name] [varchar](255) NOT NULL,
		[remarks] [nvarchar](500) NULL,

		[created_time] [datetime2](7) NOT NULL default sysdatetime(),
		[created_by] [nvarchar](128) NOT NULL default suser_name()
	);
end
go

if not exists (select * from sys.indexes where [object_id] = OBJECT_ID('[dbo].[alert_categories]') and name = 'ci_alert_categories')
begin
	create unique clustered index ci_alert_categories on [dbo].[alert_categories] ([error_number],[error_severity]);
end
go

--	Alerts would be created using [DDLs\SCH-usp_create_agent_alerts.sql]
if OBJECT_ID('[dbo].[alert_categories]') is not null
begin
	insert dbo.alert_categories
	([error_number], [error_severity], [category], [sub_category], [alert_name], [remarks])
	select en.[error_number], en.[error_severity], en.[category], en.[sub_category], en.[alert_name], en.[remarks]
	from (VALUES	('1480', 0, 'Availability Group', NULL, '(dba) AG Role Change - failover', NULL)
				  , ('976', 0, 'Availability Group', NULL, '(dba) Database Not Accessible', NULL)
				  , ('983', 0, 'Availability Group', NULL, '(dba) Database Role Resolving', NULL)
				  , ('3402' , 0, 'Availability Group', NULL, '(dba) Database Restoring', NULL)
				  , ('19406', 0, 'Availability Group', NULL, '(dba) AG Replica Changed States', NULL)
				  , ('35206', 0, 'Availability Group', NULL, '(dba) Connection Timeout', NULL)
				  , ('35250', 0, 'Availability Group', NULL, '(dba) Connection to Primary Inactive', NULL)
				  , ('35264', 0, 'Availability Group', NULL, '(dba) Data Movement Suspended', NULL)
				  , ('35273', 0, 'Availability Group', NULL, '(dba) Database Inaccessible', NULL)
				  , ('35274', 0, 'Availability Group', NULL, '(dba) Database Recovery Pending', NULL)
				  , ('35275', 0, 'Availability Group', NULL, '(dba) Database in Suspect State', NULL)
				  , ('35276', 0, 'Availability Group', NULL, '(dba) Database Out of Sync', NULL)
				  , ('41091', 0, 'Availability Group', NULL, '(dba) Replica Going Offline', NULL)
				  , ('41131', 0, 'Availability Group', NULL, '(dba) Failed to Bring AG Online', NULL)
				  , ('41142', 0, 'Availability Group', NULL, '(dba) Replica Cannot Become Primary', NULL)
				  , ('41406', 0, 'Availability Group', NULL, '(dba) AG Not Ready for Auto Failover', NULL)
				  , ('41414', 0, 'Availability Group', NULL, '(dba) Secondary Not Connected', NULL)
				  , ('0', 19, 'Fatal Error - Sev19', NULL, '(dba) Fatal Error - Sev19', NULL)
				  , ('0', 20, 'Fatal Error - Sev20', NULL, '(dba) Fatal Error - Sev20', NULL)
				  , ('0', 21, 'Fatal Error - Sev21', NULL, '(dba) Fatal Error - Sev21', NULL)
				  , ('0', 22, 'Fatal Error - Sev22', NULL, '(dba) Fatal Error - Sev22', NULL)
				  , ('0', 23, 'Fatal Error - Sev23', NULL, '(dba) Fatal Error - Sev23', NULL)
				  , ('0', 24, 'Fatal Error - Sev24', NULL, '(dba) Fatal Error - Sev24', NULL)
				  , ('0', 25, 'Fatal Error - Sev25', NULL, '(dba) Fatal Error - Sev25', NULL)
				  , ('701', 0, 'Insufficient System Memory', NULL, '(dba) Insufficient System memory', NULL)
				  , ('823', 0, 'Corruption', NULL, '(dba) Corruption - Error 823', NULL)
				  , ('824', 0, 'Corruption', NULL, '(dba) Corruption - Error 824', NULL)
				  , ('825', 0, 'Corruption', NULL, '(dba) Corruption - Error 825', NULL)
		) en ([error_number], [error_severity], [category], [sub_category], [alert_name], [remarks])
	left join dbo.alert_categories ac
		on exists (select ac.error_number, ac.[error_severity] intersect select en.error_number, en.[error_severity])
	where ac.category is null;			
end
go


/* ***** 29) Create table [dbo].[alert_history]		**************************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '29) Create table [dbo].[alert_history]';

-- drop table [dbo].[alert_history]
if OBJECT_ID('[dbo].[alert_history]') is null
begin
	create table [dbo].[alert_history]
	(
		[collection_time_utc] [datetime2](7) NOT NULL default sysutcdatetime(),		
		[server_name] [nvarchar](128) NULL,
		[database_name] [sysname] NULL,
		[error_number] [int] NULL,
		[error_severity] [tinyint] NULL,
		[error_message] [nvarchar](510) NULL,
		[host_instance] [nvarchar](128) NULL,
		[collection_time] [datetime2](7) NOT NULL default sysdatetime()
	) on ps_dba_datetime2_daily ([collection_time_utc]);
end
go

if not exists (select * from sys.indexes where [object_id] = OBJECT_ID('[dbo].[alert_history]') and name = 'ci_alert_history')
begin
	create clustered index ci_alert_history on [dbo].[alert_history] ([collection_time_utc]) on ps_dba_datetime2_daily ([collection_time_utc])
end
go

if not exists (select 1 from dbo.purge_table where table_name = 'dbo.alert_history')
begin
	insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.alert_history', 
			date_key = 'collection_time_utc', 
			retention_days = 7, 
			purge_row_size = 100000,
			reference = 'SQLMonitor Data Collection'
end
go


/* ***** 30) Add boundaries to partition. 1 boundary per hour ***************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '30) Add boundaries to partition. 1 boundary per hour';

set nocount on;
declare @is_partitioned bit = 1;
declare @is_upgrade bit = 0;
if @is_partitioned = 1 and @is_upgrade = 0
begin
	declare @current_boundary_value datetime2;
	declare @target_boundary_value datetime2; /* last day of new quarter */
	set @target_boundary_value = DATEADD (dd, -1, DATEADD(qq, DATEDIFF(qq, 0, GETDATE()) +2, 0));

	select top 1 @current_boundary_value = convert(datetime2,prv.value)
	from sys.partition_range_values prv
	join sys.partition_functions pf on pf.function_id = prv.function_id
	where pf.name = 'pf_dba_datetime2_hourly'
	order by prv.value desc;

	-- Set current boundary to current time. So that no time waste in creating old partitions
	if(@current_boundary_value is null or @current_boundary_value < dateadd(hour,datediff(hour,convert(date,getutcdate()),getutcdate())-1,cast(convert(date,getutcdate())as datetime2)))
	begin
		select 'Error - @current_boundary_value is NULL. So set to 2 Days back.';
		set @current_boundary_value = dateadd(hour,datediff(hour,convert(date,getutcdate()),getutcdate())-1,cast(convert(date,getutcdate())as datetime2));
	end
	--select [@current_boundary_value] = @current_boundary_value, [@target_boundary_value] = @target_boundary_value;	

	while (@current_boundary_value < @target_boundary_value)
	begin
		set @current_boundary_value = DATEADD(hour,1,@current_boundary_value);
		--print @current_boundary_value
		begin try
			alter partition scheme ps_dba_datetime2_hourly next used [PRIMARY];
			alter partition function pf_dba_datetime2_hourly() split range (@current_boundary_value);	
		end try
		begin catch
			print error_message();
		end catch
	end
end
go


/* ***** 31) Remove boundaries with retention of 3 months ***************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '31) Remove boundaries with retention of 3 months';

set nocount on;
declare @is_partitioned bit = 1;
declare @is_upgrade bit = 0;
if @is_partitioned = 1 and @is_upgrade = 0
begin
	declare @partition_boundary datetime2;
	declare @target_boundary_value datetime2; /* 3 months back date */
	set @target_boundary_value = DATEADD(mm,DATEDIFF(mm,0,GETDATE())-3,0);

	--select @target_boundary_value as [@target_boundary_value];

	declare cur_boundaries cursor local fast_forward for
			select convert(datetime2,prv.value) as boundary_value
			from sys.partition_range_values prv
			join sys.partition_functions pf on pf.function_id = prv.function_id
			where pf.name = 'pf_dba_datetime2_hourly' and convert(datetime2,prv.value) < @target_boundary_value
			order by prv.value asc;

	open cur_boundaries;
	fetch next from cur_boundaries into @partition_boundary;
	while @@FETCH_STATUS = 0
	begin
		--print @partition_boundary
		alter partition function pf_dba_datetime2_hourly() merge range (@partition_boundary);

		fetch next from cur_boundaries into @partition_boundary;
	end
	CLOSE cur_boundaries
	DEALLOCATE cur_boundaries;
end
go


/* ***** 32) Populate [dbo].[BlitzFirst_WaitStats_Categories] ***************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '32) Populate [dbo].[BlitzFirst_WaitStats_Categories]';

IF OBJECT_ID('[dbo].[BlitzFirst_WaitStats_Categories]') IS NOT NULL
BEGIN
	-- Add new entries of Wait Types
	INSERT INTO [dbo].[BlitzFirst_WaitStats_Categories]
	(WaitType, WaitCategory, Ignorable, IgnorableOnPerCoreMetric, IgnorableOnDashboard)
	select WaitType, WaitCategory, Ignorable, IgnorableOnPerCoreMetric, IgnorableOnDashboard
			--,[help-url] = 'https://www.sqlskills.com/help/waits/'+WaitType
	from ( values
			('ASYNC_IO_COMPLETION','Other Disk IO',0,0,0),
			('ASYNC_NETWORK_IO','Network IO',0,0,0),
			('BACKUPIO','Other Disk IO',0,0,0),
			('BROKER_CONNECTION_RECEIVE_TASK','Service Broker',0,0,0),
			('BROKER_DISPATCHER','Service Broker',0,0,0),
			('BROKER_ENDPOINT_STATE_MUTEX','Service Broker',0,0,0),
			('BROKER_EVENTHANDLER','Service Broker',1,1,1),
			('BROKER_FORWARDER','Service Broker',0,0,0),
			('BROKER_INIT','Service Broker',0,0,0),
			('BROKER_MASTERSTART','Service Broker',0,0,0),
			('BROKER_RECEIVE_WAITFOR','User Wait',1,1,1),
			('BROKER_REGISTERALLENDPOINTS','Service Broker',0,0,0),
			('BROKER_SERVICE','Service Broker',0,0,0),
			('BROKER_SHUTDOWN','Service Broker',0,0,0),
			('BROKER_START','Service Broker',0,0,0),
			('BROKER_TASK_SHUTDOWN','Service Broker',0,0,0),
			('BROKER_TASK_STOP','Service Broker',1,1,1),
			('BROKER_TASK_SUBMIT','Service Broker',0,0,0),
			('BROKER_TO_FLUSH','Service Broker',1,1,1),
			('BROKER_TRANSMISSION_OBJECT','Service Broker',0,0,0),
			('BROKER_TRANSMISSION_TABLE','Service Broker',0,0,0),
			('BROKER_TRANSMISSION_WORK','Service Broker',0,0,0),
			('BROKER_TRANSMITTER','Service Broker',1,1,1),
			('CHECKPOINT_QUEUE','Idle',1,1,1),
			('CHKPT','Tran Log IO',0,1,0),
			('CLR_AUTO_EVENT','SQL CLR',1,1,1),
			('CLR_CRST','SQL CLR',0,0,0),
			('CLR_JOIN','SQL CLR',0,0,0),
			('CLR_MANUAL_EVENT','SQL CLR',1,1,1),
			('CLR_MEMORY_SPY','SQL CLR',0,0,0),
			('CLR_MONITOR','SQL CLR',0,0,0),
			('CLR_RWLOCK_READER','SQL CLR',0,0,0),
			('CLR_RWLOCK_WRITER','SQL CLR',0,0,0),
			('CLR_SEMAPHORE','SQL CLR',1,1,1),
			('CLR_TASK_START','SQL CLR',0,0,0),
			('CLRHOST_STATE_ACCESS','SQL CLR',0,0,0),
			('CMEMPARTITIONED','Memory',0,0,0),
			('CMEMTHREAD','Memory',0,0,0),
			('CXPACKET','Parallelism',0,0,0),
			('CXCONSUMER','Parallelism',0,1,0),
			('DBMIRROR_DBM_EVENT','Mirroring',1,1,1),
			('DBMIRROR_DBM_MUTEX','Mirroring',1,1,1),
			('DBMIRROR_EVENTS_QUEUE','Mirroring',1,1,1),
			('DBMIRROR_SEND','Mirroring',0,0,0),
			('DBMIRROR_WORKER_QUEUE','Mirroring',1,1,1),
			('DBMIRRORING_CMD','Mirroring',1,1,1),
			('DIRTY_PAGE_POLL','Other',1,1,1),
			('DIRTY_PAGE_TABLE_LOCK','Replication',0,0,0),
			('DISPATCHER_QUEUE_SEMAPHORE','Other',1,1,1),
			('DPT_ENTRY_LOCK','Replication',0,0,0),
			('DTC','Transaction',0,0,0),
			('DTC_ABORT_REQUEST','Transaction',0,0,0),
			('DTC_RESOLVE','Transaction',0,0,0),
			('DTC_STATE','Transaction',0,0,0),
			('DTC_TMDOWN_REQUEST','Transaction',0,0,0),
			('DTC_WAITFOR_OUTCOME','Transaction',0,0,0),
			('DTCNEW_ENLIST','Transaction',0,0,0),
			('DTCNEW_PREPARE','Transaction',0,0,0),
			('DTCNEW_RECOVERY','Transaction',0,0,0),
			('DTCNEW_TM','Transaction',0,0,0),
			('DTCNEW_TRANSACTION_ENLISTMENT','Transaction',0,0,0),
			('DTCPNTSYNC','Transaction',0,0,0),
			('EE_PMOLOCK','Memory',0,0,0),
			('EXCHANGE','Parallelism',0,0,0),
			('EXECSYNC','Parallelism',0,1,0),
			('EXTERNAL_SCRIPT_NETWORK_IOF','Network IO',0,0,0),
			('FCB_REPLICA_READ','Replication',0,0,0),
			('FCB_REPLICA_WRITE','Replication',0,0,0),
			('FSAGENT','FileStream',0,1,0),
			('FT_COMPROWSET_RWLOCK','Full Text Search',0,0,0),
			('FT_IFTS_RWLOCK','Full Text Search',0,0,0),
			('FT_IFTS_SCHEDULER_IDLE_WAIT','Idle',1,1,1),
			('FT_IFTSHC_MUTEX','Full Text Search',1,1,1),
			('FT_IFTSISM_MUTEX','Full Text Search',1,1,1),
			('FT_MASTER_MERGE','Full Text Search',0,0,0),
			('FT_MASTER_MERGE_COORDINATOR','Full Text Search',0,0,0),
			('FT_METADATA_MUTEX','Full Text Search',0,0,0),
			('FT_PROPERTYLIST_CACHE','Full Text Search',0,0,0),
			('FT_RESTART_CRAWL','Full Text Search',0,0,0),
			('FULLTEXT GATHERER','Full Text Search',0,0,0),
			('HADR_AG_MUTEX','Replication',0,0,0),
			('HADR_AR_CRITICAL_SECTION_ENTRY','Replication',0,0,0),
			('HADR_AR_MANAGER_MUTEX','Replication',0,0,0),
			('HADR_AR_UNLOAD_COMPLETED','Replication',0,0,0),
			('HADR_ARCONTROLLER_NOTIFICATIONS_SUBSCRIBER_LIST','Replication',0,0,0),
			('HADR_BACKUP_BULK_LOCK','Replication',0,0,0),
			('HADR_BACKUP_QUEUE','Replication',0,0,0),
			('HADR_CLUSAPI_CALL','Replication',1,1,1),
			('HADR_COMPRESSED_CACHE_SYNC','Replication',0,0,0),
			('HADR_CONNECTIVITY_INFO','Replication',0,0,0),
			('HADR_DATABASE_FLOW_CONTROL','Replication',0,0,0),
			('HADR_DATABASE_VERSIONING_STATE','Replication',0,0,0),
			('HADR_DATABASE_WAIT_FOR_RECOVERY','Replication',0,0,0),
			('HADR_DATABASE_WAIT_FOR_RESTART','Replication',0,0,0),
			('HADR_DATABASE_WAIT_FOR_TRANSITION_TO_VERSIONING','Replication',0,0,0),
			('HADR_DB_COMMAND','Replication',0,0,0),
			('HADR_DB_OP_COMPLETION_SYNC','Replication',0,0,0),
			('HADR_DB_OP_START_SYNC','Replication',0,0,0),
			('HADR_DBR_SUBSCRIBER','Replication',0,0,0),
			('HADR_DBR_SUBSCRIBER_FILTER_LIST','Replication',0,0,0),
			('HADR_DBSEEDING','Replication',0,0,0),
			('HADR_DBSEEDING_LIST','Replication',0,0,0),
			('HADR_DBSTATECHANGE_SYNC','Replication',0,0,0),
			('HADR_FABRIC_CALLBACK','Replication',1,1,1),
			('HADR_FILESTREAM_BLOCK_FLUSH','Replication',0,0,0),
			('HADR_FILESTREAM_FILE_CLOSE','Replication',0,0,0),
			('HADR_FILESTREAM_FILE_REQUEST','Replication',0,0,0),
			('HADR_FILESTREAM_IOMGR','Replication',0,0,0),
			('HADR_FILESTREAM_IOMGR_IOCOMPLETION','Replication',1,1,1),
			('HADR_FILESTREAM_MANAGER','Replication',0,0,0),
			('HADR_FILESTREAM_PREPROC','Replication',0,0,0),
			('HADR_GROUP_COMMIT','Replication',0,0,0),
			('HADR_LOGCAPTURE_SYNC','Replication',0,0,0),
			('HADR_LOGCAPTURE_WAIT','Replication',1,1,1),
			('HADR_LOGPROGRESS_SYNC','Replication',0,0,0),
			('HADR_NOTIFICATION_DEQUEUE','Replication',1,1,1),
			('HADR_NOTIFICATION_WORKER_EXCLUSIVE_ACCESS','Replication',0,0,0),
			('HADR_NOTIFICATION_WORKER_STARTUP_SYNC','Replication',0,0,0),
			('HADR_NOTIFICATION_WORKER_TERMINATION_SYNC','Replication',0,0,0),
			('HADR_PARTNER_SYNC','Replication',0,0,0),
			('HADR_READ_ALL_NETWORKS','Replication',0,0,0),
			('HADR_RECOVERY_WAIT_FOR_CONNECTION','Replication',0,0,0),
			('HADR_RECOVERY_WAIT_FOR_UNDO','Replication',0,0,0),
			('HADR_REPLICAINFO_SYNC','Replication',0,0,0),
			('HADR_SEEDING_CANCELLATION','Replication',0,0,0),
			('HADR_SEEDING_FILE_LIST','Replication',0,0,0),
			('HADR_SEEDING_LIMIT_BACKUPS','Replication',0,0,0),
			('HADR_SEEDING_SYNC_COMPLETION','Replication',0,0,0),
			('HADR_SEEDING_TIMEOUT_TASK','Replication',0,0,0),
			('HADR_SEEDING_WAIT_FOR_COMPLETION','Replication',0,0,0),
			('HADR_SYNC_COMMIT','Replication',0,0,0),
			('HADR_SYNCHRONIZING_THROTTLE','Replication',0,0,0),
			('HADR_TDS_LISTENER_SYNC','Replication',0,0,0),
			('HADR_TDS_LISTENER_SYNC_PROCESSING','Replication',0,0,0),
			('HADR_THROTTLE_LOG_RATE_GOVERNOR','Log Rate Governor',0,0,0),
			('HADR_TIMER_TASK','Replication',1,1,1),
			('HADR_TRANSPORT_DBRLIST','Replication',0,0,0),
			('HADR_TRANSPORT_FLOW_CONTROL','Replication',0,0,0),
			('HADR_TRANSPORT_SESSION','Replication',0,0,0),
			('HADR_WORK_POOL','Replication',0,0,0),
			('HADR_WORK_QUEUE','Replication',1,1,1),
			('HADR_XRF_STACK_ACCESS','Replication',0,0,0),
			('INSTANCE_LOG_RATE_GOVERNOR','Log Rate Governor',0,0,0),
			('IO_COMPLETION','Other Disk IO',0,0,0),
			('IO_QUEUE_LIMIT','Other Disk IO',0,0,0),
			('IO_RETRY','Other Disk IO',0,0,0),
			('KSOURCE_WAKEUP','Other',0,0,0),
			('LATCH_DT','Latch',0,0,0),
			('LATCH_EX','Latch',0,0,0),
			('LATCH_KP','Latch',0,0,0),
			('LATCH_NL','Latch',0,0,0),
			('LATCH_SH','Latch',0,0,0),
			('LATCH_UP','Latch',0,0,0),
			('LAZYWRITER_SLEEP','Idle',1,1,1),
			('LCK_M_BU','Lock',0,0,0),
			('LCK_M_BU_ABORT_BLOCKERS','Lock',0,0,0),
			('LCK_M_BU_LOW_PRIORITY','Lock',0,0,0),
			('LCK_M_IS','Lock',0,0,0),
			('LCK_M_IS_ABORT_BLOCKERS','Lock',0,0,0),
			('LCK_M_IS_LOW_PRIORITY','Lock',0,0,0),
			('LCK_M_IU','Lock',0,0,0),
			('LCK_M_IU_ABORT_BLOCKERS','Lock',0,0,0),
			('LCK_M_IU_LOW_PRIORITY','Lock',0,0,0),
			('LCK_M_IX','Lock',0,0,0),
			('LCK_M_IX_ABORT_BLOCKERS','Lock',0,0,0),
			('LCK_M_IX_LOW_PRIORITY','Lock',0,0,0),
			('LCK_M_RIn_NL','Lock',0,0,0),
			('LCK_M_RIn_NL_ABORT_BLOCKERS','Lock',0,0,0),
			('LCK_M_RIn_NL_LOW_PRIORITY','Lock',0,0,0),
			('LCK_M_RIn_S','Lock',0,0,0),
			('LCK_M_RIn_S_ABORT_BLOCKERS','Lock',0,0,0),
			('LCK_M_RIn_S_LOW_PRIORITY','Lock',0,0,0),
			('LCK_M_RIn_U','Lock',0,0,0),
			('LCK_M_RIn_U_ABORT_BLOCKERS','Lock',0,0,0),
			('LCK_M_RIn_U_LOW_PRIORITY','Lock',0,0,0),
			('LCK_M_RIn_X','Lock',0,0,0),
			('LCK_M_RIn_X_ABORT_BLOCKERS','Lock',0,0,0),
			('LCK_M_RIn_X_LOW_PRIORITY','Lock',0,0,0),
			('LCK_M_RS_S','Lock',0,0,0),
			('LCK_M_RS_S_ABORT_BLOCKERS','Lock',0,0,0),
			('LCK_M_RS_S_LOW_PRIORITY','Lock',0,0,0),
			('LCK_M_RS_U','Lock',0,0,0),
			('LCK_M_RS_U_ABORT_BLOCKERS','Lock',0,0,0),
			('LCK_M_RS_U_LOW_PRIORITY','Lock',0,0,0),
			('LCK_M_RX_S','Lock',0,0,0),
			('LCK_M_RX_S_ABORT_BLOCKERS','Lock',0,0,0),
			('LCK_M_RX_S_LOW_PRIORITY','Lock',0,0,0),
			('LCK_M_RX_U','Lock',0,0,0),
			('LCK_M_RX_U_ABORT_BLOCKERS','Lock',0,0,0),
			('LCK_M_RX_U_LOW_PRIORITY','Lock',0,0,0),
			('LCK_M_RX_X','Lock',0,0,0),
			('LCK_M_RX_X_ABORT_BLOCKERS','Lock',0,0,0),
			('LCK_M_RX_X_LOW_PRIORITY','Lock',0,0,0),
			('LCK_M_S','Lock',0,0,0),
			('LCK_M_S_ABORT_BLOCKERS','Lock',0,0,0),
			('LCK_M_S_LOW_PRIORITY','Lock',0,0,0),
			('LCK_M_SCH_M','Lock',0,0,0),
			('LCK_M_SCH_M_ABORT_BLOCKERS','Lock',0,0,0),
			('LCK_M_SCH_M_LOW_PRIORITY','Lock',0,0,0),
			('LCK_M_SCH_S','Lock',0,0,0),
			('LCK_M_SCH_S_ABORT_BLOCKERS','Lock',0,0,0),
			('LCK_M_SCH_S_LOW_PRIORITY','Lock',0,0,0),
			('LCK_M_SIU','Lock',0,0,0),
			('LCK_M_SIU_ABORT_BLOCKERS','Lock',0,0,0),
			('LCK_M_SIU_LOW_PRIORITY','Lock',0,0,0),
			('LCK_M_SIX','Lock',0,0,0),
			('LCK_M_SIX_ABORT_BLOCKERS','Lock',0,0,0),
			('LCK_M_SIX_LOW_PRIORITY','Lock',0,0,0),
			('LCK_M_U','Lock',0,0,0),
			('LCK_M_U_ABORT_BLOCKERS','Lock',0,0,0),
			('LCK_M_U_LOW_PRIORITY','Lock',0,0,0),
			('LCK_M_UIX','Lock',0,0,0),
			('LCK_M_UIX_ABORT_BLOCKERS','Lock',0,0,0),
			('LCK_M_UIX_LOW_PRIORITY','Lock',0,0,0),
			('LCK_M_X','Lock',0,0,0),
			('LCK_M_X_ABORT_BLOCKERS','Lock',0,0,0),
			('LCK_M_X_LOW_PRIORITY','Lock',0,0,0),
			('LOG_RATE_GOVERNOR','Tran Log IO',0,0,0),
			('LOGBUFFER','Tran Log IO',0,0,0),
			('LOGMGR','Tran Log IO',0,0,0),
			('LOGMGR_FLUSH','Tran Log IO',0,0,0),
			('LOGMGR_PMM_LOG','Tran Log IO',0,0,0),
			('LOGMGR_QUEUE','Idle',1,1,1),
			('LOGMGR_RESERVE_APPEND','Tran Log IO',0,0,0),
			('MEMORY_ALLOCATION_EXT','Memory',0,1,0),
			('MEMORY_GRANT_UPDATE','Memory',0,0,0),
			('MSQL_XACT_MGR_MUTEX','Transaction',0,0,0),
			('MSQL_XACT_MUTEX','Transaction',0,0,0),
			('MSSEARCH','Full Text Search',0,0,0),
			('NET_WAITFOR_PACKET','Network IO',0,0,0),
			('ONDEMAND_TASK_QUEUE','Idle',1,1,1),
			('PAGEIOLATCH_DT','Buffer IO',0,0,0),
			('PAGEIOLATCH_EX','Buffer IO',0,0,0),
			('PAGEIOLATCH_KP','Buffer IO',0,0,0),
			('PAGEIOLATCH_NL','Buffer IO',0,0,0),
			('PAGEIOLATCH_SH','Buffer IO',0,0,0),
			('PAGEIOLATCH_UP','Buffer IO',0,0,0),
			('PAGELATCH_DT','Buffer Latch',0,0,0),
			('PAGELATCH_EX','Buffer Latch',0,0,0),
			('PAGELATCH_KP','Buffer Latch',0,0,0),
			('PAGELATCH_NL','Buffer Latch',0,0,0),
			('PAGELATCH_SH','Buffer Latch',0,0,0),
			('PAGELATCH_UP','Buffer Latch',0,0,0),
			('PARALLEL_REDO_DRAIN_WORKER','Replication',1,1,1),
			('PARALLEL_REDO_FLOW_CONTROL','Replication',0,0,0),
			('PARALLEL_REDO_LOG_CACHE','Replication',1,1,1),
			('PARALLEL_REDO_TRAN_LIST','Replication',1,1,1),
			('PARALLEL_REDO_TRAN_TURN','Replication',1,1,1),
			('PARALLEL_REDO_WORKER_SYNC','Replication',1,1,1),
			('PARALLEL_REDO_WORKER_WAIT_WORK','Replication',1,1,1),
			('POOL_LOG_RATE_GOVERNOR','Log Rate Governor',0,0,0),
			('PREEMPTIVE_ABR','Preemptive',0,0,0),
			('PREEMPTIVE_CLOSEBACKUPMEDIA','Preemptive',0,0,0),
			('PREEMPTIVE_CLOSEBACKUPTAPE','Preemptive',0,0,0),
			('PREEMPTIVE_CLOSEBACKUPVDIDEVICE','Preemptive',0,0,0),
			('PREEMPTIVE_CLUSAPI_CLUSTERRESOURCECONTROL','Preemptive',0,0,0),
			('PREEMPTIVE_COM_COCREATEINSTANCE','Preemptive',0,0,0),
			('PREEMPTIVE_COM_COGETCLASSOBJECT','Preemptive',0,0,0),
			('PREEMPTIVE_COM_CREATEACCESSOR','Preemptive',0,0,0),
			('PREEMPTIVE_COM_DELETEROWS','Preemptive',0,0,0),
			('PREEMPTIVE_COM_GETCOMMANDTEXT','Preemptive',0,0,0),
			('PREEMPTIVE_COM_GETDATA','Preemptive',0,0,0),
			('PREEMPTIVE_COM_GETNEXTROWS','Preemptive',0,0,0),
			('PREEMPTIVE_COM_GETRESULT','Preemptive',0,0,0),
			('PREEMPTIVE_COM_GETROWSBYBOOKMARK','Preemptive',0,0,0),
			('PREEMPTIVE_COM_LBFLUSH','Preemptive',0,0,0),
			('PREEMPTIVE_COM_LBLOCKREGION','Preemptive',0,0,0),
			('PREEMPTIVE_COM_LBREADAT','Preemptive',0,0,0),
			('PREEMPTIVE_COM_LBSETSIZE','Preemptive',0,0,0),
			('PREEMPTIVE_COM_LBSTAT','Preemptive',0,0,0),
			('PREEMPTIVE_COM_LBUNLOCKREGION','Preemptive',0,0,0),
			('PREEMPTIVE_COM_LBWRITEAT','Preemptive',0,0,0),
			('PREEMPTIVE_COM_QUERYINTERFACE','Preemptive',0,0,0),
			('PREEMPTIVE_COM_RELEASE','Preemptive',0,0,0),
			('PREEMPTIVE_COM_RELEASEACCESSOR','Preemptive',0,0,0),
			('PREEMPTIVE_COM_RELEASEROWS','Preemptive',0,0,0),
			('PREEMPTIVE_COM_RELEASESESSION','Preemptive',0,0,0),
			('PREEMPTIVE_COM_RESTARTPOSITION','Preemptive',0,0,0),
			('PREEMPTIVE_COM_SEQSTRMREAD','Preemptive',0,0,0),
			('PREEMPTIVE_COM_SEQSTRMREADANDWRITE','Preemptive',0,0,0),
			('PREEMPTIVE_COM_SETDATAFAILURE','Preemptive',0,0,0),
			('PREEMPTIVE_COM_SETPARAMETERINFO','Preemptive',0,0,0),
			('PREEMPTIVE_COM_SETPARAMETERPROPERTIES','Preemptive',0,0,0),
			('PREEMPTIVE_COM_STRMLOCKREGION','Preemptive',0,0,0),
			('PREEMPTIVE_COM_STRMSEEKANDREAD','Preemptive',0,0,0),
			('PREEMPTIVE_COM_STRMSEEKANDWRITE','Preemptive',0,0,0),
			('PREEMPTIVE_COM_STRMSETSIZE','Preemptive',0,0,0),
			('PREEMPTIVE_COM_STRMSTAT','Preemptive',0,0,0),
			('PREEMPTIVE_COM_STRMUNLOCKREGION','Preemptive',0,0,0),
			('PREEMPTIVE_CONSOLEWRITE','Preemptive',0,0,0),
			('PREEMPTIVE_CREATEPARAM','Preemptive',0,0,0),
			('PREEMPTIVE_DEBUG','Preemptive',0,0,0),
			('PREEMPTIVE_DFSADDLINK','Preemptive',0,0,0),
			('PREEMPTIVE_DFSLINKEXISTCHECK','Preemptive',0,0,0),
			('PREEMPTIVE_DFSLINKHEALTHCHECK','Preemptive',0,0,0),
			('PREEMPTIVE_DFSREMOVELINK','Preemptive',0,0,0),
			('PREEMPTIVE_DFSREMOVEROOT','Preemptive',0,0,0),
			('PREEMPTIVE_DFSROOTFOLDERCHECK','Preemptive',0,0,0),
			('PREEMPTIVE_DFSROOTINIT','Preemptive',0,0,0),
			('PREEMPTIVE_DFSROOTSHARECHECK','Preemptive',0,0,0),
			('PREEMPTIVE_DTC_ABORT','Preemptive',0,0,0),
			('PREEMPTIVE_DTC_ABORTREQUESTDONE','Preemptive',0,0,0),
			('PREEMPTIVE_DTC_BEGINTRANSACTION','Preemptive',0,0,0),
			('PREEMPTIVE_DTC_COMMITREQUESTDONE','Preemptive',0,0,0),
			('PREEMPTIVE_DTC_ENLIST','Preemptive',0,0,0),
			('PREEMPTIVE_DTC_PREPAREREQUESTDONE','Preemptive',0,0,0),
			('PREEMPTIVE_FILESIZEGET','Preemptive',0,0,0),
			('PREEMPTIVE_FSAOLEDB_ABORTTRANSACTION','Preemptive',0,0,0),
			('PREEMPTIVE_FSAOLEDB_COMMITTRANSACTION','Preemptive',0,0,0),
			('PREEMPTIVE_FSAOLEDB_STARTTRANSACTION','Preemptive',0,0,0),
			('PREEMPTIVE_FSRECOVER_UNCONDITIONALUNDO','Preemptive',0,0,0),
			('PREEMPTIVE_GETRMINFO','Preemptive',0,0,0),
			('PREEMPTIVE_HADR_LEASE_MECHANISM','Preemptive',1,1,1),
			('PREEMPTIVE_HTTP_EVENT_WAIT','Preemptive',0,0,0),
			('PREEMPTIVE_HTTP_REQUEST','Preemptive',0,0,0),
			('PREEMPTIVE_LOCKMONITOR','Preemptive',0,0,0),
			('PREEMPTIVE_MSS_RELEASE','Preemptive',0,0,0),
			('PREEMPTIVE_ODBCOPS','Preemptive',0,0,0),
			('PREEMPTIVE_OLE_UNINIT','Preemptive',0,0,0),
			('PREEMPTIVE_OLEDB_ABORTORCOMMITTRAN','Preemptive',0,0,0),
			('PREEMPTIVE_OLEDB_ABORTTRAN','Preemptive',0,0,0),
			('PREEMPTIVE_OLEDB_GETDATASOURCE','Preemptive',0,0,0),
			('PREEMPTIVE_OLEDB_GETLITERALINFO','Preemptive',0,0,0),
			('PREEMPTIVE_OLEDB_GETPROPERTIES','Preemptive',0,0,0),
			('PREEMPTIVE_OLEDB_GETPROPERTYINFO','Preemptive',0,0,0),
			('PREEMPTIVE_OLEDB_GETSCHEMALOCK','Preemptive',0,0,0),
			('PREEMPTIVE_OLEDB_JOINTRANSACTION','Preemptive',0,0,0),
			('PREEMPTIVE_OLEDB_RELEASE','Preemptive',0,0,0),
			('PREEMPTIVE_OLEDB_SETPROPERTIES','Preemptive',0,0,0),
			('PREEMPTIVE_OLEDBOPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_ACCEPTSECURITYCONTEXT','Preemptive',0,0,0),
			('PREEMPTIVE_OS_ACQUIRECREDENTIALSHANDLE','Preemptive',0,0,0),
			('PREEMPTIVE_OS_AUTHENTICATIONOPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_AUTHORIZATIONOPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_AUTHZGETINFORMATIONFROMCONTEXT','Preemptive',0,0,0),
			('PREEMPTIVE_OS_AUTHZINITIALIZECONTEXTFROMSID','Preemptive',0,0,0),
			('PREEMPTIVE_OS_AUTHZINITIALIZERESOURCEMANAGER','Preemptive',0,0,0),
			('PREEMPTIVE_OS_BACKUPREAD','Preemptive',0,0,0),
			('PREEMPTIVE_OS_CLOSEHANDLE','Preemptive',0,0,0),
			('PREEMPTIVE_OS_CLUSTEROPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_COMOPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_COMPLETEAUTHTOKEN','Preemptive',0,0,0),
			('PREEMPTIVE_OS_COPYFILE','Preemptive',0,0,0),
			('PREEMPTIVE_OS_CREATEDIRECTORY','Preemptive',0,0,0),
			('PREEMPTIVE_OS_CREATEFILE','Preemptive',0,0,0),
			('PREEMPTIVE_OS_CRYPTACQUIRECONTEXT','Preemptive',0,0,0),
			('PREEMPTIVE_OS_CRYPTIMPORTKEY','Preemptive',0,0,0),
			('PREEMPTIVE_OS_CRYPTOPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_DECRYPTMESSAGE','Preemptive',0,0,0),
			('PREEMPTIVE_OS_DELETEFILE','Preemptive',0,0,0),
			('PREEMPTIVE_OS_DELETESECURITYCONTEXT','Preemptive',0,0,0),
			('PREEMPTIVE_OS_DEVICEIOCONTROL','Preemptive',0,0,0),
			('PREEMPTIVE_OS_DEVICEOPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_DIRSVC_NETWORKOPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_DISCONNECTNAMEDPIPE','Preemptive',0,0,0),
			('PREEMPTIVE_OS_DOMAINSERVICESOPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_DSGETDCNAME','Preemptive',0,0,0),
			('PREEMPTIVE_OS_DTCOPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_ENCRYPTMESSAGE','Preemptive',0,0,0),
			('PREEMPTIVE_OS_FILEOPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_FINDFILE','Preemptive',0,0,0),
			('PREEMPTIVE_OS_FLUSHFILEBUFFERS','Preemptive',0,1,0),
			('PREEMPTIVE_OS_FORMATMESSAGE','Preemptive',0,0,0),
			('PREEMPTIVE_OS_FREECREDENTIALSHANDLE','Preemptive',0,0,0),
			('PREEMPTIVE_OS_FREELIBRARY','Preemptive',0,0,0),
			('PREEMPTIVE_OS_GENERICOPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_GETADDRINFO','Preemptive',0,0,0),
			('PREEMPTIVE_OS_GETCOMPRESSEDFILESIZE','Preemptive',0,0,0),
			('PREEMPTIVE_OS_GETDISKFREESPACE','Preemptive',0,0,0),
			('PREEMPTIVE_OS_GETFILEATTRIBUTES','Preemptive',0,0,0),
			('PREEMPTIVE_OS_GETFILESIZE','Preemptive',0,0,0),
			('PREEMPTIVE_OS_GETFINALFILEPATHBYHANDLE','Preemptive',0,0,0),
			('PREEMPTIVE_OS_GETLONGPATHNAME','Preemptive',0,0,0),
			('PREEMPTIVE_OS_GETPROCADDRESS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_GETVOLUMENAMEFORVOLUMEMOUNTPOINT','Preemptive',0,0,0),
			('PREEMPTIVE_OS_GETVOLUMEPATHNAME','Preemptive',0,0,0),
			('PREEMPTIVE_OS_INITIALIZESECURITYCONTEXT','Preemptive',0,0,0),
			('PREEMPTIVE_OS_LIBRARYOPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_LOADLIBRARY','Preemptive',0,0,0),
			('PREEMPTIVE_OS_LOGONUSER','Preemptive',0,0,0),
			('PREEMPTIVE_OS_LOOKUPACCOUNTSID','Preemptive',0,0,0),
			('PREEMPTIVE_OS_MESSAGEQUEUEOPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_MOVEFILE','Preemptive',0,0,0),
			('PREEMPTIVE_OS_NETGROUPGETUSERS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_NETLOCALGROUPGETMEMBERS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_NETUSERGETGROUPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_NETUSERGETLOCALGROUPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_NETUSERMODALSGET','Preemptive',0,0,0),
			('PREEMPTIVE_OS_NETVALIDATEPASSWORDPOLICY','Preemptive',0,0,0),
			('PREEMPTIVE_OS_NETVALIDATEPASSWORDPOLICYFREE','Preemptive',0,0,0),
			('PREEMPTIVE_OS_OPENDIRECTORY','Preemptive',0,0,0),
			('PREEMPTIVE_OS_PDH_WMI_INIT','Preemptive',0,0,0),
			('PREEMPTIVE_OS_PIPEOPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_PROCESSOPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_QUERYCONTEXTATTRIBUTES','Preemptive',0,0,0),
			('PREEMPTIVE_OS_QUERYREGISTRY','Preemptive',0,0,0),
			('PREEMPTIVE_OS_QUERYSECURITYCONTEXTTOKEN','Preemptive',0,0,0),
			('PREEMPTIVE_OS_REMOVEDIRECTORY','Preemptive',0,0,0),
			('PREEMPTIVE_OS_REPORTEVENT','Preemptive',0,0,0),
			('PREEMPTIVE_OS_REVERTTOSELF','Preemptive',0,0,0),
			('PREEMPTIVE_OS_RSFXDEVICEOPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_SECURITYOPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_SERVICEOPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_SETENDOFFILE','Preemptive',0,0,0),
			('PREEMPTIVE_OS_SETFILEPOINTER','Preemptive',0,0,0),
			('PREEMPTIVE_OS_SETFILEVALIDDATA','Preemptive',0,0,0),
			('PREEMPTIVE_OS_SETNAMEDSECURITYINFO','Preemptive',0,0,0),
			('PREEMPTIVE_OS_SQLCLROPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_SQMLAUNCH','Preemptive',0,0,0),
			('PREEMPTIVE_OS_VERIFYSIGNATURE','Preemptive',0,0,0),
			('PREEMPTIVE_OS_VERIFYTRUST','Preemptive',0,0,0),
			('PREEMPTIVE_OS_VSSOPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_WAITFORSINGLEOBJECT','Preemptive',0,0,0),
			('PREEMPTIVE_OS_WINSOCKOPS','Preemptive',0,0,0),
			('PREEMPTIVE_OS_WRITEFILE','Preemptive',0,0,0),
			('PREEMPTIVE_OS_WRITEFILEGATHER','Preemptive',0,0,0),
			('PREEMPTIVE_OS_WSASETLASTERROR','Preemptive',0,0,0),
			('PREEMPTIVE_REENLIST','Preemptive',0,0,0),
			('PREEMPTIVE_RESIZELOG','Preemptive',0,0,0),
			('PREEMPTIVE_ROLLFORWARDREDO','Preemptive',0,0,0),
			('PREEMPTIVE_ROLLFORWARDUNDO','Preemptive',0,0,0),
			('PREEMPTIVE_SB_STOPENDPOINT','Preemptive',0,0,0),
			('PREEMPTIVE_SERVER_STARTUP','Preemptive',0,0,0),
			('PREEMPTIVE_SETRMINFO','Preemptive',0,0,0),
			('PREEMPTIVE_SHAREDMEM_GETDATA','Preemptive',0,0,0),
			('PREEMPTIVE_SNIOPEN','Preemptive',0,0,0),
			('PREEMPTIVE_SOSHOST','Preemptive',0,0,0),
			('PREEMPTIVE_SOSTESTING','Preemptive',0,0,0),
			('PREEMPTIVE_SP_SERVER_DIAGNOSTICS','Preemptive',1,1,1),
			('PREEMPTIVE_STARTRM','Preemptive',0,0,0),
			('PREEMPTIVE_STREAMFCB_CHECKPOINT','Preemptive',0,0,0),
			('PREEMPTIVE_STREAMFCB_RECOVER','Preemptive',0,0,0),
			('PREEMPTIVE_STRESSDRIVER','Preemptive',0,0,0),
			('PREEMPTIVE_TESTING','Preemptive',0,0,0),
			('PREEMPTIVE_TRANSIMPORT','Preemptive',0,0,0),
			('PREEMPTIVE_UNMARSHALPROPAGATIONTOKEN','Preemptive',0,0,0),
			('PREEMPTIVE_VSS_CREATESNAPSHOT','Preemptive',0,0,0),
			('PREEMPTIVE_VSS_CREATEVOLUMESNAPSHOT','Preemptive',0,0,0),
			('PREEMPTIVE_XE_CALLBACKEXECUTE','Preemptive',0,0,0),
			('PREEMPTIVE_XE_CX_FILE_OPEN','Preemptive',0,0,0),
			('PREEMPTIVE_XE_CX_HTTP_CALL','Preemptive',0,0,0),
			('PREEMPTIVE_XE_DISPATCHER','Preemptive',1,1,1),
			('PREEMPTIVE_XE_ENGINEINIT','Preemptive',0,0,0),
			('PREEMPTIVE_XE_GETTARGETSTATE','Preemptive',0,1,0),
			('PREEMPTIVE_XE_SESSIONCOMMIT','Preemptive',0,0,0),
			('PREEMPTIVE_XE_TARGETFINALIZE','Preemptive',0,0,0),
			('PREEMPTIVE_XE_TARGETINIT','Preemptive',0,0,0),
			('PREEMPTIVE_XE_TIMERRUN','Preemptive',0,0,0),
			('PREEMPTIVE_XETESTING','Preemptive',0,0,0),
			('PVS_PREALLOCATE','Other',0,1,0),
			('PWAIT_ALL_COMPONENTS_INITIALIZED','Other',0,1,0),
			('PWAIT_DIRECTLOGCONSUMER_GETNEXT','Other',0,1,0),
			('PWAIT_EXTENSIBILITY_CLEANUP_TASK','Other',0,1,0),
			('PWAIT_HADR_ACTION_COMPLETED','Replication',0,0,0),
			('PWAIT_HADR_CHANGE_NOTIFIER_TERMINATION_SYNC','Replication',0,0,0),
			('PWAIT_HADR_CLUSTER_INTEGRATION','Replication',0,0,0),
			('PWAIT_HADR_FAILOVER_COMPLETED','Replication',0,0,0),
			('PWAIT_HADR_JOIN','Replication',0,0,0),
			('PWAIT_HADR_OFFLINE_COMPLETED','Replication',0,0,0),
			('PWAIT_HADR_ONLINE_COMPLETED','Replication',0,0,0),
			('PWAIT_HADR_POST_ONLINE_COMPLETED','Replication',0,0,0),
			('PWAIT_HADR_SERVER_READY_CONNECTIONS','Replication',0,0,0),
			('PWAIT_HADR_WORKITEM_COMPLETED','Replication',0,0,0),
			('PWAIT_HADRSIM','Replication',0,0,0),
			('PWAIT_RESOURCE_SEMAPHORE_FT_PARALLEL_QUERY_SYNC','Full Text Search',0,0,0),
			('QDS_ASYNC_QUEUE','Other',1,1,1),
			('QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP','Other',1,1,1),
			('QDS_PERSIST_TASK_MAIN_LOOP_SLEEP','Other',1,1,1),
			('QDS_SHUTDOWN_QUEUE','Other',1,1,1),
			('QUERY_TRACEOUT','Tracing',0,0,0),
			('REDO_THREAD_PENDING_WORK','Other',1,1,1),
			('REPL_CACHE_ACCESS','Replication',0,0,0),
			('REPL_HISTORYCACHE_ACCESS','Replication',0,0,0),
			('REPL_SCHEMA_ACCESS','Replication',0,0,0),
			('REPL_TRANFSINFO_ACCESS','Replication',0,0,0),
			('REPL_TRANHASHTABLE_ACCESS','Replication',0,0,0),
			('REPL_TRANTEXTINFO_ACCESS','Replication',0,0,0),
			('REPLICA_WRITES','Replication',0,0,0),
			('REQUEST_FOR_DEADLOCK_SEARCH','Idle',1,1,1),
			('RESERVED_MEMORY_ALLOCATION_EXT','Memory',0,0,0),
			('RESOURCE_QUEUE','Other',0,0,0),
			('RESOURCE_SEMAPHORE','Memory',0,0,0),
			('RESOURCE_SEMAPHORE_QUERY_COMPILE','Compilation',0,0,0),
			('SERVER_IDLE_CHECK','Idle',0,1,0),
			('SLEEP_BPOOL_FLUSH','Idle',0,1,0),
			('SLEEP_BUFFERPOOL_HELPLW','Idle',0,0,0),
			('SLEEP_DBSTARTUP','Idle',0,1,0),
			('SLEEP_DCOMSTARTUP','Idle',0,1,0),
			('SLEEP_MASTERDBREADY','Idle',0,1,0),
			('SLEEP_MASTERMDREADY','Idle',0,1,0),
			('SLEEP_MASTERUPGRADED','Idle',0,1,0),
			('SLEEP_MEMORYPOOL_ALLOCATEPAGES','Idle',0,0,0),
			('SLEEP_MSDBSTARTUP','Idle',0,1,0),
			('SLEEP_RETRY_VIRTUALALLOC','Idle',0,0,0),
			('SLEEP_SYSTEMTASK','Idle',1,1,1),
			('SLEEP_TASK','Idle',1,1,1),
			('SLEEP_TEMPDBSTARTUP','Idle',0,1,0),
			('SLEEP_WORKSPACE_ALLOCATEPAGE','Idle',0,0,0),
			('SOS_SCHEDULER_YIELD','CPU',0,0,0),
			('SOS_WORK_DISPATCHER','Idle',1,1,1),
			('SP_SERVER_DIAGNOSTICS_SLEEP','Other',1,1,1),
			('SQLCLR_APPDOMAIN','SQL CLR',0,0,0),
			('SQLCLR_ASSEMBLY','SQL CLR',0,0,0),
			('SQLCLR_DEADLOCK_DETECTION','SQL CLR',0,0,0),
			('SQLCLR_QUANTUM_PUNISHMENT','SQL CLR',0,0,0),
			('SQLTRACE_BUFFER_FLUSH','Idle',1,1,1),
			('SQLTRACE_FILE_BUFFER','Tracing',0,0,0),
			('SQLTRACE_FILE_READ_IO_COMPLETION','Tracing',0,0,0),
			('SQLTRACE_FILE_WRITE_IO_COMPLETION','Tracing',0,0,0),
			('SQLTRACE_INCREMENTAL_FLUSH_SLEEP','Idle',1,1,1),
			('SQLTRACE_PENDING_BUFFER_WRITERS','Tracing',0,0,0),
			('SQLTRACE_SHUTDOWN','Tracing',0,0,0),
			('SQLTRACE_WAIT_ENTRIES','Idle',0,1,0),
			('THREADPOOL','Worker Thread',0,0,0),
			('TRACE_EVTNOTIF','Tracing',0,0,0),
			('TRACEWRITE','Tracing',0,0,0),
			('TRAN_MARKLATCH_DT','Transaction',0,0,0),
			('TRAN_MARKLATCH_EX','Transaction',0,0,0),
			('TRAN_MARKLATCH_KP','Transaction',0,0,0),
			('TRAN_MARKLATCH_NL','Transaction',0,0,0),
			('TRAN_MARKLATCH_SH','Transaction',0,0,0),
			('TRAN_MARKLATCH_UP','Transaction',0,0,0),
			('TRANSACTION_MUTEX','Transaction',0,0,0),
			('UCS_SESSION_REGISTRATION','Other',1,1,1),
			('VDI_CLIENT_OTHER','Idle',0,1,0),
			('WAIT_FOR_RESULTS','User Wait',0,0,0),
			('WAIT_XTP_CKPT_CLOSE','Other',0,1,0),
			('WAIT_XTP_OFFLINE_CKPT_NEW_LOG','Other',1,1,1),
			('WAIT_XTP_RECOVERY','Other',0,1,0),
			('WAIT_XTP_HOST_WAIT','Other',0,1,0),
			('WAITFOR','User Wait',1,1,1),
			('WAITFOR_TASKSHUTDOWN','Idle',1,1,1),
			('WRITE_COMPLETION','Other Disk IO',0,0,0),
			('WRITELOG','Tran Log IO',0,0,0),
			('XACT_OWN_TRANSACTION','Transaction',0,0,0),
			('XACT_RECLAIM_SESSION','Transaction',0,0,0),
			('XACTLOCKINFO','Transaction',0,0,0),
			('XACTWORKSPACE_MUTEX','Transaction',0,0,0),
			('XE_DISPATCHER_JOIN','Other',0,1,0),
			('XE_DISPATCHER_WAIT','Idle',1,1,1),
			('XE_LIVE_TARGET_TVF','Other',1,1,1),
			('XE_TIMER_EVENT','Idle',1,1,1)
	) as Waits (WaitType, WaitCategory, Ignorable, IgnorableOnPerCoreMetric, IgnorableOnDashboard)
	where WaitType not in (select WaitType from [dbo].[BlitzFirst_WaitStats_Categories]);
END
GO
