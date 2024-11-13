/*
	Version:		2024-11-13
	Date:			2024-11-13 - Enhancement#4 - Get Max Server Memory in dbo.all_server_stable_info
					2024-11-12 - Enhancement#3 - Add table dbo.all_server_stable_info_history
					2024-10-22 - Enhancement#51 - Add few objects required for DBA Inventory & Alerting
					2024-08-07 - Enhancement#45 - Add Preventive Triggers on dbo.instance_details to avoid mistakes
					2024-06-05 - Enhancement#42 - Get [avg_disk_wait_ms]
					2024-04-26 - Enhancement#40 - Change Retention of dbo.all_server_volatile_info_history to 15 Days
					2024-02-21 - Enhancement#30 - Add flag for choice of MemoryOptimized Tables 
					2023-10-16 - Enhancement#5 - Dashboard for AlwaysOn Latency
					2023-07-14 - Enhancement#268 - Add tables sql_agent_job_stats & memory_clerks in Collection Latency Dashboard
					2023-06-16 - Enhancement#262 - Add is_enabled on Inventory.DBA.dbo.instance_details
					2022-03-31 - Enhancement#227 - Add CollectionTime of Each Table Data

	*** Self Pre Steps ***
	----------------------
	1) Credential Manager should be installed on Inventory Server in case of Windows Authentication does not work on SQLServers
	2) SQLMonitor should be present

	*** Steps in this Script ****
	-----------------------------
	1) Alter inventory database with [MEMORY_OPTIMIZED_ELEVATE_TO_SNAPSHOT]
	2) Alter inventory database with MemoryOptimized filegroup
	3) Alter inventory database with MemoryOptimized filegroup file
	4) Drop all self created tables
	5) Create table dbo.all_server_stable_info
	6) Create table dbo.all_server_stable_info_history
	7) Create table dbo.all_server_volatile_info__staging
	8) Create table dbo.all_server_volatile_info
	9) Create table dbo.all_server_collection_latency_info
	10) Create table dbo.all_server_volatile_info_history
	11) Create table dbo.sql_agent_jobs_all_servers
	12) Create table dbo.sql_agent_jobs_all_servers__staging
	13) Create table dbo.disk_space_all_servers
	14) Create table dbo.disk_space_all_servers__staging
	15) Create table dbo.log_space_consumers_all_servers
	16) Create table dbo.log_space_consumers_all_servers__staging
	17) Create table dbo.tempdb_space_usage_all_servers
	18) Create table dbo.tempdb_space_usage_all_servers__staging
	19) Create table dbo.ag_health_state_all_servers
	20) Create table dbo.ag_health_state_all_servers__staging
	21) Add dbo.purge_table entry for dbo.all_server_stable_info_history
	22) Create procedure dbo.usp_populate__all_server_stable_info_history
	23) Add dbo.purge_table entry for dbo.all_server_volatile_info_history
	24) Create procedure dbo.usp_populate__all_server_volatile_info_history
	25) Create view dbo.vw_all_server_info
	26) Alter multiple tables and add few columns
	27) Create table dbo.instance_details_history
	28) Create trigger tgr_dml__instance_details on dbo.instance_details
	29) Create trigger tgr_dml__instance_details__prevent_bulk_udpate on dbo.instance_details
	30) Add dbo.purge_table entry for dbo.instance_details_history
	31) Create table dbo.backups_all_servers
	32) Create table dbo.backups_all_servers__staging
	33) Create table dbo.services_all_servers
	34) Create table dbo.services_all_servers__staging
	35) Create table dbo.alert_history_all_servers
	36) Add dbo.purge_table entry for dbo.alert_history_all_servers
	37) Create table dbo.sent_alert_history_all_servers
	38) Create table dbo.alert_history_all_servers_last_actioned
	39) Create table dbo.sma_errorlog
	40) Add dbo.purge_table entry for dbo.sma_errorlog
	41) Create table dbo.sma_params

	42) Create table dbo.sma_servers
	43) Create table dbo.sma_sql_server_extended_info
	44) Create table dbo.sma_sql_server_hosts
	45) Create table dbo.sma_hadr_ag
	46) Create table dbo.sma_hadr_sql_cluster
	47) Create table dbo.sma_hadr_mirroring
	48) Create table dbo.sma_hadr_log_shipping
	49) Create table dbo.sma_hadr_transaction_replication_publishers
	50) Create table dbo.sma_applications
	51) Create table dbo.sma_applications_server_xref
	52) Create table dbo.sma_applications_database_xref
	53) Create view dbo.sma_sql_servers
	54) Create view dbo.sma_sql_servers_including_offline
	55) Create Trigger dbo.tgr_dml__fk_validation_sma_servers__server on dbo.sma_servers
	56) Create Trigger dbo.tgr_dml__sma_servers__server_owner_email__validation on dbo.sma_servers
	57) Create Trigger dbo.tgr_dml__sma_applications__email__validation on dbo.sma_applications
	58) Create table dbo.login_email_mapping
	59) Create Trigger dbo.tgr_dml__login_email_mapping__email__validation on dbo.login_email_mapping
	60) Create table dbo.all_server_login_expiry_info
	61) Create table dbo.server_login_expiry_collection_computed used for [usp_send_login_expiry_emails]
	62) Create table dbo.all_server_login_expiry_info_dashboard used for [usp_send_login_expiry_emails]
	63) Create table dbo.sma_servers_logs used for [usp_wrapper_populate_sma_sql_instance]
	64) Create table dbo.sma_wrapper_sql_server_hosts 
	65) Create view dbo.vw_all_server_logins
	66) Create table dbo.sma_server_aliases
	67) Create function dbo.fn_IsJobRunning

*/

IF APP_NAME() = 'Microsoft SQL Server Management Studio - Query'
BEGIN
	SET QUOTED_IDENTIFIER OFF;
	SET ANSI_PADDING ON;
	SET CONCAT_NULL_YIELDS_NULL ON;
	SET ANSI_WARNINGS ON;
	SET NUMERIC_ROUNDABORT OFF;
	SET ARITHABORT ON;
END
GO

IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

