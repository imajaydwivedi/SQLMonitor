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

CREATE OR ALTER PROCEDURE dbo.usp_collect_all_server_login_expiration_info
	@verbose tinyint = 0, /* 0 = No logs, 1 = Print Message, 2 = Table Result + Messages */
	@execute bit = 1, /* 0 = Don't execute */
	@generate_error_scenario bit = 0, /* 1 = Generate Error */
	@test_server varchar(125) = null /* list of servers for testing */
AS

BEGIN
/*
	Purpose:		Gather login metrics like last_password_set_date, expiry_date etc from each SQLServer using Linked Server object.
					[dbo].[all_server_login_expiry] is target table.

	Modifications:	2024-08-26 - Ajay - Adding extra column [is_app_login] in dbo.login_email_mapping

	Examples:	
		exec usp_collect_all_server_login_expiration_info @verbose = 2, @execute = 0, @test_server = '192.168.1.5'				
		exec usp_collect_all_server_login_expiration_info @verbose = 2, @execute = 1, @test_server = '192.168.1.5'
		exec usp_collect_all_server_login_expiration_info @verbose = 2, @execute = 1, @test_server = '192.168.1.5', @generate_error_scenario = 1
*/
	SET NOCOUNT ON;

	declare @_start_time datetime2 = sysdatetime();
	declare @_crlf nchar(2) = char(10)+char(13);
	declare @_long_star_line varchar(500) = replicate('*',75);
	declare @_server_count int = 0;

	declare @_failed_server_count int = 0;
	DECLARE	@_errorNumber int,
			@_errorSeverity int,
			@_errorState int,
			@_errorLine int,
			@_errorMessage nvarchar(4000);
	DECLARE @_caller_program nvarchar(255);

	set @_caller_program = case when HOST_NAME() like '(dba) Get-AllServerInfo%'
								then HOST_NAME()
								else PROGRAM_NAME()
								end;

	if @verbose >= 1
		print 'Declare variables..'

	DECLARE @_sql_Instance VARCHAR(125);
	DECLARE @_sql NVARCHAR(MAX);

	if @verbose >= 1
		print 'Get list of servers..'

	if OBJECT_ID('tempdb..#servers') is not null
		drop table #servers;
	;with t_servers as (
		select distinct id.sql_instance 
		from dbo.instance_details id 
		where id.is_enabled = 1 and id.is_available = 1 and id.is_alias = 0
	)
	select * into #servers from t_servers
	where @test_server is null or sql_instance = @test_server;

	select @_server_count = count(*) from #servers;

	if @verbose >= 1
		print convert(varchar,@_server_count)+ ' servers found for looping.';

	if @verbose >= 2
	begin
		select t.RunningQuery, s.*
		from #servers s
		full outer join 
			(select RunningQuery = '#servers') t
			on 1=1;
	end

	DECLARE curServers CURSOR LOCAL FAST_FORWARD FOR 
		select sql_instance from #servers
		where 1=1
		order by sql_instance;

	OPEN curServers
	FETCH NEXT FROM curServers INTO @_sql_Instance;

	WHILE @@FETCH_STATUS = 0
	BEGIN
		if @verbose >= 1
			print @_crlf+@_long_star_line+@_crlf+'Working on server ['+@_sql_Instance+']..'+@_crlf
		set @_sql = '
		;with t_login_info as (
			SELECT 	[host_name] = convert(varchar,COALESCE(SERVERPROPERTY(''ComputerNamePhysicalNetBIOS''),SERVERPROPERTY(''ServerName''))),
					[login_name] = sl.name, [login_sid] = sl.sid, [create_date] = sl.create_date,
					[modify_date] = sl.modify_date, sl.default_database_name,
					sl.is_policy_checked, sl.is_expiration_checked,
					[is_sysadmin] = IS_SRVROLEMEMBER (''sysadmin'', sl.name),
					[password_last_set_time] = convert(datetime,LOGINPROPERTY([sl].name, ''PasswordLastSetTime''),120),
					[days_until_expiration] = CONVERT(int,LOGINPROPERTY([sl].name, ''DaysUntilExpiration'')),
					[is_expired] = convert(bit,LOGINPROPERTY([sl].name, ''IsExpired'')),
					[is_locked] = convert(bit,LOGINPROPERTY([sl].name, ''IsLocked''))
				from master.sys.sql_logins sl
				where sl.type_desc = ''SQL_LOGIN''
				and sl.is_disabled = 0
		)
		select	[sql_instance] = '''+@_sql_Instance+''', [host_name], 
				[login_name], [login_sid], [create_date], [modify_date], 
				default_database_name, is_policy_checked, is_expiration_checked, [is_sysadmin],
				[password_last_set_time], [days_until_expiration],
				[password_expiration] = case when [days_until_expiration] <= 0 
										then case when DATEADD(dd,60,[password_last_set_time]) < getdate() 
													then DATEADD(dd,60,[password_last_set_time]) 
													else DATEADD(dd,-1,cast(getdate() as date)) 
													end
										else DATEADD(dd,[days_until_expiration],cast(GETDATE() as date))
										end,
				[is_expired], [is_locked] = [is_locked]
		from t_login_info'

		if @generate_error_scenario = 1
			set @_sql = replace(@_sql, '[is_locked] = [is_locked]', '[is_locked] = 1/0');
		
		if @@SERVERNAME <> @_sql_Instance
			set @_sql = 'select * from openquery(' + QUOTENAME(@_sql_Instance) + ', '''+ replace(@_sql,'''','''''') + ''')';
		BEGIN TRY
			if @verbose >= 2
				PRINT @_sql
			if @execute = 1
			begin
				INSERT INTO dbo.all_server_login_expiry_info 
				(sql_instance, [host_name], login_name, login_sid, create_date, modify_date, 
				default_database_name, is_policy_checked, is_expiration_checked, [is_sysadmin],
				[password_last_set_time], [days_until_expiration], [password_expiration], [is_expired], [is_locked] )
				EXEC (@_sql)
			end
			else
				EXEC (@_sql)
		END TRY
		BEGIN CATCH
			SELECT	@_errorNumber	 = Error_Number()
					,@_errorSeverity = Error_Severity()
					,@_errorState	 = Error_State()
					,@_errorLine	 = Error_Line()
					,@_errorMessage	 = Error_Message();

			set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

			print @_crlf+@_long_star_line+@_crlf+'Error Occurred while processing server ['+@_sql_Instance+'].'+@_crlf+@_errorMessage+@_crlf+@_long_star_line+@_crlf;

			insert [dbo].[sma_errorlog]
			([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
			select	[collection_time] = @_start_time, [function_name] = 'usp_collect_all_server_login_expiration_info', 
					[function_call_arguments] = '', [server] = @_sql_Instance, [error] = @_errorMessage, 
					[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = @_caller_program;
		END CATCH

		FETCH NEXT FROM curServers INTO @_sql_Instance;
	END

	CLOSE curServers
	DEALLOCATE curServers

	set @_failed_server_count = (select count(*) from [dbo].[sma_errorlog] where collection_time = @_start_time);
	if @_failed_server_count > 0 
	begin
		print @_crlf+@_long_star_line+@_crlf+@_long_star_line+@_crlf+'Error occurred for a total of '+
					convert(varchar,@_failed_server_count)+' servers.'
					+@_crlf+@_long_star_line+@_crlf+@_long_star_line+@_crlf;

		if @verbose >= 2
			select RunningQuery = '[dbo].[sma_errorlog]', * 
			from [dbo].[sma_errorlog] where collection_time = @_start_time;		
	end
END
GO



