USE DBA
GO

CREATE OR ALTER procedure dbo.usp_compute_all_server_volatile_info_history_hourly
		@verbose tinyint = 2
AS
BEGIN
/*	Purpose: Optimize table dbo.all_server_volatile_info_history
			Aggregate data from dbo.all_server_volatile_info_history, and save it into hourly trend in tables
				dbo.all_server_volatile_info_history_hourly_p99
				dbo.all_server_volatile_info_history_hourly_p993
	
	Modifications: 2024-Nov-28 - Ajay - Initial Draft

	exec dbo.usp_compute_all_server_volatile_info_history_hourly
			@verbose = 2, 
			@days_for_analysis = 15,
			--@filter_server = 'SqlPractice',
			@drop_create_staging_tables = 0;

*/
	set nocount on;
	set xact_abort on;

	if @verbose > 0
		print 'Inside procedure dbo.usp_compute_all_server_volatile_info_history_hourly.';

	-- declare variables
	declare @_sql nvarchar(max);
	declare @_params nvarchar(max);
	declare @_start_time datetime2 = sysdatetime();
	declare @_tab nchar(1) = '  ';
	declare @_crlf nchar(2) = nchar(10);

	declare @collection_time_latest_p99 datetime2;
	declare @collection_time_latest_p993 datetime2;

	select @collection_time_latest_p99 = coalesce(max(collection_time),'17-08-1989')
	from dbo.all_server_volatile_info_history_hourly_p99 hh;

	select @collection_time_latest_p993 = coalesce(max(collection_time),'17-08-1989')
	from dbo.all_server_volatile_info_history_hourly_p993 hh;

	select @collection_time_latest_p99, @collection_time_latest_p993;

END
GO

/*
select *
from DBA.dbo.lama_computed_metrics with (nolock)
where memory_action_needed <> 'no' or cpu_action_needed <> 'no'

*/