/* ****** 1) Alter inventory database with [MEMORY_OPTIMIZED_ELEVATE_TO_SNAPSHOT] ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '1) Alter inventory database with [MEMORY_OPTIMIZED_ELEVATE_TO_SNAPSHOT]';
DECLARE @MemoryOptimizedObjectUsage bit = 1;
IF @MemoryOptimizedObjectUsage = 1
	EXEC ('ALTER DATABASE CURRENT SET MEMORY_OPTIMIZED_ELEVATE_TO_SNAPSHOT = ON');
go

/* ****** 2) Alter inventory database with MemoryOptimized filegroup ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '2) Alter inventory database with MemoryOptimized filegroup';
DECLARE @MemoryOptimizedObjectUsage bit = 1;
if not exists (select * from sys.filegroups where name = 'MemoryOptimized') and (@MemoryOptimizedObjectUsage = 1)
	EXEC ('ALTER DATABASE CURRENT ADD FILEGROUP MemoryOptimized CONTAINS MEMORY_OPTIMIZED_DATA');
go

/* ****** 3) Alter inventory database with MemoryOptimized filegroup file ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '3) Alter inventory database with MemoryOptimized filegroup file';
DECLARE @MemoryOptimizedObjectUsage bit = 1;
if not exists (select * from sys.database_files where name = 'MemoryOptimized') and (@MemoryOptimizedObjectUsage = 1)
	EXEC ('ALTER DATABASE CURRENT ADD FILE (name=''MemoryOptimized'', filename=''E:\Data\MemoryOptimized.ndf'') TO FILEGROUP MemoryOptimized');
go

/* ****** 4) Drop all self created tables ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '4) Drop all self created tables';
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[all_server_stable_info]') AND type in (N'U'))
	DROP TABLE [dbo].[all_server_stable_info]
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[all_server_volatile_info__staging]') AND type in (N'U'))
	DROP TABLE [dbo].[all_server_volatile_info__staging]
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[all_server_volatile_info]') AND type in (N'U'))
	DROP TABLE [dbo].[all_server_volatile_info]
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[all_server_stable_info_history]') AND type in (N'U'))
	DROP TABLE [dbo].[all_server_stable_info_history]
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[all_server_volatile_info_history]') AND type in (N'U'))
	DROP TABLE [dbo].[all_server_volatile_info_history]
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[all_server_collection_latency_info]') AND type in (N'U'))
	DROP TABLE [dbo].[all_server_collection_latency_info]
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[sql_agent_jobs_all_servers]') AND type in (N'U'))
	DROP TABLE [dbo].[sql_agent_jobs_all_servers]
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[sql_agent_jobs_all_servers__staging]') AND type in (N'U'))
	DROP TABLE [dbo].[sql_agent_jobs_all_servers__staging]
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[disk_space_all_servers__staging]') AND type in (N'U'))
	DROP TABLE [dbo].[disk_space_all_servers__staging]
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[disk_space_all_servers]') AND type in (N'U'))
	DROP TABLE [dbo].[disk_space_all_servers]
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[log_space_consumers_all_servers__staging]') AND type in (N'U'))
	DROP TABLE [dbo].[log_space_consumers_all_servers__staging]
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[log_space_consumers_all_servers]') AND type in (N'U'))
	DROP TABLE [dbo].[log_space_consumers_all_servers]
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tempdb_space_usage_all_servers__staging]') AND type in (N'U'))
	DROP TABLE [dbo].[tempdb_space_usage_all_servers__staging]
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tempdb_space_usage_all_servers]') AND type in (N'U'))
	DROP TABLE [dbo].[tempdb_space_usage_all_servers]
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ag_health_state_all_servers]') AND type in (N'U'))
	DROP TABLE [dbo].[ag_health_state_all_servers]
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ag_health_state_all_servers__staging]') AND type in (N'U'))
	DROP TABLE [dbo].[ag_health_state_all_servers__staging]
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[backups_all_servers]') AND type in (N'U'))
	DROP TABLE [dbo].[backups_all_servers]
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[backups_all_servers__staging]') AND type in (N'U'))
	DROP TABLE [dbo].[backups_all_servers__staging]
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[services_all_servers]') AND type in (N'U'))
	DROP TABLE [dbo].[services_all_servers]
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[services_all_servers__staging]') AND type in (N'U'))
	DROP TABLE [dbo].[services_all_servers__staging]
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[alert_history_all_servers]') AND type in (N'U'))
	DROP TABLE [dbo].[alert_history_all_servers]
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[alert_history_all_servers_last_actioned]') AND type in (N'U'))
	DROP TABLE dbo.alert_history_all_servers_last_actioned
GO

/* ****** 5) Create table dbo.all_server_stable_info ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '5) Create table dbo.all_server_stable_info';
DECLARE @_sql NVARCHAR(MAX);
DECLARE @MemoryOptimizedObjectUsage bit = 1;

SET @_sql = '
CREATE TABLE [dbo].[all_server_stable_info]
(
	[srv_name] [varchar](125) NOT NULL,
	[at_server_name] [varchar](125) NULL,
	[machine_name] [varchar](125) NULL,
	[server_name] [varchar](125) NULL,
	[ip] [varchar](30) NULL,
	[domain] [varchar](125) NULL,
	[host_name] [varchar](125) NULL,
	[fqdn] [varchar](225) NULL,
	[host_distribution] [varchar](200),  
	[processor_name] [varchar](200),
	[product_version] [varchar](30) NULL,
	[edition] [varchar](50) NULL,
	[sqlserver_start_time_utc] [datetime2](7) NULL,
	[total_physical_memory_kb] [bigint] NULL,
	[os_start_time_utc] [datetime2](7) NULL,
	[cpu_count] [smallint] NULL,
	[scheduler_count] [smallint] NULL,
	[major_version_number] [smallint] NULL,
	[minor_version_number] [smallint] NULL,
	[max_server_memory_mb] [int] null,
	[collection_time] [datetime2] NULL default sysdatetime(),

	'+(case when @MemoryOptimizedObjectUsage = 1 then '' else '--' end)+'CONSTRAINT pk_all_server_stable_info primary key nonclustered ([srv_name])
	'+(case when @MemoryOptimizedObjectUsage = 0 then '' else '--' end)+'CONSTRAINT pk_all_server_stable_info primary key clustered ([srv_name])
)
'+(case when @MemoryOptimizedObjectUsage = 1 then '' else '--' end)+'WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);';

EXEC (@_sql);
GO

/* ****** 6) Create table dbo.all_server_stable_info_history ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '6) Create table dbo.all_server_stable_info_history';
CREATE TABLE [dbo].[all_server_stable_info_history]
(
	[collection_time] [datetime2] NULL default sysdatetime(),
	[srv_name] [varchar](125) NOT NULL,
	[at_server_name] [varchar](125) NULL,
	[machine_name] [varchar](125) NULL,
	[server_name] [varchar](125) NULL,
	[ip] [varchar](30) NULL,
	[domain] [varchar](125) NULL,
	[host_name] [varchar](125) NULL,
	[fqdn] [varchar](225) NULL,
	[host_distribution] [varchar](200),  
	[processor_name] [varchar](200),
	[product_version] [varchar](30) NULL,
	[edition] [varchar](50) NULL,
	[sqlserver_start_time_utc] [datetime2](7) NULL,
	[total_physical_memory_kb] [bigint] NULL,
	[os_start_time_utc] [datetime2](7) NULL,
	[cpu_count] [smallint] NULL,
	[scheduler_count] [smallint] NULL,
	[major_version_number] [smallint] NULL,
	[minor_version_number] [smallint] NULL,
	[max_server_memory_mb] [int] null,

	INDEX ci_all_server_stable_info_history clustered ([collection_time],[srv_name])
);


/* ****** 7) Create table dbo.all_server_volatile_info__staging ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '7) Create table dbo.all_server_volatile_info__staging';
DECLARE @_sql NVARCHAR(MAX);
DECLARE @MemoryOptimizedObjectUsage bit = 1;

SET @_sql = '
CREATE TABLE [dbo].[all_server_volatile_info__staging]
(
	[srv_name] [varchar](125) NOT NULL,
	[os_cpu] [decimal](20, 2) NULL,
	[sql_cpu] [decimal](20, 2) NULL,
	[pcnt_kernel_mode] [decimal](20, 2) NULL,
	[page_faults_kb] [decimal](20, 2) NULL,
	[blocked_counts] [int] NULL DEFAULT 0,
	[blocked_duration_max_seconds] [bigint] NULL DEFAULT 0,
	[available_physical_memory_kb] [bigint] NULL,
	[system_high_memory_signal_state] [varchar](20) NULL,
	[physical_memory_in_use_kb] [decimal](20, 2) NULL,
	[memory_grants_pending] [int] NULL,
	[connection_count] [int] NULL DEFAULT 0,
	[active_requests_count] [int] NULL DEFAULT 0,
	[waits_per_core_per_minute] [decimal](20, 2) NULL DEFAULT 0,
	[avg_disk_wait_ms] [decimal](20, 2) NULL DEFAULT 0,
	[avg_disk_latency_ms] int NULL DEFAULT 0,
	[page_life_expectancy] int NULL DEFAULT 0,
	[memory_consumers] int NULL DEFAULT 0,
	[target_server_memory_kb] bigint NULL DEFAULT 0,
	[total_server_memory_kb] bigint NULL DEFAULT 0,
	[collection_time] [datetime2] NULL default sysdatetime()
)';

EXEC (@_sql);
GO


/* ****** 8) Create table dbo.all_server_volatile_info ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '8) Create table dbo.all_server_volatile_info';
DECLARE @_sql NVARCHAR(MAX);
DECLARE @MemoryOptimizedObjectUsage bit = 1;

SET @_sql = '
CREATE TABLE [dbo].[all_server_volatile_info]
(
	[srv_name] [varchar](125) NOT NULL,
	[os_cpu] [decimal](20, 2) NULL,
	[sql_cpu] [decimal](20, 2) NULL,
	[pcnt_kernel_mode] [decimal](20, 2) NULL,
	[page_faults_kb] [decimal](20, 2) NULL,
	[blocked_counts] [int] NULL DEFAULT 0,
	[blocked_duration_max_seconds] [bigint] NULL DEFAULT 0,
	[available_physical_memory_kb] [bigint] NULL,
	[system_high_memory_signal_state] [varchar](20) NULL,
	[physical_memory_in_use_kb] [decimal](20, 2) NULL,
	[memory_grants_pending] [int] NULL,
	[connection_count] [int] NULL DEFAULT 0,
	[active_requests_count] [int] NULL DEFAULT 0,
	[waits_per_core_per_minute] [decimal](20, 2) NULL DEFAULT 0,
	[avg_disk_wait_ms] [decimal](20, 2) NULL DEFAULT 0,
	[avg_disk_latency_ms] int NULL DEFAULT 0,
	[page_life_expectancy] int NULL DEFAULT 0,
	[memory_consumers] int NULL DEFAULT 0,
	[target_server_memory_kb] bigint NULL DEFAULT 0,
	[total_server_memory_kb] bigint NULL DEFAULT 0,
	[collection_time] [datetime2] NULL default sysdatetime(),

	'+(case when @MemoryOptimizedObjectUsage = 1 then '' else '--' end)+'CONSTRAINT pk_all_server_volatile_info primary key nonclustered ([srv_name])
	'+(case when @MemoryOptimizedObjectUsage = 0 then '' else '--' end)+'CONSTRAINT pk_all_server_volatile_info primary key clustered ([srv_name])
)
'+(case when @MemoryOptimizedObjectUsage = 1 then '' else '--' end)+'WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);';

EXEC (@_sql);
GO


/* ****** 9) Create table dbo.all_server_collection_latency_info ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '9) Create table dbo.all_server_collection_latency_info';
go

CREATE TABLE [dbo].[all_server_collection_latency_info]
(
	[srv_name] [varchar](125) NOT NULL,
	[host_name] [varchar](125) NULL,
	[performance_counters__latency_minutes] int null,
	[xevent_metrics__latency_minutes] int null,
	[WhoIsActive__latency_minutes] int null,
	[os_task_list__latency_minutes] int null,
	[disk_space__latency_minutes] int null,
	[file_io_stats__latency_minutes] int null,
	[sql_agent_job_stats__latency_minutes] int null,
	[memory_clerks__latency_minutes] int null,
	[wait_stats__latency_minutes] int null,
	[BlitzIndex__latency_days] int null,
	[BlitzIndex_Mode0__latency_days] int null,
	[BlitzIndex_Mode1__latency_days] int null,
	[BlitzIndex_Mode4__latency_days] int null,
	[collection_time] [datetime2] NULL default sysdatetime(),
	INDEX ci_all_server_collection_latency_info unique nonclustered ([srv_name],[host_name])
)
GO

/* ****** 10) Create table dbo.all_server_volatile_info_history ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '10) Create table dbo.all_server_volatile_info_history';
go

CREATE TABLE [dbo].[all_server_volatile_info_history]
(
	[collection_time] [datetime2] NULL default sysdatetime(),
	[srv_name] [varchar](125) NOT NULL,
	[os_cpu] [decimal](20, 2) NULL,
	[sql_cpu] [decimal](20, 2) NULL,
	[pcnt_kernel_mode] [decimal](20, 2) NULL,
	[page_faults_kb] [decimal](20, 2) NULL,
	[blocked_counts] [int] NULL DEFAULT 0,
	[blocked_duration_max_seconds] [bigint] NULL DEFAULT 0,
	[available_physical_memory_kb] [bigint] NULL,
	[system_high_memory_signal_state] [varchar](20) NULL,
	[physical_memory_in_use_kb] [decimal](20, 2) NULL,
	[memory_grants_pending] [int] NULL,
	[connection_count] [int] NULL DEFAULT 0,
	[active_requests_count] [int] NULL DEFAULT 0,
	[waits_per_core_per_minute] [decimal](20, 2) NULL DEFAULT 0,
	[avg_disk_wait_ms] [decimal](20, 2) NULL DEFAULT 0,
	[avg_disk_latency_ms] int NULL DEFAULT 0,
	[page_life_expectancy] int NULL DEFAULT 0,
	[memory_consumers] int NULL DEFAULT 0,
	[target_server_memory_kb] bigint NULL DEFAULT 0,
	[total_server_memory_kb] bigint NULL DEFAULT 0,

	INDEX ci_all_server_volatile_info_history clustered ([collection_time],[srv_name])
)
GO

/* ****** 11) Create table dbo.sql_agent_jobs_all_servers ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '11) Create table dbo.sql_agent_jobs_all_servers';
go

CREATE TABLE [dbo].[sql_agent_jobs_all_servers]
(
	[sql_instance] [varchar](255) NOT NULL,
	[JobName] [varchar](255) NOT NULL,
	[JobCategory] [varchar](255) NOT NULL,
	[IsDisabled] [bit] NOT NULL,
	[Last_RunTime] [datetime2](7) NULL,
	[Last_Run_Duration_Seconds] [int] NULL,
	[Last_Run_Outcome] [varchar](50) NULL,
	[Expected_Max_Duration_Minutes] [int] NULL,
	[Successfull_Execution_ClockTime_Threshold_Minutes] [int] NULL,
	[Last_Successful_ExecutionTime] [datetime2](7) NULL,
	[Last_Successful_Execution_Hours] [int] NULL,
	[Running_Since] [datetime2](7) NULL,
	[Running_StepName] [varchar](250) NULL,
	[Running_Since_Min] [bigint] NULL,
	[Session_Id] [int] NULL,
	[Blocking_Session_Id] [int] NULL,
	[Next_RunTime] [datetime2](7) NULL,
	[Total_Executions] [bigint] NULL,
	[Total_Success_Count] [bigint] NULL,
	[Total_Stopped_Count] [bigint] NULL,
	[Total_Failed_Count] [bigint] NULL,
	[Success_Pcnt] [bigint] NULL,
	[Continous_Failures] [int] NULL,
	[<10-Min] [bigint] NULL,
	[10-Min] [bigint] NULL,
	[30-Min] [bigint] NULL,
	[1-Hrs] [bigint] NULL,
	[2-Hrs] [bigint] NULL,
	[3-Hrs] [bigint] NULL,
	[6-Hrs] [bigint] NULL,
	[9-Hrs] [bigint] NULL,
	[12-Hrs] [bigint] NULL,
	[18-Hrs] [bigint] NULL,
	[24-Hrs] [bigint] NULL,
	[36-Hrs] [bigint] NULL,
	[48-Hrs] [bigint] NULL,
	[Is_Running] [int] NOT NULL,

	[UpdatedDateUTC] datetime2 NOT NULL,
	[CollectionTimeUTC] datetime2 NOT NULL DEFAULT GETUTCDATE() 

	,CONSTRAINT pk_sql_agent_jobs_all_servers PRIMARY KEY CLUSTERED ([sql_instance], [JobName])
	,INDEX [JobName] NONCLUSTERED ([JobName])
)
GO

/* ****** 12) Create table dbo.sql_agent_jobs_all_servers__staging ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '12) Create table dbo.sql_agent_jobs_all_servers__staging';
go

CREATE TABLE [dbo].[sql_agent_jobs_all_servers__staging]
(
	[sql_instance] [varchar](255) NOT NULL,
	[JobName] [varchar](255) NOT NULL,
	[JobCategory] [varchar](255) NOT NULL,
	[IsDisabled] [bit] NOT NULL,
	[Last_RunTime] [datetime2](7) NULL,
	[Last_Run_Duration_Seconds] [int] NULL,
	[Last_Run_Outcome] [varchar](50) NULL,
	[Expected_Max_Duration_Minutes] [int] NULL,
	[Successfull_Execution_ClockTime_Threshold_Minutes] [int] NULL,
	[Last_Successful_ExecutionTime] [datetime2](7) NULL,
	[Last_Successful_Execution_Hours] [int] NULL,
	[Running_Since] [datetime2](7) NULL,
	[Running_StepName] [varchar](250) NULL,
	[Running_Since_Min] [bigint] NULL,
	[Session_Id] [int] NULL,
	[Blocking_Session_Id] [int] NULL,
	[Next_RunTime] [datetime2](7) NULL,
	[Total_Executions] [bigint] NULL,
	[Total_Success_Count] [bigint] NULL,
	[Total_Stopped_Count] [bigint] NULL,
	[Total_Failed_Count] [bigint] NULL,
	[Success_Pcnt] [bigint] NULL,
	[Continous_Failures] [int] NULL,
	[<10-Min] [bigint] NULL,
	[10-Min] [bigint] NULL,
	[30-Min] [bigint] NULL,
	[1-Hrs] [bigint] NULL,
	[2-Hrs] [bigint] NULL,
	[3-Hrs] [bigint] NULL,
	[6-Hrs] [bigint] NULL,
	[9-Hrs] [bigint] NULL,
	[12-Hrs] [bigint] NULL,
	[18-Hrs] [bigint] NULL,
	[24-Hrs] [bigint] NULL,
	[36-Hrs] [bigint] NULL,
	[48-Hrs] [bigint] NULL,
	[Is_Running] [int] NOT NULL,

	[UpdatedDateUTC] datetime2 NOT NULL,
	[CollectionTimeUTC] datetime2 NOT NULL DEFAULT GETUTCDATE() 

	,CONSTRAINT pk_sql_agent_jobs_all_servers__staging PRIMARY KEY CLUSTERED ([sql_instance], [JobName])
	,INDEX [JobName] NONCLUSTERED ([JobName])
)
GO

/* ****** 13) Create table dbo.disk_space_all_servers ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '13) Create table dbo.disk_space_all_servers';
go

CREATE TABLE [dbo].[disk_space_all_servers]
(
	[sql_instance] [varchar](255) NOT NULL,	
	[host_name] [varchar](125) NOT NULL,
	[disk_volume] [varchar](255) NOT NULL,
	[label] [varchar](125) NULL,
	[capacity_mb] [decimal](20,2) NOT NULL,
	[free_mb] [decimal](20,2) NOT NULL,
	[block_size] [int] NULL,
	[filesystem] [varchar](125) NULL,

	[updated_date_utc] datetime2 NOT NULL,
	[collection_time_utc] datetime2 NOT NULL DEFAULT GETUTCDATE(),

	INDEX ci_disk_space_all_servers CLUSTERED ([sql_instance])
)
go

/* ****** 14) Create table dbo.disk_space_all_servers__staging ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '14) Create table dbo.disk_space_all_servers__staging';
go

CREATE TABLE [dbo].[disk_space_all_servers__staging]
(
	[sql_instance] [varchar](255) NOT NULL,	
	[host_name] [varchar](125) NOT NULL,
	[disk_volume] [varchar](255) NOT NULL,
	[label] [varchar](125) NULL,
	[capacity_mb] [decimal](20,2) NOT NULL,
	[free_mb] [decimal](20,2) NOT NULL,
	[block_size] [int] NULL,
	[filesystem] [varchar](125) NULL,

	[updated_date_utc] datetime2 NOT NULL,
	[collection_time_utc] datetime2 NOT NULL DEFAULT GETUTCDATE(),

	INDEX ci_disk_space_all_servers__staging CLUSTERED ([sql_instance])
)
go

/* ****** 15) Create table dbo.log_space_consumers_all_servers ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '15) Create table dbo.log_space_consumers_all_servers';
go

CREATE TABLE [dbo].[log_space_consumers_all_servers]
(
	[sql_instance] [varchar](255) NOT NULL,
	[database_name] sysname not null,
	[recovery_model] varchar(20) not null,
	[log_reuse_wait_desc] varchar(125) not null,
	[log_size_mb] decimal(20, 2) not null,
	[log_used_mb] decimal(20, 2) not null,
	[exists_valid_autogrowing_file] bit null,
	[log_used_pct] decimal(10, 2) default 0.0 not null,
	[log_used_pct_threshold] decimal(10,2) not null,
	[log_used_gb_threshold] decimal(20,2) null,
	[spid] int null,
	[transaction_start_time] datetime null,
	[login_name] sysname null,
	[program_name] sysname null,
	[host_name] sysname null,
	[host_process_id] int null,
	[command] varchar(16) null,
	[additional_info] varchar(255) null,
	[action_taken] varchar(100) null,
	[sql_text] varchar(max) null,	
	[is_pct_threshold_valid] bit default 0 not null,
	[is_gb_threshold_valid] bit default 0 not null,
	[threshold_condition] varchar(5) not null,
	[thresholds_validated] bit default 0 not null,

	[updated_date_utc] datetime2 NOT NULL,
	[collection_time_utc] datetime2 NOT NULL DEFAULT GETUTCDATE(),

	INDEX ci_log_space_consumers_all_servers CLUSTERED ([sql_instance])
);
go

/* ****** 16) Create table dbo.log_space_consumers_all_servers__staging ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '16) Create table dbo.log_space_consumers_all_servers__staging';
go

CREATE TABLE [dbo].[log_space_consumers_all_servers__staging]
(
	[sql_instance] [varchar](255) NOT NULL,
	[database_name] sysname not null,
	[recovery_model] varchar(20) not null,
	[log_reuse_wait_desc] varchar(125) not null,
	[log_size_mb] decimal(20, 2) not null,
	[log_used_mb] decimal(20, 2) not null,
	[exists_valid_autogrowing_file] bit null,
	[log_used_pct] decimal(10, 2) default 0.0 not null,
	[log_used_pct_threshold] decimal(10,2) not null,
	[log_used_gb_threshold] decimal(20,2) null,
	[spid] int null,
	[transaction_start_time] datetime null,
	[login_name] sysname null,
	[program_name] sysname null,
	[host_name] sysname null,
	[host_process_id] int null,
	[command] varchar(16) null,
	[additional_info] varchar(255) null,
	[action_taken] varchar(100) null,
	[sql_text] varchar(max) null,	
	[is_pct_threshold_valid] bit default 0 not null,
	[is_gb_threshold_valid] bit default 0 not null,
	[threshold_condition] varchar(5) not null,
	[thresholds_validated] bit default 0 not null,

	[updated_date_utc] datetime2 NOT NULL,
	[collection_time_utc] datetime2 NOT NULL DEFAULT GETUTCDATE(),

	INDEX ci_log_space_consumers_all_servers__staging CLUSTERED ([sql_instance])
);
go

/* ****** 17) Create table dbo.tempdb_space_usage_all_servers ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '17) Create table dbo.tempdb_space_usage_all_servers';
go

CREATE TABLE dbo.tempdb_space_usage_all_servers
(	
	[sql_instance] [varchar](255) NOT NULL,
	[data_size_mb] decimal(20,2) not null,
	[data_used_mb] decimal(20,2) not null, 
	[data_used_pct] decimal(5,2) not null, 
	[log_size_mb] decimal(20,2) not null,
	[log_used_mb] decimal(20,2) null,
	[log_used_pct] decimal(5,2) null,
	[version_store_mb] decimal(20,2) null,
	[version_store_pct] decimal(20,2) null,

	[updated_date_utc] datetime2 NOT NULL,
	[collection_time_utc] datetime2 NOT NULL DEFAULT GETUTCDATE(),

	INDEX [CI_tempdb_space_usage_all_servers] clustered ([sql_instance])
);
go

/* ****** 18) Create table dbo.tempdb_space_usage_all_servers__staging ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '18) Create table dbo.tempdb_space_usage_all_servers__staging';
go

CREATE TABLE dbo.tempdb_space_usage_all_servers__staging
(	
	[sql_instance] [varchar](255) NOT NULL,
	[data_size_mb] decimal(20,2) not null,
	[data_used_mb] decimal(20,2) not null, 
	[data_used_pct] decimal(5,2) not null, 
	[log_size_mb] decimal(20,2) not null,
	[log_used_mb] decimal(20,2) null,
	[log_used_pct] decimal(5,2) null,
	[version_store_mb] decimal(20,2) null,
	[version_store_pct] decimal(20,2) null,

	[updated_date_utc] datetime2 NOT NULL,
	[collection_time_utc] datetime2 NOT NULL DEFAULT GETUTCDATE(),

	INDEX [CI_tempdb_space_usage_all_servers__staging] clustered ([sql_instance])
);
go

/* ****** 19) Create table dbo.ag_health_state_all_servers ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '19) Create table dbo.ag_health_state_all_servers';
go

CREATE TABLE dbo.ag_health_state_all_servers
(	
	[sql_instance] [varchar](255) not null,
	[replica_server_name] [varchar](255) NULL,
	[is_primary_replica] [bit] not null,
	[database_name] [varchar](255) not null,
	[ag_name] [sysname] not null,
	[ag_listener] [varchar](114) null,
	[is_local] [bit] not null,
	[is_distributed] [bit] not null,
	[synchronization_state_desc] [varchar](60) NULL,
	[synchronization_health_desc] [varchar](60) NULL,
	[latency_seconds] [bigint] NULL,
	[redo_queue_size] [bigint] NULL,
	[log_send_queue_size] [bigint] NULL,
	[last_redone_time] [datetime] NULL,
	[log_send_rate] [bigint] NULL,
	[redo_rate] [bigint] NULL,
	[estimated_redo_completion_time_min] [numeric](26, 6) NULL,
	[last_commit_time] [datetime] NULL,
	[is_suspended] [bit] NULL,
	[suspend_reason_desc] [varchar](125) NULL,

	[updated_date_utc] datetime2 NOT NULL,
	[collection_time_utc] datetime2 NOT NULL DEFAULT GETUTCDATE(),

	index [CI_ag_health_state_all_servers] clustered ([sql_instance], [replica_server_name]),
	index [replica_server_name__database_name] nonclustered ([replica_server_name], [database_name])
);
go

/* ****** 20) Create table dbo.ag_health_state_all_servers__staging ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '20) Create table dbo.ag_health_state_all_servers__staging';
go

CREATE TABLE dbo.ag_health_state_all_servers__staging
(	
	[sql_instance] [varchar](255) not null,
	[replica_server_name] [varchar](255) NULL,
	[is_primary_replica] [bit] not null,
	[database_name] [varchar](255) not null,
	[ag_name] [sysname] not null,
	[ag_listener] [varchar](114) null,
	[is_local] [bit] not null,
	[is_distributed] [bit] not null,
	[synchronization_state_desc] [varchar](60) NULL,
	[synchronization_health_desc] [varchar](60) NULL,
	[latency_seconds] [bigint] NULL,
	[redo_queue_size] [bigint] NULL,
	[log_send_queue_size] [bigint] NULL,
	[last_redone_time] [datetime] NULL,
	[log_send_rate] [bigint] NULL,
	[redo_rate] [bigint] NULL,
	[estimated_redo_completion_time_min] [numeric](26, 6) NULL,
	[last_commit_time] [datetime] NULL,
	[is_suspended] [bit] NULL,
	[suspend_reason_desc] [varchar](125) NULL,

	[updated_date_utc] datetime2 NOT NULL,
	[collection_time_utc] datetime2 NOT NULL DEFAULT GETUTCDATE(),

	index [CI_ag_health_state_all_servers__staging] clustered ([sql_instance], [replica_server_name]),
	index [replica_server_name__database_name] nonclustered ([replica_server_name], [database_name])
);
go

/* ****** 21) Add dbo.purge_table entry for dbo.all_server_stable_info_history ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '21) Add dbo.purge_table entry for dbo.all_server_stable_info_history';
if not exists (select 1 from dbo.purge_table where table_name = 'dbo.all_server_stable_info_history')
begin
	insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.all_server_stable_info_history', 
			date_key = 'collection_time', 
			retention_days = 90, 
			purge_row_size = 1000,
			reference = 'SQLMonitor Data Collection'
end
go

/* ****** 22) Create procedure dbo.usp_populate__all_server_stable_info_history ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '22) Create procedure dbo.usp_populate__all_server_stable_info_history';

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_populate__all_server_stable_info_history')
    EXEC ('CREATE PROC dbo.usp_populate__all_server_stable_info_history AS SELECT ''stub version, to be replaced''')
GO

ALTER PROCEDURE dbo.usp_populate__all_server_stable_info_history
AS
BEGIN
	SET NOCOUNT ON;
	INSERT dbo.all_server_stable_info_history
	(	collection_time, srv_name, at_server_name, machine_name, server_name, [ip], domain, [host_name], fqdn, host_distribution, processor_name, product_version, edition, sqlserver_start_time_utc, total_physical_memory_kb, os_start_time_utc, cpu_count, scheduler_count, major_version_number, minor_version_number, max_server_memory_mb )
	select collection_time, srv_name, at_server_name, machine_name, server_name, [ip], domain, [host_name], fqdn, host_distribution, processor_name, product_version, edition, sqlserver_start_time_utc, total_physical_memory_kb, os_start_time_utc, cpu_count, scheduler_count, major_version_number, minor_version_number, max_server_memory_mb
	from dbo.all_server_stable_info vi
END
go

/* ****** 23) Add dbo.purge_table entry for dbo.all_server_volatile_info_history ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '23) Add dbo.purge_table entry for dbo.all_server_volatile_info_history';
if not exists (select 1 from dbo.purge_table where table_name = 'dbo.all_server_volatile_info_history')
begin
	insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.all_server_volatile_info_history', 
			date_key = 'collection_time', 
			retention_days = 90, 
			purge_row_size = 1000,
			reference = 'SQLMonitor Data Collection'
end
go

/* ****** 24) Create procedure dbo.usp_populate__all_server_volatile_info_history ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '24) Create procedure dbo.usp_populate__all_server_volatile_info_history';

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_populate__all_server_volatile_info_history')
    EXEC ('CREATE PROC dbo.usp_populate__all_server_volatile_info_history AS SELECT ''stub version, to be replaced''')
GO

ALTER PROCEDURE dbo.usp_populate__all_server_volatile_info_history
AS
BEGIN
	SET NOCOUNT ON;
	INSERT dbo.all_server_volatile_info_history
	(	[collection_time], [srv_name], [os_cpu], [sql_cpu], [pcnt_kernel_mode], [page_faults_kb], [blocked_counts], 
		[blocked_duration_max_seconds], [available_physical_memory_kb], [system_high_memory_signal_state], 
		[physical_memory_in_use_kb], [memory_grants_pending], [connection_count], [active_requests_count], 
		[waits_per_core_per_minute], [avg_disk_wait_ms], [avg_disk_latency_ms], [page_life_expectancy], 
		[target_server_memory_kb], [total_server_memory_kb], [memory_consumers] 
	)
	select [collection_time], [srv_name], [os_cpu], [sql_cpu], [pcnt_kernel_mode], [page_faults_kb], [blocked_counts], 
		[blocked_duration_max_seconds], [available_physical_memory_kb], [system_high_memory_signal_state], 
		[physical_memory_in_use_kb], [memory_grants_pending], [connection_count], [active_requests_count], 
		[waits_per_core_per_minute], [avg_disk_wait_ms], [avg_disk_latency_ms], page_life_expectancy, 
		target_server_memory_kb, total_server_memory_kb, memory_consumers
	from dbo.all_server_volatile_info vi
END
go

/* ****** 25) Create view dbo.vw_all_server_info ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '25) Create view dbo.vw_all_server_info';

if OBJECT_ID('dbo.vw_all_server_info') is null
	exec ('create view dbo.vw_all_server_info as select 1 as dummy;');
go

alter view dbo.vw_all_server_info
--with schemabinding
as
	select	si.srv_name, 
			/* stable info */
			at_server_name, machine_name, server_name, ip, domain, host_name, host_distribution, processor_name,
			product_version, edition, sqlserver_start_time_utc, total_physical_memory_kb,
			os_start_time_utc, cpu_count, scheduler_count, major_version_number, minor_version_number,
			max_server_memory_mb,
			/* volatile info */
			os_cpu, sql_cpu, pcnt_kernel_mode, page_faults_kb, blocked_counts, blocked_duration_max_seconds, 
			available_physical_memory_kb, system_high_memory_signal_state, physical_memory_in_use_kb,
			memory_grants_pending, connection_count, active_requests_count, waits_per_core_per_minute,
			avg_disk_wait_ms, avg_disk_latency_ms, page_life_expectancy, target_server_memory_kb, total_server_memory_kb, 
			memory_consumers
	from dbo.all_server_stable_info as si
	left join dbo.all_server_volatile_info as vi
	on si.srv_name = vi.srv_name;
