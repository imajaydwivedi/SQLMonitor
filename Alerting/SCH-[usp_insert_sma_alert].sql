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

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_insert_sma_alert')
    EXEC ('CREATE PROC dbo.usp_insert_sma_alert AS SELECT ''stub version, to be replaced''')
GO

ALTER PROCEDURE dbo.usp_insert_sma_alert
	@alert_id_OUTPUT bigint output,
	@alert_key varchar(255),
	@frequency_minutes int,
	@alert_owner_team varchar(125) = 'DBA',
	@state varchar(15),
	@severity varchar(15),
	@logger varchar(125),
	@header varchar(500),
	@description nvarchar(max),
	@affected_servers affected_servers_type readonly,
	@is_pre_existing_OUTPUT bit = 0 output,
	@verbose tinyint = 0
AS 
BEGIN
/*
	Version:		1.0.0
	Date:			2024-Oct-10

declare @_alert_id bigint;
declare @_alert_id_RETURN bigint;
declare @_is_pre_existing bit;
declare @_affected_servers as affected_servers_type;

insert @_affected_servers
values ('21L-LTPABL-1187',NULL);

exec @_alert_id_RETURN = dbo.usp_insert_sma_alert
		@alert_id_OUTPUT = @_alert_id output,
		@is_pre_existing_OUTPUT = @_is_pre_existing output,
		@alert_key = 'Alert-DiskSpace - [21L-LTPABL-1187]',
		@frequency_minutes = 30,
		@alert_owner_team = 'DBA',
		@state = 'Active',
		@severity = 'High',
		@logger = 'Wrapper-AlertDiskSpace.ps1',
		@header = 'Disk Space Issue on [21L-LTPABL-1187]',
		@description = N'Disk space issue on [21L-LTPABL-1187]',
		@affected_servers = @_affected_servers,
		@verbose = 2;

select [result_alert_id] = @_alert_id_RETURN, [alert_id] = @_alert_id, [is_pre_existing] = @_is_pre_existing;
go
*/
	SET NOCOUNT ON;

	declare @_tbl_sma_alert table (alert_id bigint);

	--select * from dbo.sma_oncall_teams
	--dbo.sma_oncall_schedule
	--dbo.sma_alert_rules
	
	-- populate dbo.sma_alert if alert does not exist for same alert_key
	if exists (select * from dbo.sma_alert a where a.alert_key = @alert_key and a.state in ('Active','Suppressed','Cleared'))
	begin
		print 'alert with key ['+@alert_key+' already active.';
		set @is_pre_existing_OUTPUT = 1;

		insert @_tbl_sma_alert (alert_id)
		select id from dbo.sma_alert a 
		where 1=1
		and a.alert_key = @alert_key
		and a.state in ('Active','Suppressed','Cleared');
	end
	else
	begin
		print 'creating alert with key ['+@alert_key+'..';
		set @is_pre_existing_OUTPUT = 0;

		insert dbo.sma_alert (alert_key, alert_owner_team, state, severity, frequency_minutes)
		output inserted.id into @_tbl_sma_alert
		select @alert_key, @alert_owner_team, @state, @severity, @frequency_minutes;
	end

	select @alert_id_OUTPUT = alert_id from @_tbl_sma_alert;

	-- populate dbo.sma_alert_history
	insert dbo.sma_alert_history (alert_id, logger, header, description)
	select a.alert_id, @logger, @header, @description
	from @_tbl_sma_alert a;
	
	-- populate dbo.sma_alert_affected_servers
	;with cte_affected_servers as (
		select a.alert_id, s.sql_instance, s.host_name
		from @affected_servers s full outer join @_tbl_sma_alert a
			on 1=1
	)
	,cte_existing_data as (
		select s.alert_id, s.sql_instance, s.host_name
		from dbo.sma_alert_affected_servers s 
		inner join @_tbl_sma_alert a
			on a.alert_id = s.alert_id			
	)
	insert dbo.sma_alert_affected_servers (alert_id, sql_instance, host_name)
	select alert_id, sql_instance, host_name from cte_affected_servers i
	except
	select alert_id, sql_instance, host_name from cte_existing_data e;

	return @alert_id_OUTPUT;
END
GO

/*
declare @_alert_id bigint;
declare @_alert_id_RETURN bigint;
declare @_is_pre_existing bit;
declare @_affected_servers as affected_servers_type;

insert @_affected_servers
values ('21L-LTPABL-1187',NULL);

exec @_alert_id_RETURN = dbo.usp_insert_sma_alert
		@alert_id_OUTPUT = @_alert_id output,
		@is_pre_existing_OUTPUT = @_is_pre_existing output,
		@alert_key = 'Alert-DiskSpace - [21L-LTPABL-1187]',
		@frequency_minutes = 30,
		@alert_owner_team = 'DBA',
		@state = 'Active',
		@severity = 'High',
		@logger = 'Wrapper-AlertDiskSpace.ps1',
		@header = 'Disk Space Issue on [21L-LTPABL-1187]',
		@description = N'Disk space issue on [21L-LTPABL-1187]',
		@affected_servers = @_affected_servers,
		@verbose = 2;

select [result_alert_id] = @_alert_id_RETURN, [alert_id] = @_alert_id, [is_pre_existing] = @_is_pre_existing;
go
*/

/*
select * from dbo.sma_alert
select * from dbo.sma_alert_history
select * from dbo.sma_alert_affected_servers


truncate table dbo.sma_alert
truncate table dbo.sma_alert_history
truncate table dbo.sma_alert_affected_servers
*/