go


IF APP_NAME() = 'Microsoft SQL Server Management Studio - Query'
BEGIN
	SET NOCOUNT ON;

	-- Stable Info
	if	( (select count(1) from dbo.all_server_stable_info) <> (select count(distinct sql_instance) from dbo.instance_details) )
		or ( (select max(collection_time) from  dbo.all_server_stable_info) < dateadd(MINUTE, -30, SYSDATETIME()) )
	begin
		exec dbo.usp_GetAllServerInfo @result_to_table = 'dbo.all_server_stable_info',
					@output = 'srv_name, at_server_name, machine_name, server_name, ip, domain, host_name, product_version, edition, sqlserver_start_time_utc, total_physical_memory_kb, os_start_time_utc, cpu_count, scheduler_count, major_version_number, minor_version_number, max_server_memory_mb';
	end
	--select * from dbo.all_server_stable_info;

	-- Volatile Info
	exec dbo.usp_GetAllServerInfo @result_to_table = 'dbo.all_server_volatile_info',
				@output = 'srv_name, os_cpu, sql_cpu, pcnt_kernel_mode, page_faults_kb, blocked_counts, blocked_duration_max_seconds, available_physical_memory_kb, system_high_memory_signal_state, physical_memory_in_use_kb, memory_grants_pending, connection_count, active_requests_count, 
					waits_per_core_per_minute, avg_disk_wait_ms, avg_disk_latency_ms, page_life_expectancy, memory_consumers, target_server_memory_kb, total_server_memory_kb';
	--select * from dbo.all_server_volatile_info;

	select * 
	from dbo.vw_all_server_info si
	--where si.srv_name = convert(varchar,SERVERPROPERTY('ServerName'))
END
GO

/* ****** 26) Alter multiple tables and add few columns ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '26) Alter multiple tables and add few columns';

if not exists (select * from sys.columns c where c.object_id = OBJECT_ID('dbo.instance_details') and c.name = 'is_available')
    alter table dbo.instance_details add [is_available] bit NOT NULL default 1;
go
if not exists (select * from sys.columns c where c.object_id = OBJECT_ID('dbo.instance_details') and c.name = 'created_date_utc')
    alter table dbo.instance_details add [created_date_utc] datetime2 NOT NULL default SYSUTCDATETIME();
go
if not exists (select * from sys.columns c where c.object_id = OBJECT_ID('dbo.instance_details') and c.name = 'last_unavailability_time_utc')
    alter table dbo.instance_details add [last_unavailability_time_utc] datetime2 null;
go
if not exists (select * from sys.columns c where c.object_id = OBJECT_ID('dbo.instance_details') and c.name = 'more_info')
    alter table dbo.instance_details add [more_info] varchar(2000) null;
go
if not exists (select * from sys.columns c where c.object_id = OBJECT_ID('dbo.instance_details') and c.name = 'is_enabled')
    alter table dbo.instance_details add [is_enabled] bit NOT NULL default 0;
go
if not exists (select * from sys.columns c where c.object_id = OBJECT_ID('dbo.instance_details') and c.name = 'is_linked_server_working')
    alter table dbo.instance_details add [is_linked_server_working] bit NOT NULL default 1;
go
if not exists (select * from sys.columns c where c.object_id = OBJECT_ID('dbo.instance_details') and c.name = 'remarks')
    alter table dbo.instance_details add [remarks] nvarchar(500) NULL;
go

/* ****** 27) Create table dbo.instance_details_history ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '27) Create table dbo.instance_details_history';
go

if OBJECT_ID('dbo.instance_details_history') is null
begin
	CREATE TABLE dbo.instance_details_history
	(
		[sql_instance] [nvarchar](255) NOT NULL,
		[sql_instance_port] [varchar](10) NULL,
		[host_name] [nvarchar](255) NOT NULL,
		[database] [varchar](255) NOT NULL,
		[collector_tsql_jobs_server] [varchar](255) NOT NULL,
		[collector_powershell_jobs_server] [varchar](255) NOT NULL,
		[data_destination_sql_instance] [varchar](255) NOT NULL,
		[is_available] [bit] NOT NULL,
		[created_date_utc] [datetime2](7) NOT NULL,
		[last_unavailability_time_utc] [datetime2](7) NULL,
		[dba_group_mail_id] [varchar](2000) NOT NULL,
		[sqlmonitor_script_path] [varchar](2000) NOT NULL,
		[sqlmonitor_version] [varchar](20) NOT NULL,
		[is_alias] [bit] NOT NULL,
		[source_sql_instance] [varchar](255) NULL,
		[is_enabled] [bit] NOT NULL,
		[is_linked_server_working] [bit] NOT NULL,
		[more_info] [varchar](2000) NULL,

		action_type varchar(50) not null,
		action_time datetime2 not null default sysdatetime(),
		acted_by_login varchar(125) not null default suser_name(),
		acted_by_program varchar(500) null default app_name(),
		acted_by_client_host varchar(125) null default host_name(),
		remarks varchar(500) null,

		index CI_instance_details_history clustered (action_time)
	);
end
go

/* ****** 28) Create trigger tgr_dml__instance_details on dbo.instance_details ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '28) Create trigger tgr_dml__instance_details on dbo.instance_details';
go

-- drop trigger [dbo].[tgr_dml__instance_details] on dbo.instance_details
create or alter trigger dbo.tgr_dml__instance_details
	on dbo.instance_details
	after insert, update, delete
as 
begin
	declare @action_type varchar(20);
	declare @remarks nvarchar(255);
	declare @identity_min bigint;
	declare @identity_max bigint;
	declare @current_time datetime2 = sysdatetime();
	declare @subject varchar(2000);
	declare @table_html nvarchar(max);
	declare @body_html nvarchar(max);
	declare @footer_html nvarchar(max);
	declare @dba_team_email_id varchar(125) = 'dba_team@gmail.com';

	if LEFT(@dba_team_email_id,CHARINDEX('@',@dba_team_email_id)-1) = 'dba_team'
		select top 1 @dba_team_email_id = dba_group_mail_id from dbo.instance_details where is_enabled = 1 and is_alias = 0;

	if exists (select * from deleted) and exists (select * from inserted)
	begin
		set @action_type = 'update'
		select @remarks = convert(nvarchar, count(*)) + ' row(s) affected.'  from inserted;
	end
	if exists (select * from deleted) and not exists (select * from inserted)
	begin
		set @action_type = 'delete'
		select @remarks = convert(nvarchar, count(*)) + ' row(s) affected.'  from deleted;
	end
	if not exists (select * from deleted) and exists (select * from inserted)
	begin
		set @action_type = 'insert'
		select @remarks = convert(nvarchar, count(*)) + ' row(s) affected.'  from inserted;
	end

	if exists (select * from deleted)
	begin
		insert dbo.instance_details_history
		(sql_instance, sql_instance_port, [host_name], [database], collector_tsql_jobs_server, collector_powershell_jobs_server, data_destination_sql_instance, is_available, created_date_utc, last_unavailability_time_utc, dba_group_mail_id, sqlmonitor_script_path, sqlmonitor_version, is_alias, source_sql_instance, is_enabled, is_linked_server_working, more_info, action_type, action_time, acted_by_login, acted_by_program, acted_by_client_host, remarks)
		select	sql_instance, sql_instance_port, [host_name], [database], collector_tsql_jobs_server, collector_powershell_jobs_server, data_destination_sql_instance, is_available, created_date_utc, last_unavailability_time_utc, dba_group_mail_id, sqlmonitor_script_path, sqlmonitor_version, is_alias, source_sql_instance, is_enabled, is_linked_server_working, more_info, 
			action_type = @action_type + (case when @action_type = 'update' then '-old-data' else '' end), 
			action_time = @current_time, 
			acted_by_login = SUSER_NAME(), 
			acted_by_program = APP_NAME(), 
			acted_by_client_host = HOST_NAME(), 
			remarks = @remarks
		from deleted d;
	end

	if exists (select * from inserted)
	begin
		insert dbo.instance_details_history
		(sql_instance, sql_instance_port, [host_name], [database], collector_tsql_jobs_server, collector_powershell_jobs_server, data_destination_sql_instance, is_available, created_date_utc, last_unavailability_time_utc, dba_group_mail_id, sqlmonitor_script_path, sqlmonitor_version, is_alias, source_sql_instance, is_enabled, is_linked_server_working, more_info, action_type, action_time, acted_by_login, acted_by_program, acted_by_client_host, remarks)
		select	sql_instance, sql_instance_port, [host_name], [database], collector_tsql_jobs_server, collector_powershell_jobs_server, data_destination_sql_instance, is_available, created_date_utc, last_unavailability_time_utc, dba_group_mail_id, sqlmonitor_script_path, sqlmonitor_version, is_alias, source_sql_instance, is_enabled, is_linked_server_working, more_info, 
			action_type = @action_type + (case when @action_type = 'update' then '-new-data' else '' end), 
			action_time = @current_time, 
			acted_by_login = SUSER_NAME(), 
			acted_by_program = APP_NAME(), 
			acted_by_client_host = HOST_NAME(), 
			remarks = @remarks
		from inserted i;
	end

	-- Check if sql_instance has been 'Disabled'
	if @action_type = 'update' 
		and exists (select * from deleted d join inserted i on i.sql_instance = d.sql_instance and i.host_name = d.host_name 
					where i.is_enabled = 0 and d.is_enabled = 1 and i.is_alias = 0)
	begin
		set @subject = 'SQLMonitor Monitoring Disabled - '+convert(varchar,@current_time,120);
		set @body_html = N'<H1>SQLMonitor Monitoring Disabled - '+convert(varchar,@current_time,120)+'</H1>'
		set @table_html = N'<table border="1">'
			+ N'<tr>'+
				N'<th>SQL Instance</th> <th>SQL Port</th> <th>Host Name</th> <th>Updated By</th> <th>Updated Time</th> <th>More Info</th>'
			+ N'</tr>'
			+ CAST((
					SELECT td = i.sql_instance, '',
						td = coalesce(i.sql_instance_port,' '), '',
						td = i.[host_name], '',
						td = convert(varchar,SUSER_NAME()), '',
						td = convert(varchar,@current_time,121), '',
						td = coalesce(i.more_info,' ')
					from deleted d join inserted i 
						on i.sql_instance = d.sql_instance and i.host_name = d.host_name 
					where i.is_enabled = 0 and d.is_enabled = 1 and i.is_alias = 0
					FOR XML PATH('tr'),
						TYPE
					) AS NVARCHAR(MAX))
			+ N'</table>';	
		
		set @footer_html = N'<div><p>Kindly update other inventory tables also.</p></div>';

		set @body_html = @body_html+@table_html+@footer_html

		exec msdb.dbo.sp_send_dbmail
					@recipients = @dba_team_email_id,
					@subject = @subject,
					@body = @body_html,
					@body_format = 'HTML';
	end


	-- Check if sql_instance is deleted
	if @action_type = 'delete'
		and exists (select * from deleted d	where d.is_alias = 0)
	begin
		set @subject = 'SQLMonitor Monitoring - Record Removed - '+convert(varchar,@current_time,120);
		set @body_html = N'<H1>Server Removed from SQLMonitor Table - '+convert(varchar,@current_time,120)+'</H1>'
		set @table_html = N'<table border="1">'
			+ N'<tr>'+
				N'<th>SQL Instance</th> <th>SQL Port</th> <th>Host Name</th> <th>Removed By</th> <th>Removal Time</th> <th>More Info</th>'
			+ N'</tr>'
			+ CAST((
					SELECT td = d.sql_instance, '',
						td = coalesce(d.sql_instance_port,' '), '',
						td = d.[host_name], '',
						td = convert(varchar,SUSER_NAME()), '',
						td = convert(varchar,@current_time,121), '',
						td = coalesce(d.more_info,' ')
					from deleted d
					where d.is_alias = 0
					FOR XML PATH('tr'),
						TYPE
					) AS NVARCHAR(MAX))
			+ N'</table>';	
		
		set @footer_html = N'<div><p>In general, removal of server record from <code>dbo.instance_details</code> table is not permitted. <br><br>Kindly ensure this is done only in exceptional case.</p></div>';

		set @body_html = @body_html+@table_html+@footer_html

		exec msdb.dbo.sp_send_dbmail
					@recipients = @dba_team_email_id,
					@subject = @subject,
					@body = @body_html,
					@body_format = 'HTML';
	end
end
go

/* ****** 29) Create trigger tgr_dml__instance_details__prevent_bulk_udpate on dbo.instance_details ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '29) Create trigger tgr_dml__instance_details__prevent_bulk_udpate on dbo.instance_details';
go

-- drop trigger [dbo].[tgr_dml__instance_details__prevent_bulk_udpate] on dbo.instance_details
create or alter trigger dbo.tgr_dml__instance_details__prevent_bulk_udpate
	on dbo.instance_details
	for update, delete, insert
as 
begin
	declare @action_type varchar(20);
	declare @program_name nvarchar(255);
	set @program_name = PROGRAM_NAME();

	if exists (select * from deleted) and exists (select * from inserted)
	begin
		set @action_type = 'update'
	end
	if exists (select * from deleted) and not exists (select * from inserted)
	begin
		set @action_type = 'delete'
	end
	if not exists (select * from deleted) and exists (select * from inserted)
	begin
		set @action_type = 'insert'
	end

	-- Don't allow more than 5 rows in a single UPDATE/DELETE
	if @action_type in ('update','delete')
		and (select count(*) from deleted) > 5
		and @program_name <> 'check-instance-availability.ps1'
	begin
		RAISERROR ('More than 5 rows cannot be updated in a single transaction in table [dbo].[instance_details].', 16, 1);  
		ROLLBACK TRANSACTION; 
	end

	-- Check if host entry already present for another instance
	if @action_type = 'insert'
	begin
		if exists (select * from inserted)
		begin
			if exists (
						select * 
						from inserted i
						where i.is_alias = 0
						and exists (select * from dbo.instance_details id 
									where id.is_enabled = 1 and id.is_alias = 0
									and id.sql_instance <> i.sql_instance
									and id.host_name = i.host_name
									and id.data_destination_sql_instance <> i.data_destination_sql_instance
									)
					)
			begin
				RAISERROR ('[data_destination_sql_instance] cannot be more than 1 for a single host_name in table [dbo].[instance_details].', 16, 1);  
				ROLLBACK TRANSACTION; 
			end
		end
	end
end
go

/* ****** 30) Add dbo.purge_table entry for dbo.instance_details_history ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '30) Add dbo.purge_table entry for dbo.instance_details_history';
go
insert dbo.purge_table (table_name, date_key, retention_days, purge_row_size, reference)
select	table_name, date_key, retention_days, purge_row_size = 100000, reference = 'Login Expiry Infra'
from ( values 
			('dbo.instance_details_history', 'action_time', 365)
	) login_expiry_infra_tables (table_name, date_key, retention_days)
where 1=1
and not exists (select * from dbo.purge_table pt where pt.table_name = login_expiry_infra_tables.table_name)
go

/* ****** 31) Create table dbo.backups_all_servers ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '31) Create table dbo.backups_all_servers';
go
CREATE TABLE [dbo].[backups_all_servers]
(
	[sql_instance] [varchar](255) not null,
	[database_name] [varchar](128) not null,
	[backup_type] [varchar](35) null,
	[log_backups_count] [int] NULL,
	[backup_start_date_utc] [datetime] NULL,
	[backup_finish_date_utc] [datetime] NULL,
	[latest_backup_location] [varchar](260) NULL,
	[backup_size_mb] [decimal](20, 2) NULL,
	[compressed_backup_size_mb] [decimal](20, 2) NULL,
	[first_lsn] [numeric](25, 0) NULL,
	[last_lsn] [numeric](25, 0) NULL,
	[checkpoint_lsn] [numeric](25, 0) NULL,
	[database_backup_lsn] [numeric](25, 0) NULL,
	[database_creation_date_utc] [datetime] NULL,
	[backup_software] [varchar](128) NULL,
	[recovery_model] [varchar](60) NULL,
	[compatibility_level] [tinyint] NULL,
	[device_type] [varchar](25) NULL,
	[description] [varchar](255) NULL,

	[collection_time_utc] datetime2 NOT NULL DEFAULT GETUTCDATE(),

	index [CI_backups_all_servers] clustered ([sql_instance], [database_name], [backup_start_date_utc])
) ON [PRIMARY]
GO

/* ****** 32) Create table dbo.backups_all_servers__staging ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '32) Create table dbo.backups_all_servers__staging';
go
CREATE TABLE [dbo].[backups_all_servers__staging]
(
	[sql_instance] [varchar](255) not null,
	[database_name] [varchar](128) not null,
	[backup_type] [varchar](35) NULL,
	[log_backups_count] [int] NULL,
	[backup_start_date_utc] [datetime] NULL,
	[backup_finish_date_utc] [datetime] NULL,
	[latest_backup_location] [varchar](260) NULL,
	[backup_size_mb] [decimal](20, 2) NULL,
	[compressed_backup_size_mb] [decimal](20, 2) NULL,
	[first_lsn] [numeric](25, 0) NULL,
	[last_lsn] [numeric](25, 0) NULL,
	[checkpoint_lsn] [numeric](25, 0) NULL,
	[database_backup_lsn] [numeric](25, 0) NULL,
	[database_creation_date_utc] [datetime] NULL,
	[backup_software] [varchar](128) NULL,
	[recovery_model] [varchar](60) NULL,
	[compatibility_level] [tinyint] NULL,
	[device_type] [varchar](25) NULL,
	[description] [varchar](255) NULL,

	[collection_time_utc] datetime2 NOT NULL DEFAULT GETUTCDATE(),

	index [CI_backups_all_servers__staging] clustered ([sql_instance], [database_name], [backup_start_date_utc])
) ON [PRIMARY]
GO

/* ****** 33) Create table dbo.services_all_servers ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '33) Create table dbo.services_all_servers';
go
CREATE TABLE [dbo].[services_all_servers]
(
	[sql_instance] [varchar](255) NOT NULL,
	[at_server_name] [varchar](125) NULL,
	[service_type] [varchar](20) NOT NULL,
	[servicename] [varchar](255) NOT NULL,
	[startup_type_desc] [varchar](50) NOT NULL,
	[status_desc] [varchar](125) NOT NULL,
	[process_id] [int] NULL,
	[service_account] [varchar](255) NOT NULL,
	[sql_ports] [varchar](500) NULL,
	[last_startup_time_utc] [datetime2] NULL,
	[instant_file_initialization_enabled] [varchar](1) NULL,

	[collection_time_utc] [datetime2] NOT NULL DEFAULT GETUTCDATE(),

	index [CI_services_all_servers] clustered ([sql_instance])
) ON [PRIMARY]
GO

/* ****** 34) Create table dbo.services_all_servers__staging ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '34) Create table dbo.services_all_servers__staging';
go
CREATE TABLE [dbo].[services_all_servers__staging]
(
	[sql_instance] [varchar](255) NOT NULL,
	[at_server_name] [varchar](125) NULL,
	[service_type] [varchar](20) NOT NULL,
	[servicename] [varchar](255) NOT NULL,
	[startup_type_desc] [varchar](50) NOT NULL,
	[status_desc] [varchar](125) NOT NULL,
	[process_id] [int] NULL,
	[service_account] [varchar](255) NOT NULL,
	[sql_ports] [varchar](500) NULL,
	[last_startup_time_utc] [datetime2] NULL,
	[instant_file_initialization_enabled] [varchar](1) NULL,
	[collection_time_utc] [datetime2] NOT NULL DEFAULT GETUTCDATE(),

	index [CI_services_all_servers__staging] clustered ([sql_instance])
) ON [PRIMARY]
GO

/* ****** 35) Create table dbo.alert_history_all_servers ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '35) Create table dbo.alert_history_all_servers';
go
create table [dbo].[alert_history_all_servers]
(
	[collection_time_utc] [datetime2](7) NOT NULL,	
	[sql_instance] [varchar](255) NOT NULL,
	[server_name] [nvarchar](128) NULL,
	[database_name] [sysname] NULL,
	[error_number] [int] NULL,
	[error_severity] [tinyint] NULL,
	[error_message] [nvarchar](510) NULL,
	[host_instance] [nvarchar](128) NULL,
	[updated_time_utc] [datetime2](7) NOT NULL,

	index ci_alert_history_all_servers clustered ([collection_time_utc]) on ps_dba_datetime2_daily ([collection_time_utc])
) on ps_dba_datetime2_daily ([collection_time_utc]);
go

/* ****** 36) Add dbo.purge_table entry for dbo.alert_history_all_servers ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '36) Add dbo.purge_table entry for dbo.alert_history_all_servers';
go
if not exists (select 1 from dbo.purge_table where table_name = 'dbo.alert_history_all_servers')
begin
	insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.alert_history_all_servers', 
			date_key = 'collection_time_utc', 
			retention_days = 30, 
			purge_row_size = 100000,
			reference = 'SQLMonitor Data Collection'
end
go

/* ****** 37) Create table dbo.sent_alert_history_all_servers ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '37) Create table dbo.sent_alert_history_all_servers';
go
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[sent_alert_history_all_servers]') AND type in (N'U'))
BEGIN
	create table dbo.sent_alert_history_all_servers
	(	last_alert_time_utc datetime2 not null
	);
END
go

/* ****** 38) Create table dbo.alert_history_all_servers_last_actioned ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '38) Create table dbo.alert_history_all_servers_last_actioned';
go
create table dbo.alert_history_all_servers_last_actioned
(	updated_time_utc datetime2 not null  );
go


/* ****** 39) Create table dbo.sma_errorlog ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '39) Create table dbo.sma_errorlog';
go
-- drop table [dbo].[sma_errorlog]
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[sma_errorlog]') AND type in (N'U'))
BEGIN
	create table [dbo].[sma_errorlog]
	( 	[collection_time] datetime2 not null default sysdatetime(), 
		[function_name] varchar(125) not null, 
		[function_call_arguments] varchar(1000) null, 
		[server] varchar(125) null,
		[error] varchar(1000) not null, 
		[is_resolved] bit not null default 0,
		[remark] varchar(1000) null,
		[executed_by] varchar(125) not null default SUSER_NAME(),
		[executor_program_name] varchar(125) not null default program_name()

		,index [ci_sma_errorlog] clustered ([collection_time])
	)
END
go

/* ****** 40) Add dbo.purge_table entry for dbo.sma_errorlog ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '40) Add dbo.purge_table entry for dbo.sma_errorlog';
go
if not exists (select 1 from dbo.purge_table where table_name = 'dbo.sma_errorlog')
begin
	insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.sma_errorlog', 
			date_key = 'collection_time', 
			retention_days = 30, 
			purge_row_size = 100000,
			reference = 'SQLMonitor Data Collection'
end
go

/* ****** 41) Create table dbo.sma_params ******* */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '41) Create table dbo.sma_params';
go
--drop table dbo.sma_params
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[sma_params]') AND type in (N'U'))
BEGIN
	create table dbo.sma_params
	(	param_key varchar(125) not null,
		param_value varchar(500) not null,
		created_date datetime2 not null default sysdatetime(),
		created_by varchar(125) not null default suser_name(),
		remarks varchar(2000) null,
		[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
		,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
		,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

		,constraint pk_sma_params primary key clustered (param_key)
	)
	WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.sma_params_history));;
END
go

if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '41.a) Populate table dbo.sma_params';
go
if OBJECT_ID('dbo.sma_params') is not null
begin
	-- Populate missing params
	insert dbo.sma_params (param_key, param_value, remarks)
	select my_keys.param_key, my_keys.param_value, my_keys.remarks
	from (values 
			('dba_team_email_id','dba_team@gmail.com','EMail of DBA Team'),
			('dba_manager_email_id','dba.manager@gmail.com','EMail of DBA Team Manager'),
			('sre_vp_email_id','sre.vp@gmail.com','EMail of SRE VP'),
			('cto_email_id','cto@gmail.com','EMail of CTO'),
			('noc_email_id','noc@gmail.com','EMail of NOC Team'),
			('url_for_dba_slack_channel','workspace.slack.com/archives/unique_id','URL for DBA Public Slack Channel For End Users Support'),
			('dba_slack_channel_name','#sqlmonitor-alerts','DBA Slack Channel ID'),
			('dba_slack_channel_id','C01234567890','DBA Slack Channel ID'),
			('dba_slack_bot', 'SQLMonitor', 'DBA Slack Bot Name'),
			('credential_manager_database', 'DBA', 'Credential Manager Database on Inventory Server'),
			('GrafanaDashboardPortal',
				'http://localhost:3000/d/',
					'Grafana Dashboard Portal'),
			('url_all_servers_core_health_metrics_dashboard_panel',
				'distributed_live_dashboard_all_servers/monitoring-live-all-servers?orgId=1&refresh=1m&viewPanel=842',
				'URL for All Servers Core Health Metrics Panel'),
			('url_all_servers_login_expiry_dashboard_panel',
				'distributed_live_dashboard_all_servers/monitoring-live-all-servers?orgId=1&refresh=1m&viewPanel=885',
				'URL for Login Expiry Panel'),
			('url_login_expiry_dashboard_panel',
				'distributed_live_dashboard_all_servers/monitoring-live-all-servers?orgId=1&refresh=1m&viewPanel=885',
				'URL for Login Expiry Panel'),
			('url_all_servers_alert_history_dashboard_panel',
				'distributed_live_dashboard_all_servers/monitoring-live-all-servers?orgId=1&refresh=1m&viewPanel=882',
				'URL for All Servers Alert History Panel'),
			('url_all_servers_tempdb_utilization_dashboard_panel',
				'distributed_live_dashboard_all_servers/monitoring-live-all-servers?orgId=1&refresh=1m&viewPanel=860',
				'URL for All Servers Tempdb Utilization Panel'),
			('url_all_servers_logspace_utilization_dashboard_panel',
				'distributed_live_dashboard_all_servers/monitoring-live-all-servers?orgId=1&refresh=1m&viewPanel=856',
				'URL for All Servers Log Space Utilization Panel'),
			('url_all_servers_alwayson_latency_dashboard_panel',
				'distributed_live_dashboard_all_servers/monitoring-live-all-servers?orgId=1&refresh=1m&viewPanel=872',
				'URL for All Servers AlwaysOn Utilization Panel'),
			('url_all_servers_disk_utilization_dashboard_panel',
				'distributed_live_dashboard_all_servers/monitoring-live-all-servers?orgId=1&refresh=1m&viewPanel=852',
				'URL for All Servers Disk Utilization Panel'),
			('url_all_servers_sqlmonitor_jobs_dashboard_panel',
				'distributed_live_dashboard_all_servers/monitoring-live-all-servers?orgId=1&refresh=1m&viewPanel=864',
				'URL for All Servers SQLMonitor Jobs Panel'),
			('url_all_servers_backups_nonag_dbs_dashboard_panel',
				'distributed_live_dashboard_all_servers/monitoring-live-all-servers?orgId=1&refresh=1m&viewPanel=874',
				'URL for All Servers Backup Issues for Non AG Dbs Panel'),
			('url_all_servers_backups_ag_dbs_dashboard_panel',
				'distributed_live_dashboard_all_servers/monitoring-live-all-servers?orgId=1&refresh=1m&viewPanel=888',
				'URL for All Servers Backup Issues for AG Dbs Panel'),
			('url_all_servers_sqlagent_service_dashboard_panel',
				'distributed_live_dashboard_all_servers/monitoring-live-all-servers?orgId=1&refresh=1m&viewPanel=878',
				'URL for All Servers SQLAgent Service Panel'),
			('url_all_servers_offline_servers_dashboard_panel',
				'distributed_live_dashboard_all_servers/monitoring-live-all-servers?orgId=1&refresh=1m&viewPanel=844',
				'URL for All Servers Offline Instance or Linked Server Panel'),
			('url_all_servers_offline_aliases_dashboard_panel',
				'distributed_live_dashboard_all_servers/monitoring-live-all-servers?orgId=1&refresh=1m&viewPanel=887',
				'URL for All Servers Offline Aliasas or Alias Linked Server Panel'),
			('url_for_login_password_reset','#','Portal for Resetting Login Password'),
			('url_for_alerts_grafana_dashboard',
				'http://localhost:3000/d/',
					'Grafana Dashboard for Alerts'),
			('smtp_server','smtp.gmail.com','SMTP Server for Database Mail'),
			('smtp_server_port','587','SMTP Server Port'),
			('smtp_account_name','some_smtp_account@gmail.com','Account having access to SMTP Server'),
			('alert_sender_email','alert_sender_email@gmail.com','EMail used for sending Email alerts'),
			('send_sqlmonitor_job_failure_mail','1','When enabled, then job failure mail is send to DBA team'),
			('all_server_volatile_info-parallelize','no','When enabled, then volatile info is collected in parallel threads'),
			('all_server_volatile_info-parallel-threads',convert(varchar,(select case when cpu_count > 4 then 4 else cpu_count end from sys.dm_os_sys_info as osi)),'parallel threads/jobs for Volatile Info collection'),
			('usp_wrapper_GetAllServerInfo-enable-LOCK_TIMEOUT','0','Enable/Disable LOCK_TIMEOUT in procedure dbo.usp_wrapper_GetAllServerInfo'),
			('usp_GetAllServerInfo-enable-LOCK_TIMEOUT','0','Enable/Disable LOCK_TIMEOUT in procedure dbo.usp_GetAllServerInfo')
		) my_keys (param_key, param_value, remarks)
	left join dbo.sma_params p
		on p.param_key = my_keys.param_key
	where p.param_key is null;
end
go


/* ***** 42) Create table dbo.sma_servers ***************************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '42) Create table dbo.sma_servers';
go
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.sma_servers') AND type in (N'U'))
BEGIN	
	/*
		ALTER TABLE dbo.sma_servers SET ( SYSTEM_VERSIONING = OFF);
		drop table dbo.sma_servers;
		drop table dbo.sma_servers_history;
	*/
	create table dbo.sma_servers
	(
		[server] varchar(125) not null,
		[server_port] varchar(10) null,
		[domain] varchar(80) null,
		[friendly_name] varchar(500) null,
		[stability] varchar(20) not null default 'dev',
		[priority] tinyint not null default '2',
		[server_type] varchar(20) not null default 'SQLServer',
		[has_hadr] bit not null default 0,
		[hadr_strategy] varchar(50) null default 'standalone',
		[backup_strategy] varchar(255) null default 'Native',
		[server_owner_email] varchar(500) null,
		[rdp_credential] varchar(125) null,
		[sql_credential] varchar(125) null,
		[is_monitoring_enabled] bit not null default 0,
		[is_maintenance_scheduled] bit not null default 0,
		[is_tde_implemented] bit not null default 0,
		[enabled_restart_schedule] bit not null default 0, /* Remove in General */
		[is_onboarded] bit not null default 1,
		[is_decommissioned] bit not null default 0,
		[more_info] varchar(2000) null,
		[created_date_utc] datetime2 not null default getutcdate(),
		[updated_date_utc] datetime2 not null default getutcdate(),
		[updated_by] varchar(255) not null default suser_name()

		,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
		,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
		,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

		,constraint [pk_sma_servers] primary key clustered ([server])
		,constraint [chk_stability] check ( [stability] in ('dev', 'uat', 'qa', 'stg', 'prod') )
		,constraint [chk_priority] check ([priority] in (0,1,2,3,4,5))
		,constraint [chk_server_type] check ([server_type] in ('SQLServer','PostgreSQL'))
		,constraint [chk_hadr_strategy] check ([hadr_strategy] in ('standalone','mirroring','logshipping','sqlcluster','ag'))
		,constraint [chk_backup_strategy] check ([backup_strategy] in ('Native','CommVault','Rubrik','Redgate','VSS'))
	)
	WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.sma_servers_history));
END
go

/* ***** 43) Create table dbo.sma_sql_server_extended_info ***************************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '43) Create table dbo.sma_sql_server_extended_inf';
go
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.sma_sql_server_extended_info') AND type in (N'U'))
BEGIN	
	/*
		ALTER TABLE dbo.sma_sql_server_extended_info SET ( SYSTEM_VERSIONING = OFF);
		drop table dbo.sma_sql_server_extended_info;
		drop table dbo.sma_sql_server_extended_info_history;
	*/
	create table dbo.sma_sql_server_extended_info
	(
		[server] varchar(125) not null,
		[at_server_name] varchar(125) null,
		[server_name] varchar(125) not null,
		[server_ips_CSV] varchar(125) null,
		[alias_names] varchar(100) null,
		[product_version] varchar(30) not null,
		[edition] varchar(50) not null,
		[has_PII_data] bit not null default 0,
		[total_physical_memory_kb] bigint null,
		[cpu_count] smallint not null,
		[rpo_worst_case_minutes] int null,
		[rto_minutes] int null,
		[data_center] varchar(125) null,
		[availability_zone] varchar(125) null,
		[avg_utilization] varchar(2000) null,
		[ticket] varchar(2000) null,
		[purpose] varchar(2000) null,
		[known_challenges] varchar(2000) null,
		[remarks] varchar(2000) null,
		[more_info] varchar(2000) null

		,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
		,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
		,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

		,constraint [pk_sma_sql_server_extended_info] primary key clustered ([server])
		--,index [uq_at_server_name] unique ([at_server_name])
		--,index [uq_server_name] unique ([server_name])
		,constraint [fk_sma_sql_server_extended_info__server] foreign key ([server]) references dbo.sma_servers ([server])
	)
	with (system_versioning = on (history_table = dbo.sma_sql_server_extended_info_history));
END
go

if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '43.a) Add constraint chk_data_center on table dbo.sma_sql_server_extended_info';
go
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'chk_data_center') and parent_object_id = OBJECT_ID(N'dbo.sma_sql_server_extended_info'))
BEGIN	
	alter table dbo.sma_sql_server_extended_info
		add constraint chk_data_center check ([data_center] in ('Hyd','Blr'))
END
go

if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '44) Create table dbo.sma_sql_server_hosts';
go
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.sma_sql_server_hosts') AND type in (N'U'))
BEGIN	
	/* ***** 44) Create table dbo.sma_sql_server_hosts ***************************** */
		/*
			ALTER TABLE dbo.sma_sql_server_hosts SET ( SYSTEM_VERSIONING = OFF);
			drop table dbo.sma_sql_server_hosts;
			drop table dbo.sma_sql_server_hosts_history;
		*/
	create table dbo.sma_sql_server_hosts
	(
		[server] varchar(125) not null,
		[host_name] varchar(125) not null,
		[host_ips] varchar(80) null,
		[host_distribution] varchar(200) null,
		[processor_name] varchar(200) null,
		[ram_mb] bigint null,
		[cpu_count] smallint null,
		[wsfc_name] varchar(125) null,
		[wsfc_ip1] varchar(15) null,
		[wsfc_ip2] varchar(15) null,
		[is_quarantined] bit not null default 0,
		[is_decommissioned] bit not null default 0,
		[more_info] varchar(2000) null

		,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
		,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
		,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

		,constraint [pk_sma_sql_server_hosts] primary key clustered ([server],[host_name])
		,constraint [fk_sma_sql_server_hosts__server] foreign key ([server]) references dbo.sma_servers ([server])
	)
	WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.sma_sql_server_hosts_history));
END
go

if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '45) Create table dbo.sma_hadr_ag';
go
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.sma_hadr_ag') AND type in (N'U'))
BEGIN
	/* ***** 45) Create table dbo.sma_hadr_ag ***************************** */
		/*
			ALTER TABLE dbo.sma_hadr_ag SET ( SYSTEM_VERSIONING = OFF);
			drop table dbo.sma_hadr_ag;
			drop table dbo.sma_hadr_ag_history;
		*/
	create table dbo.sma_hadr_ag
	(
		[server] varchar(125) not null,
		[ag_name] varchar(125) not null,
		[ag_replicas_CSV] varchar(2000) not null,
		[preferred_role] varchar(50) not null default 'Secondary',
		[current_role] varchar(50) not null default 'Secondary',
		[ag_databases_CSV] varchar(max) null,
		[ag_listener_name] varchar(125) null,
		[ag_listener_ip1] varchar(15) null,
		[ag_listener_ip2] varchar(15) null,
		[backup_preference] varchar(125) null,
		[backup_replica] varchar(125) null,
		[is_decommissioned] bit not null default 0,
		[remarks] varchar(2000) null

		,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
		,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
		,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

		,constraint [pk_sma_hadr_ag] primary key clustered ([server],[ag_name])
		,index [ag_listener_ip1] nonclustered ([ag_listener_ip1])
		,index [ag_listener_ip2] nonclustered ([ag_listener_ip2])
		,constraint [fk_sma_hadr_ag__server] foreign key ([server]) references dbo.sma_servers ([server])
		,constraint [chk_preferred_role] check ( [preferred_role] in ('Primary', 'Secondary') )
		,constraint [chk_current_role] check ( [current_role] in ('Primary', 'Secondary') )
		,constraint [chk_backup_preference] check ( [backup_preference] in ('Prefer Secondary','Secondary only','Primary','Any Replica') )
	)
	with (system_versioning = on (history_table = dbo.sma_hadr_ag_history));
END
go


if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '46) Create table dbo.sma_hadr_sql_cluster';
go
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.sma_hadr_sql_cluster') AND type in (N'U'))
BEGIN
	/* ***** 46) Create table dbo.sma_hadr_sql_cluster ***************************** */
		/*
			ALTER TABLE dbo.sma_hadr_sql_cluster SET ( SYSTEM_VERSIONING = OFF);
			drop table dbo.sma_hadr_sql_cluster;
			drop table dbo.sma_hadr_sql_cluster_history;
		*/
	create table dbo.sma_hadr_sql_cluster
	(
		[server] varchar(125) not null,
		[sql_cluster_network_name] varchar(125) not null,
		[preferred_owner_node] varchar(50) null,
		[sql_cluster_ip1] varchar(15) null,
		[sql_cluster_ip2] varchar(15) null,
		[is_decommissioned] bit not null default 0,
		[remarks] varchar(2000) null

		,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
		,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
		,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

		,constraint [pk_sma_hadr_sql_cluster] primary key clustered ([server])
		,index [sql_cluster_network_name] nonclustered ([sql_cluster_network_name])
		,index [sql_cluster_ip1] nonclustered ([sql_cluster_ip1])
		,index [sql_cluster_ip2] nonclustered ([sql_cluster_ip2])
		,constraint [fk_sma_hadr_sql_cluster__server] foreign key ([server]) references dbo.sma_servers ([server])
	)
	with (system_versioning = on (history_table = dbo.sma_hadr_sql_cluster_history));
END
go


if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '47) Create table dbo.sma_hadr_mirroring';
go
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.sma_hadr_mirroring') AND type in (N'U'))
BEGIN
	/* ***** 47) Create table dbo.sma_hadr_mirroring ***************************** */
		/*
			ALTER TABLE dbo.sma_hadr_mirroring SET ( SYSTEM_VERSIONING = OFF);
			drop table dbo.sma_hadr_mirroring;
			drop table dbo.sma_hadr_mirroring_history;
		*/
	create table dbo.sma_hadr_mirroring
	(
		[server] varchar(125) not null,
		[preferred_role] varchar(125) not null default 'Principal',
		[mirroring_partner_server] varchar(125) not null,
		[witness_server] varchar(125) null,
		[is_decommissioned] bit not null default 0,
		[remarks] varchar(2000) null

		,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
		,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
		,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

		,constraint [pk_sma_hadr_mirroring] primary key clustered ([server])
		,constraint [fk_sma_hadr_mirroring__server] foreign key ([server]) references dbo.sma_servers ([server])
	)
	with (system_versioning = on (history_table = dbo.sma_hadr_mirroring_history));
END
go


if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '48) Create table dbo.sma_hadr_log_shipping';
go
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.sma_hadr_log_shipping') AND type in (N'U'))
BEGIN
	/* ***** 48) Create table dbo.sma_hadr_log_shipping ***************************** */
		/*
			ALTER TABLE dbo.sma_hadr_log_shipping SET ( SYSTEM_VERSIONING = OFF);
			drop table dbo.sma_hadr_log_shipping;
			drop table dbo.sma_hadr_log_shipping_history;
		*/
	create table dbo.sma_hadr_log_shipping
	(
		[server] varchar(125) not null,
		[databases_CSV] varchar(2000) not null,
		[source_server] varchar(125) not null,
		[is_decommissioned] bit not null default 0,
		[remarks] varchar(2000) null

		,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
		,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
		,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

		,constraint [pk_sma_hadr_log_shipping] primary key clustered ([server],[source_server])
		,constraint [fk_sma_hadr_log_shipping__server] foreign key ([server]) references dbo.sma_servers ([server])
	)
	with (system_versioning = on (history_table = dbo.sma_hadr_log_shipping_history));
END
go


if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '49) Create table dbo.sma_hadr_transaction_replication_publishers';
go
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.sma_hadr_transaction_replication_publishers') AND type in (N'U'))
BEGIN
	/* ***** 49) Create table dbo.sma_hadr_transaction_replication_publishers ***************************** */
		/*
			ALTER TABLE dbo.sma_hadr_transaction_replication_publishers SET ( SYSTEM_VERSIONING = OFF);
			drop table dbo.sma_hadr_transaction_replication_publishers;
			drop table dbo.sma_hadr_transaction_replication_publishers_history;
		*/
	create table dbo.sma_hadr_transaction_replication_publishers
	(
		[server] varchar(125) not null,
		[distributor_server] varchar(125) not null,
		[subscribers_CSV] varchar(2000) not null,
		[published_databases_CSV] varchar(2000) not null,
		[is_decommissioned] bit not null default 0,
		[remarks] varchar(2000) null

		,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
		,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
		,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

		,constraint [pk_sma_hadr_transaction_replication_publishers] primary key clustered ([server])
		,constraint [fk_sma_hadr_transaction_replication_publishers__server] foreign key ([server]) references dbo.sma_servers ([server])
	)
	with (system_versioning = on (history_table = dbo.sma_hadr_transaction_replication_publishers_history));
END
go


if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '50) Create table dbo.sma_applications';
go
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.sma_applications') AND type in (N'U'))
BEGIN
	/* ***** 50) Create table dbo.sma_applications ***************************** */
		/*
			ALTER TABLE dbo.sma_applications SET ( SYSTEM_VERSIONING = OFF);
			drop table dbo.sma_applications;
			drop table dbo.sma_applications_history;
		*/
	create table dbo.sma_applications
	(
		[application_name] varchar(125) not null,
		[application_owner_email] varchar(125) not null,
		[app_team_email] varchar(125) null,
		[primary_contact_email] varchar(125) null,
		[is_decommissioned] bit not null default 0,
		[more_info] varchar(2000) null,
		[remarks] varchar(2000) null

		,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
		,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
		,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

		,constraint [pk_sma_applications] primary key clustered ([application_name])
	)
	with (system_versioning = on (history_table = dbo.sma_applications_history));
END
go


if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '51) Create table dbo.sma_applications_server_xref';
go
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.sma_applications_server_xref') AND type in (N'U'))
BEGIN
	/* ***** 51) Create table dbo.sma_applications_server_xref ***************************** */
		/*
			ALTER TABLE dbo.sma_applications_server_xref SET ( SYSTEM_VERSIONING = OFF);
			drop table dbo.sma_applications_server_xref;
			drop table dbo.sma_applications_server_xref_history;
		*/
	create table dbo.sma_applications_server_xref
	(
		[server] varchar(125) not null,
		[application_name] varchar(125) not null,
		[is_valid] bit not null default 0,
		[more_info] varchar(2000) null,
		[remarks] varchar(2000) null

		,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
		,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
		,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

		,constraint [pk_sma_applications_server_xref] primary key clustered ([server],[application_name])
		,index [application_name] nonclustered ([application_name])
		,constraint [fk_sma_applications_server_xref__server] foreign key ([server]) references dbo.sma_servers ([server])
		,constraint [fk_sma_applications_server_xref__application_name] foreign key ([application_name]) references dbo.sma_applications ([application_name])
	)
	with (system_versioning = on (history_table = dbo.sma_applications_server_xref_history));
END
go


if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '52) Create table dbo.sma_applications_database_xref';
go
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.sma_applications_database_xref') AND type in (N'U'))
BEGIN
	/* ***** 52) Create table dbo.sma_applications_database_xref ***************************** */
		/*
			ALTER TABLE dbo.sma_applications_database_xref SET ( SYSTEM_VERSIONING = OFF);
			drop table dbo.sma_applications_database_xref;
			drop table dbo.sma_applications_database_xref_history;
		*/
	create table dbo.sma_applications_database_xref
	(
		[server] varchar(125) not null,
		[database_name] varchar(125) not null,
		[application_name] varchar(125) not null,
		[is_valid] bit not null default 0,
		[more_info] varchar(2000) null,
		[remarks] varchar(2000) null

		,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
		,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
		,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

		,constraint [pk_sma_applications_database_xref] primary key clustered ([server],[database_name])
		,index [application_name] nonclustered ([application_name])
		,constraint [fk_sma_applications_database_xref__server] foreign key ([server]) references dbo.sma_servers ([server])
		,constraint [fk_sma_applications_database_xref__application_name] foreign key ([application_name]) references dbo.sma_applications ([application_name])
	)
	with (system_versioning = on (history_table = dbo.sma_applications_database_xref_history));
END
go


/*	***** 53) Create view dbo.sma_sql_servers **************************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '53) Create view dbo.sma_sql_servers';
go
create or alter view dbo.sma_sql_servers
as
select	server = case when s.server = 'ATPR0SVDNTRY160' then '10.253.33.160' else s.server end, 
		server_port = coalesce(id.sql_instance_port, s.server_port), s.domain, s.friendly_name, 
		s.stability, s.hadr_strategy, hosts = hosts.hosts, s.backup_strategy,
		s.server_owner_email, 
		at_server_name = coalesce(asi.at_server_name,ei.at_server_name), 
		server_name = coalesce(asi.server_name,ei.server_name), 
		asi.machine_name, [current_host_name] = asi.host_name,
		--ag.ag_replicas_CSV, ag.ag_listener_name, ag.ag_listener_ip1, ag.ag_listener_ip2,
		agr.ag_replicas, agr.ag_listeners,
		sc.sql_cluster_network_name,
		product_version = coalesce(asi.product_version,ei.product_version),
		edition = coalesce(asi.edition, ei.edition),
		ei.has_PII_data,
		total_physical_memory_kb = coalesce(asi.total_physical_memory_kb, ei.total_physical_memory_kb),
		cpu_count = coalesce(asi.cpu_count, ei.cpu_count),
		ei.data_center,		
		[server_purpose] = ei.purpose,
		ei.known_challenges,		
		s.is_onboarded,
		s.is_decommissioned,
		[server_more_info] = s.more_info,
		[sql_server_remarks] = ei.remarks
from dbo.sma_servers s
left join dbo.sma_sql_server_extended_info ei
	on ei.server = s.server
left join dbo.vw_all_server_info asi
	on asi.srv_name = s.server
outer apply (
		select top 1 id.sql_instance_port, id.sql_instance
		from dbo.instance_details id
		where id.is_enabled = 1
		and id.sql_instance = s.server
		and id.is_alias = 0
	) id
outer apply (
	select STUFF(
			(SELECT ', ' + h.host_name+'('+h.host_ips+')'
			FROM dbo.sma_sql_server_hosts h
			where 1=1
			and h.server = s.server
			and h.is_decommissioned = 0
			FOR XML PATH (''))
			, 1, 1, '')  AS hosts
	) hosts
outer apply (
	select STUFF((	SELECT ', ' + [ag_replica]
					from (
							select distinct [ag_replica] = ltrim(rtrim(r.value))
							from dbo.sma_hadr_ag ag
							outer apply string_split(ag.ag_replicas_CSV,',') r
							where 1=1
							and ag.is_decommissioned = 0
							and ag.server = s.server
						) agr
					FOR XML PATH (''))
			, 1, 1, '')  AS ag_replicas,

			STUFF((	SELECT ', ' + ag.ag_listener_name+'('+ag.ag_listener_ip1+coalesce(','+ag.ag_listener_ip2,'')+')'
					from dbo.sma_hadr_ag ag
					where 1=1
					and ag.is_decommissioned = 0
					and ag.server = s.server
					FOR XML PATH (''))
			, 1, 1, '')  AS ag_listeners
	) agr
left join dbo.sma_hadr_sql_cluster sc
	on sc.server = s.server
	and sc.is_decommissioned = 0
where 1=1
and s.is_decommissioned = 0;
go


/*	***** 54) Create view dbo.sma_sql_servers_including_offline **************************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '54) Create view dbo.sma_sql_servers_including_offline';
go
create or alter view dbo.sma_sql_servers_including_offline
as
select	server = case when s.server = 'ATPR0SVDNTRY160' then '10.253.33.160' else s.server end, 
		server_port = coalesce(id.sql_instance_port, s.server_port), s.domain, s.friendly_name, 
		s.stability, s.hadr_strategy, hosts = hosts.hosts, s.backup_strategy,
		s.server_owner_email, 
		at_server_name = coalesce(asi.at_server_name,ei.at_server_name), 
		server_name = coalesce(asi.server_name,ei.server_name), 
		asi.machine_name, [current_host_name] = asi.host_name,
		--ag.ag_replicas_CSV, ag.ag_listener_name, ag.ag_listener_ip1, ag.ag_listener_ip2,
		agr.ag_replicas, agr.ag_listeners,
		sc.sql_cluster_network_name,
		product_version = coalesce(asi.product_version,ei.product_version),
		edition = coalesce(asi.edition, ei.edition),
		ei.has_PII_data,
		total_physical_memory_kb = coalesce(asi.total_physical_memory_kb, ei.total_physical_memory_kb),
		cpu_count = coalesce(asi.cpu_count, ei.cpu_count),
		ei.data_center,		
		[server_purpose] = ei.purpose,
		ei.known_challenges,		
		s.is_onboarded,
		s.is_decommissioned,
		[server_more_info] = s.more_info,
		[sql_server_remarks] = ei.remarks
from dbo.sma_servers s
left join dbo.sma_sql_server_extended_info ei
	on ei.server = s.server
left join dbo.vw_all_server_info asi
	on asi.srv_name = s.server
outer apply (
		select top 1 id.sql_instance_port, id.sql_instance, id.host_name
		from dbo.instance_details id
		where id.is_enabled = 1
		and id.sql_instance = s.server
		and id.is_alias = 0
	) id
outer apply (
	select STUFF(
         (SELECT ', ' + h.host_name+'('+h.host_ips+')'
          FROM dbo.sma_sql_server_hosts h
          where 1=1
		  and h.server = s.server
		  --and h.is_decommissioned = 0
          FOR XML PATH (''))
          , 1, 1, '')  AS hosts
	) hosts
outer apply (
	select STUFF((	SELECT ', ' + [ag_replica]
					from (
							select distinct [ag_replica] = ltrim(rtrim(r.value))
							from dbo.sma_hadr_ag ag
							outer apply string_split(ag.ag_replicas_CSV,',') r
							where 1=1
							--and ag.is_decommissioned = 0
							and ag.server = s.server
						) agr
					FOR XML PATH (''))
			, 1, 1, '')  AS ag_replicas,

			STUFF((	SELECT ', ' + ag.ag_listener_name+'('+ag.ag_listener_ip1+coalesce(','+ag.ag_listener_ip2,'')+')'
					from dbo.sma_hadr_ag ag
					where 1=1
					--and ag.is_decommissioned = 0
					and ag.server = s.server
					FOR XML PATH (''))
			, 1, 1, '')  AS ag_listeners
	) agr
left join dbo.sma_hadr_sql_cluster sc
	on sc.server = s.server
	--and sc.is_decommissioned = 0
where 1=1
--and s.is_decommissioned = 0
go


/* ***** 55) Create Trigger dbo.tgr_dml__fk_validation_sma_servers__server on dbo.sma_servers ***************************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '55) Create Trigger dbo.tgr_dml__fk_validation_sma_servers__server on dbo.sma_servers';
GO
-- drop trigger dbo.tgr_dml__fk_validation_sma_servers__server;
create or alter trigger dbo.tgr_dml__fk_validation_sma_servers__server
	on dbo.sma_servers
	for insert, update
as 
begin
	if exists (select * from inserted)
		and not exists (	select 1/0 from dbo.instance_details id join inserted i on i.server = id.sql_instance and id.is_alias = 0 )
	begin
		RAISERROR ('Server entry should exist in [dbo].[instance_details] prior to adding in Inventory table [dbo].[sma_servers].', 16, 1);  
		ROLLBACK TRANSACTION; 
	end
end
go

/* ***** 56) Create Trigger dbo.tgr_dml__sma_servers__server_owner_email__validation on dbo.sma_servers ***************************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '56) Create Trigger dbo.tgr_dml__sma_servers__server_owner_email__validation on dbo.sma_servers';
GO
create or alter trigger dbo.tgr_dml__sma_servers__server_owner_email__validation
	on dbo.sma_servers
	for insert, update
as 
begin
	declare @count int = 0;
	;with t_chk_emails as (
		select s.server_owner_email, emails.email_address
				,is_valid_email = case when emails.email_address LIKE '%_@__%.__%' AND PATINDEX('%[^a-z,0-9,@,.,_,\-]%', emails.email_address) = 0 
									then 1 else 0 end
		from inserted s
		cross apply (select email_address = ltrim(rtrim(value)) from string_split(s.server_owner_email,';')) emails
		where 1=1
		and s.server_owner_email is not null
		and	emails.email_address <> ''
	)
	select @count = COUNT(*)
	from t_chk_emails e
	where e.is_valid_email = 0;

	if @count > 0
	begin
		RAISERROR ('Provided email address(s) is invalid. Kindly ensure to provide semicolon(;) separated emails if multiple emails are provided.', 16, 1);  
		ROLLBACK TRANSACTION; 
	end
end
go


/* ***** 57) Create Trigger dbo.tgr_dml__sma_applications__email__validation on dbo.sma_applications ***************************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '57) Create Trigger dbo.tgr_dml__sma_applications__email__validation on dbo.sma_applications';
GO
create or alter trigger dbo.tgr_dml__sma_applications__email__validation
	on dbo.sma_applications
	for insert, update
as 
begin
	declare @count int = 0;

	;with t_emails as (
		select emails_concatenated = coalesce(application_owner_email+';','')+coalesce(app_team_email+';','')+coalesce(primary_contact_email+';','')
		from inserted 
		where 1=1
		and (application_owner_email is not null or app_team_email is not null or primary_contact_email is not null)
	)
	,t_chk_emails as (
		select s.emails_concatenated, emails.email_address
				,is_valid_email = case when emails.email_address LIKE '%_@__%.__%' AND PATINDEX('%[^a-z,0-9,@,.,_,\-]%', emails.email_address) = 0 
									then 1 else 0 end
		from t_emails s
		cross apply (select email_address = ltrim(rtrim(value)) from string_split(s.emails_concatenated,';')) emails
		where 1=1
		and s.emails_concatenated is not null
		and	emails.email_address <> ''
	)
	select @count = COUNT(*)
	from t_chk_emails e
	where e.is_valid_email = 0;

	if @count > 0
	begin
		RAISERROR ('Provided email address(s) is invalid. Kindly ensure to provide semicolon(;) separated emails if multiple emails are provided.', 16, 1);  
		ROLLBACK TRANSACTION; 
	end
end
go


/* ***** 58) Create table dbo.login_email_mapping ***************************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '58) Create table dbo.login_email_mapping';
go
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.login_email_mapping') AND type in (N'U'))
BEGIN	
	-- drop table [dbo].[login_email_mapping]
	create table dbo.login_email_mapping
	(
		sql_instance_ip		varchar(20) not null,	-- should match with link server name
		sql_instance_name	varchar(125) null,	-- serverproprty(servername)
		server_alias_name	varchar(125) null,
		at_server_name		varchar(125) null,
		[host_name]			varchar(125) null,
		login_name			varchar(125) not null,
		[is_app_login]		bit not null,
		owner_group_email	varchar(2000) not null,
		created_date		datetime not null default getdate(),
		created_by			varchar(125) not null default suser_name(),
		is_deleted			bit not null default 0,
		remarks				text null,
		mapping_id			bigint null

		,index CI_login_email_mapping unique clustered (sql_instance_ip, login_name)
	);
END
go


/* ***** 59) Create Trigger dbo.tgr_dml__login_email_mapping__email__validation on dbo.login_email_mapping ***************************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '59) Create Trigger dbo.tgr_dml__login_email_mapping__email__validation on dbo.login_email_mapping';
go
create or alter trigger dbo.tgr_dml__login_email_mapping__email__validation
	on dbo.login_email_mapping
	for insert, update
as 
begin
	declare @count int = 0;
	;with t_chk_emails as (
		select s.owner_group_email, emails.email_address
				,is_valid_email = case when emails.email_address LIKE '%_@__%.__%' AND PATINDEX('%[^a-z,0-9,@,.,_,\-]%', emails.email_address) = 0 
									then 1 else 0 end
		from inserted s
		cross apply (select email_address = ltrim(rtrim(value)) from string_split(s.owner_group_email,';')) emails
		where 1=1
		and s.owner_group_email is not null
		and	emails.email_address <> ''
	)
	select @count = COUNT(*)
	from t_chk_emails e
	where e.is_valid_email = 0;

	if @count > 0
	begin
		RAISERROR ('Provided email address(s) is invalid. Kindly ensure to provide semicolon(;) separated emails if multiple emails are provided.', 16, 1);  
		ROLLBACK TRANSACTION; 
	end
end
go


/* ***** 60) Create table dbo.all_server_login_expiry_info ***************************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '60) Create table dbo.all_server_login_expiry_info';
go
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.all_server_login_expiry_info') AND type in (N'U'))
BEGIN	
	-- drop table dbo.all_server_login_expiry_info
	CREATE TABLE dbo.all_server_login_expiry_info
	(
		collection_time datetime2 not null default sysdatetime(),
		sql_instance	varchar(125),
		[host_name]		varchar(125),	
		login_name		varchar(125),
		login_sid 		varbinary(85),
		create_date		datetime,
		modify_date		datetime,
		default_database_name varchar(125),
		is_policy_checked bit,
		is_expiration_checked bit,
		is_sysadmin bit,
		password_last_set_time	datetime,
		days_until_expiration	int,
		password_expiration	datetime,
		is_expired	bit,
		is_locked	bit,		
		owner_group_email varchar(500)		

		,index CI_all_server_login_expiry_info clustered (collection_time, sql_instance)
	);
END
go

-- 60.a) Add dbo.purge_table entry for dbo.all_server_login_expiry_info
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '60.a) Add dbo.purge_table entry for dbo.all_server_login_expiry_info';
go
if not exists (select 1 from dbo.purge_table where table_name = 'dbo.all_server_login_expiry_info')
begin
	insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.all_server_login_expiry_info', 
			date_key = 'collection_time', 
			retention_days = 30, 
			purge_row_size = 100000,
			reference = 'SQLMonitor Data Collection'
end
go


/* ***** 61) Create table dbo.server_login_expiry_collection_computed used for [usp_send_login_expiry_emails] ***************************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '61) Create table dbo.server_login_expiry_collection_computed used for [usp_send_login_expiry_emails]';
go
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.server_login_expiry_collection_computed') AND type in (N'U'))
BEGIN	
	create table dbo.server_login_expiry_collection_computed
	(	sql_instance varchar(125) not null,
		collection_time_latest datetime2 not null,
		server_owner_email varchar(2000) null,
		app_team_emails varchar(2000) null,
		application_owner_emails varchar(2000) null

		,index CI_server_login_expiry_collection_computed unique clustered (sql_instance, collection_time_latest)
	);
END
go


/* ***** 62) Create table dbo.all_server_login_expiry_info_dashboard used for [usp_send_login_expiry_emails] ***************************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '62) Create table dbo.all_server_login_expiry_info_dashboard used for [usp_send_login_expiry_emails]';
go
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.all_server_login_expiry_info_dashboard') AND type in (N'U'))
BEGIN	
	-- drop table dbo.all_server_login_expiry_info_dashboard
	create table dbo.all_server_login_expiry_info_dashboard
	(
		[collection_time] [datetime2](7) NOT NULL,
		[sql_instance] [varchar](125) not null,
		[login_name] [varchar](125) not null,
		[is_sysadmin] [bit] NULL,
		[is_app_login] [bit] null,
		[password_last_set_time] [datetime] NULL,
		[password_expiration] [datetime] NULL,
		[is_expired] [bit] NULL,
		[is_locked] [bit] NULL,
		[days_until_expiration] [int] NULL,
		[login_owner_group_email] [varchar](4000) NULL,
		[server_owner_email] [varchar](2000) NULL,
		[app_team_emails] [varchar](2000) NULL,
		[application_owner_emails] [varchar](2000) NULL

		,index CI_all_server_login_expiry_info_dashboard unique clustered (sql_instance, login_name)
	);
END
go


/* ***** 63) Create table dbo.sma_servers_logs used for [usp_wrapper_populate_sma_sql_instance] ***************************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '63) Create table dbo.sma_servers_logs used for [usp_wrapper_populate_sma_sql_instance]';
go
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.sma_servers_logs') AND type in (N'U'))
BEGIN	
	--drop table dbo.sma_servers_logs
	create table dbo.sma_servers_logs
	(	id int identity(1,1) not null,
		sql_instance varchar(125) not null,
		start_time datetime2 not null default sysdatetime(),
		status varchar(125) default 'start',
		remarks varchar(2000) null

		,constraint pk_sma_servers_logs primary key clustered (id)
		,index sql_instance nonclustered (sql_instance, start_time)
	);
END
go

/* ***** 64) Create table dbo.sma_wrapper_sql_server_hosts  ***************************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '64) Create table dbo.sma_wrapper_sql_server_hosts';
go
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.sma_wrapper_sql_server_hosts') AND type in (N'U'))
BEGIN	
	create table dbo.sma_wrapper_sql_server_hosts 
	(	server varchar(125), [host_name] varchar(125), exists_in_DMV bit, exists_in_SM bit, 
		exists_in_INV bit, disabled_in_INV bit, collection_time datetime2 default getdate()
	);
END
go

/* ***** 65) Create view dbo.vw_all_server_logins ***************************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '65) Create view dbo.vw_all_server_logins';
go
create or alter view dbo.vw_all_server_logins
as
select	lei.sql_instance, s.server_port, lei.login_name, lei.login_sid, 
		is_app_login = coalesce(lem.is_app_login, dba.is_app_login),
		lei.is_sysadmin, login_create_date = lei.create_date,
		lei.is_expiration_checked, lei.is_policy_checked, ct.server_owner_email,
		[login_owner_group_email] = coalesce(lem.owner_group_email, dba.owner_group_email), 
		days_until_expiration, password_expiration, lei.modify_date, lei.password_last_set_time, 
		lei.collection_time
from dbo.server_login_expiry_collection_computed ct
inner join dbo.all_server_login_expiry_info lei
	on lei.sql_instance = ct.sql_instance and lei.collection_time = ct.collection_time_latest
left join dbo.login_email_mapping lem
	on	lem.sql_instance_ip = lei.sql_instance and lem.login_name = lei.login_name
		and lem.is_deleted = 0
outer apply (select dba.owner_group_email, dba.is_app_login from dbo.login_email_mapping dba 
				where dba.sql_instance_ip = '*' and login_name = lei.login_name) dba
left join dbo.sma_servers s
	on s.server = ct.[sql_instance]
	and s.is_decommissioned = 0
where 1=1;
go

/* ***** 66) Create table dbo.sma_server_aliases  ***************************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '66) Create table dbo.sma_server_aliases';
go
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.sma_server_aliases') AND type in (N'U'))
BEGIN
	--drop table dbo.sma_server_aliases
	create table dbo.sma_server_aliases
	(	alias_name varchar(255) not null,
		prod_ip varchar(20) null,
		dr_ip varchar(20) null, 
		listener_name varchar(125) null,
		remarks varchar(2000) null, 
		is_active bit default 1 not null,
		created_date datetime2 not null default sysdatetime(),

		index ci__sma_server_aliases unique clustered (alias_name)
	)
END
go


/* ***** 67) Create function dbo.fn_IsJobRunning  ***************************** */
if (PROGRAM_NAME() <> 'Microsoft SQL Server Management Studio - Query')
	print '67) Create function dbo.fn_IsJobRunning';
go
IF OBJECT_ID('dbo.fn_IsJobRunning') IS NULL
	EXEC ('CREATE FUNCTION dbo.fn_IsJobRunning() RETURNS BIT BEGIN RETURN 1 END');
GO
ALTER FUNCTION dbo.fn_IsJobRunning(@p_JobName VARCHAR(2000)) 
	RETURNS BIT
AS
BEGIN
	/*
		Created By:		Ajay Dwivedi
		Created Date:	Apr 07, 2019
		Version:			0.0
	*/
	DECLARE @returnValue BIT
	SET @returnValue = 0;

	IF EXISTS(	SELECT	1
				FROM msdb.dbo.sysjobactivity ja 
				LEFT JOIN msdb.dbo.sysjobhistory jh 
					ON ja.job_history_id = jh.instance_id
				JOIN msdb.dbo.sysjobs j 
				ON ja.job_id = j.job_id
				JOIN msdb.dbo.sysjobsteps js
					ON ja.job_id = js.job_id
					AND ISNULL(ja.last_executed_step_id,0)+1 = js.step_id
				WHERE ja.session_id = (SELECT TOP 1 session_id FROM msdb.dbo.syssessions ORDER BY agent_start_date DESC)
				AND ja.start_execution_date is not null
				AND ja.stop_execution_date is null
				AND LTRIM(RTRIM(j.name)) = @p_JobName
	)
	BEGIN
		SET @returnValue = 1;
	END

	RETURN @returnValue
END
GO



/*
-- SQLMonitor core table
select * from dbo.instance_details

select * from dbo.sma_servers
select * from dbo.sma_sql_server_extended_info
select * from dbo.sma_sql_server_hosts
select * from dbo.sma_hadr_ag
select * from dbo.sma_hadr_sql_cluster
select * from dbo.sma_hadr_mirroring
select * from dbo.sma_hadr_log_shipping
select * from dbo.sma_hadr_transaction_replication_publishers
select * from dbo.sma_applications
select * from dbo.sma_applications_server_xref
select * from dbo.sma_applications_database_xref
select * from dbo.instance_details_history

select * from dbo.sma_errorlog

select * from dbo.login_email_mapping -- login owner mapping
select * from dbo.all_server_login_expiry_info_dashboard
dbo.usp_collect_all_server_login_expiration_info -> collect login info data from all servers
dbo.usp_send_login_expiry_emails -> send mail notifications for login expiry

-- Populate Inventory Table
exec dbo.usp_populate_sma_sql_instance @server = '192.168.1.2' ,@execute = 1 ,@verbose = 2;

*/