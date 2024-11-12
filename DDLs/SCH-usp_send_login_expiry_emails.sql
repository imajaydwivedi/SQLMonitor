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

CREATE OR ALTER PROCEDURE dbo.usp_send_login_expiry_emails
	@warning_threshold_days int = 20,
	@critical_threshold_days int = 10,
	@pager_duty_threshold_days int = 13,
	@mail_subject nvarchar(2000) = '*** IMPORTANT - Database Password Expiration Notification',
	@job_name nvarchar(255) = '(dba) Send Login Expiry EMails',	
	@dba_manager_threshold_days int = 7,	
	@copy_dba_team_for_all_mails bit = 0, /* 1 = Copy dba team for all email notifications */
	@sre_vp_threshold_days int = 7,	
	@cto_threshold_days int = 3,	
	@noc_threshold_days int = 12,
	@verbose tinyint = 0, /* 0 = No logs, 1 = Print Message, 2 = Table Result + Messages */
	@send_mail bit = 1, /* 0 = Don't execute */
	@enable_dba_mail_while_testing bit = 0, /* 1 = Send mails to DBA team for testing */
	@generate_error_scenario bit = 0, /* 1 = Generate Error */
	@test_server varchar(125) = null /* list of servers for testing */
AS
BEGIN
/*
	Purpose:		Send mail notification to login owners

	Modifications:	2024-09-12 - Ajay - Send mail to server owner when login owner is missing
					2024-08-27 - Ajay - Get emails & params from dbo.sma_params
					2024-04-01 - Ajay - Initial Draft

	Examples:	
		exec dbo.usp_send_login_expiry_emails @verbose = 2, @execute = 0, @test_server = '192.168.1.5'				
		exec dbo.usp_send_login_expiry_emails @verbose = 2, @send_mail = 0, @enable_dba_mail_while_testing = 1;

		exec dbo.usp_send_login_expiry_emails
					@verbose = 2, 
					@send_mail = 0, 
					@warning_threshold_days = 365,
					@enable_dba_mail_while_testing = 1;
*/
	SET NOCOUNT ON;

	declare @_start_time datetime2 = sysdatetime();
	if @verbose >= 1
		print 'Declare variables..'

	declare @dba_team_email_id varchar(125) = 'dba_team@gmail.com'
	declare @dba_manager_email_id varchar(125) = 'dba.manager@gmail.com' /* Email for DBA Manager */
	declare @sre_vp_email_id varchar(125) = 'sre.vp@gmail.com' /* Email for SRE Senior VP */
	declare @cto_email_id varchar(125) = 'cto@gmail.com' /* Email for CTO */
	declare @noc_email_id varchar(125) = 'noc@gmail.com' /* NOC team */
	declare @url_for_GrafanaDashboardPortal varchar(1000) = 'http://localhost:3000/d/';
	declare @url_login_expiry_dashboard_panel varchar(1000) = 'distributed_live_dashboard_all_servers/monitoring-live-all-servers?orgId=1&refresh=1m&viewPanel=885'
	declare @url_for_login_password_reset varchar(1000) = '#'
	declare @url_for_dba_slack_channel varchar(1000) = 'workspace.slack.com/archives/unique_id';

	select @dba_team_email_id = p.param_value from dbo.sma_params p where p.param_key = 'dba_team_email_id';
	select @dba_manager_email_id = p.param_value from dbo.sma_params p where p.param_key = 'dba_manager_email_id';
	select @sre_vp_email_id = p.param_value from dbo.sma_params p where p.param_key = 'sre_vp_email_id';
	select @cto_email_id = p.param_value from dbo.sma_params p where p.param_key = 'cto_email_id';
	select @noc_email_id = p.param_value from dbo.sma_params p where p.param_key = 'noc_email_id';

	select @url_for_dba_slack_channel = p.param_value from dbo.sma_params p where p.param_key = 'url_for_dba_slack_channel';
	select @url_for_GrafanaDashboardPortal = p.param_value from dbo.sma_params p where p.param_key = 'GrafanaDashboardPortal';
	select @url_login_expiry_dashboard_panel = p.param_value from dbo.sma_params p where p.param_key = 'url_login_expiry_dashboard_panel';
	select @url_for_login_password_reset = p.param_value from dbo.sma_params p where p.param_key = 'url_for_login_password_reset';
	

	IF (@dba_team_email_id IS NULL OR @dba_team_email_id = 'dba_team@gmail.com')
		raiserror ('@dba_team_email_id is mandatory parameter', 20, -1) with log;
	IF (@dba_manager_email_id IS NULL OR @dba_manager_email_id = 'dba.manager@gmail.com') AND @verbose = 0
		raiserror ('@dba_manager_email_id is mandatory parameter', 20, -1) with log;
	IF (@sre_vp_email_id IS NULL OR @sre_vp_email_id = 'sre.vp@gmail.com') AND @verbose = 0
		raiserror ('@sre_vp_email_id is mandatory parameter', 20, -1) with log;
	IF (@noc_email_id IS NULL OR @noc_email_id = 'noc@gmail.com') AND @verbose = 0
		raiserror ('@noc_email_id is mandatory parameter', 20, -1) with log;
	IF (@cto_email_id IS NULL OR @cto_email_id = 'cto@gmail.com') AND @verbose = 0
		raiserror ('@cto_email_id is mandatory parameter', 20, -1) with log;

	declare @_crlf nchar(2) = char(10)+char(13);
	declare @_long_star_line varchar(500) = replicate('*',75);
	declare @_server_count int = 0;
	declare @_url_login_expiry_dashboard_panel varchar(1000);

	set @_url_login_expiry_dashboard_panel = @url_for_GrafanaDashboardPortal+@url_login_expiry_dashboard_panel;

	declare @_failed_server_count int = 0;
	declare	@_errorNumber int,
			@_errorSeverity int,
			@_errorState int,
			@_errorLine int,
			@_errorMessage nvarchar(4000);

	declare @_mail_subject varchar(max)
	declare @_mail_html nvarchar(max)
	declare @_mail_html_title nvarchar(max);
	declare @_mail_html_body  nvarchar(MAX); 
	declare @_table_headline nvarchar(max);
	declare @_table_header nvarchar(max);
	declare @_table_data nvarchar(max);	
	declare @_style_css nvarchar(max);
	declare @_recepient varchar(4000);
	declare @_copy_recipients varchar(500);
	declare @_owner_email varchar(4000)

	-- Table to store emails for each login
	create table #login_email_xref_raw
	(sql_instance varchar(125), login_name varchar(125), mail_recipient varchar(500));

	-- Declare cluster variables
	declare @c_sql_instance varchar(125);
	declare @c_login_name varchar(125);
	declare @c_server_owner_email varchar(500);
	declare @c_login_owner_group_email varchar(500);
	declare @c_is_app_login bit;
	declare @c_app_team_emails varchar(500);
	declare @c_application_owner_emails varchar(500);
	declare @c_mail_recipient varchar(2000);

	if @copy_dba_team_for_all_mails = 1
		set @_copy_recipients = @dba_team_email_id

	-- Get email ids per sql server
	if OBJECT_ID('tempdb..#applications_server_xref') is not null
		drop table #applications_server_xref;
	select	s.server, 
			application_owner_emails = STUFF(
										 (select '; ' + a.application_owner_email
										  from dbo.sma_applications a
										  inner join dbo.sma_applications_server_xref x
											on x.application_name = a.application_name and x.is_valid = 1
										  where x.server = s.server
										  for xml path (''))
										  , 1, 1, ''), 
			app_team_emails = STUFF(
										 (select '; ' + a.app_team_email
										  from dbo.sma_applications a
										  inner join dbo.sma_applications_server_xref x
											on x.application_name = a.application_name and x.is_valid = 1
										  where x.server = s.server
										  for xml path (''))
										  , 1, 1, '')
	into #applications_server_xref
	from dbo.sma_servers s
	where s.is_decommissioned = 0;

	if @verbose >= 2
	begin
		select t.RunningQuery, s.*
		from #applications_server_xref s
		full outer join 
			(select RunningQuery = '#applications_server_xref') t
			on 1=1
		where s.app_team_emails is not null or s.application_owner_emails is not null;
	end

	-- Get list of servers & latest data collection time
	truncate table dbo.server_login_expiry_collection_computed;
	;with t_sql_instances as (
		select sql_instance 
		from dbo.instance_details id 
		where id.is_enabled = 1 and id.is_alias = 0
		group by sql_instance
	)
	,t_server_login_expiry_collection as (
		select id.sql_instance, collection_time_latest = max(collection_time)
		from t_sql_instances id
		inner join dbo.all_server_login_expiry_info lei
			on lei.sql_instance = id.sql_instance
		where lei.collection_time >= DATEADD(day,-7,getdate())
		group by id.sql_instance
	)
	insert dbo.server_login_expiry_collection_computed
	(sql_instance, collection_time_latest, server_owner_email, app_team_emails, application_owner_emails)
	select lec.sql_instance, collection_time_latest, s.server_owner_email, asx.app_team_emails, asx.application_owner_emails
	from t_server_login_expiry_collection lec
	left join dbo.sma_servers s
		on s.server = lec.sql_instance
	left join #applications_server_xref asx
		on asx.server = lec.sql_instance;

	if @verbose >= 2
	begin
		select t.RunningQuery, s.*
		from dbo.server_login_expiry_collection_computed s
		full outer join 
			(select RunningQuery = 'dbo.server_login_expiry_collection_computed') t
			on 1=1;
	end

	-- Get logins which are about to expire in @warning_threshold_days
	truncate table [dbo].[all_server_login_expiry_info_dashboard];
	insert dbo.all_server_login_expiry_info_dashboard
	([collection_time], [sql_instance], [login_name], [is_sysadmin], [is_app_login], [password_last_set_time], [password_expiration], [is_expired], [is_locked], [days_until_expiration], [login_owner_group_email], [server_owner_email], [app_team_emails], [application_owner_emails])
	select	lei.collection_time, lei.sql_instance, lei.login_name, lei.is_sysadmin, 
			[is_app_login] = coalesce(lem.is_app_login, dba.is_app_login), lei.password_last_set_time,
			lei.password_expiration, lei.is_expired, lei.is_locked, days_until_expiration,
			[login_owner_group_email] = coalesce(lem.owner_group_email, dba.owner_group_email), ct.server_owner_email,
			ct.app_team_emails, ct.application_owner_emails
	from dbo.server_login_expiry_collection_computed ct
	inner join dbo.all_server_login_expiry_info lei
		on lei.sql_instance = ct.sql_instance and lei.collection_time = ct.collection_time_latest
	left join dbo.login_email_mapping lem
		on	lem.sql_instance_ip = lei.sql_instance and lem.login_name = lei.login_name
			and lem.is_deleted = 0
	outer apply (select dba.owner_group_email, dba.is_app_login from dbo.login_email_mapping dba 
					where dba.sql_instance_ip = '*' and login_name = lei.login_name) dba
	where 1=1
	and lei.is_expiration_checked = 1
	and lei.days_until_expiration <= @warning_threshold_days;

	if @verbose >= 2
	begin
		select t.RunningQuery, s.*
		from dbo.all_server_login_expiry_info_dashboard s
		full outer join 
			(select RunningQuery = 'dbo.all_server_login_expiry_info_dashboard') t
			on 1=1
		--order by s.sql_instance, s.login_name;
		--order by s.password_expiration desc
	end

	if 'Get-Unique-Emails-Per-Login' = 'Get-Unique-Emails-Per-Login'
	begin
		declare cur_sql_logins cursor local fast_forward for 
			select	sql_instance, login_name, login_owner_group_email, is_app_login,
					server_owner_email, app_team_emails, application_owner_emails
			from dbo.all_server_login_expiry_info_dashboard;
	
		open cur_sql_logins;
		fetch next from cur_sql_logins into @c_sql_instance, @c_login_name, @c_login_owner_group_email, @c_is_app_login,
											@c_server_owner_email, @c_app_team_emails, @c_application_owner_emails;

		while @@FETCH_STATUS = 0
		begin
			if @verbose >= 1
				print 'Working on {server:login :: '+@c_sql_instance+':'+@c_login_name+'}..';

			-- If login belongs to DBA or no Non-DBA owner found
			if	(	left(lower(@c_login_name),6) = 'dba.'
				or	@c_login_owner_group_email = @dba_team_email_id
				--or	@c_login_owner_group_email like ('%'+@dba_team_email_id+'%')
				or	(@c_login_owner_group_email is null and @c_server_owner_email is null and @c_app_team_emails is null and @c_application_owner_emails is null)
				)
			begin
				-- Enter dba email id if not individual DBA login
				insert #login_email_xref_raw (sql_instance, login_name, mail_recipient)
				SELECT	@c_sql_instance, @c_login_name, 
						mail_recipient = case when @c_login_owner_group_email is not null 
											then @c_login_owner_group_email 
											else @dba_team_email_id 
											end;
			end
			else -- Non-DBA login
			begin
				-- Split [login_owner_group_email]
				insert #login_email_xref_raw (sql_instance, login_name, mail_recipient)
				SELECT @c_sql_instance, @c_login_name, ltrim(rtrim(value))
				from string_split(@c_login_owner_group_email, ';');

				-- Split [server_owner_email]
				if @c_login_owner_group_email is null
				begin
					insert #login_email_xref_raw (sql_instance, login_name, mail_recipient)
					SELECT @c_sql_instance, @c_login_name, ltrim(rtrim(value)) 
					from string_split(@c_server_owner_email, ';');
				end

				if(@c_is_app_login = 1)
				begin
					-- Split [app_team_emails]
					insert #login_email_xref_raw (sql_instance, login_name, mail_recipient)
					SELECT @c_sql_instance, @c_login_name, ltrim(rtrim(value)) 
					from string_split(@c_app_team_emails, ';');

					-- Split [application_owner_emails]
					insert #login_email_xref_raw (sql_instance, login_name, mail_recipient)
					SELECT @c_sql_instance, @c_login_name, ltrim(rtrim(value)) 
					from string_split(@c_application_owner_emails, ';');
				end
			end

			fetch next from cur_sql_logins into @c_sql_instance, @c_login_name, @c_login_owner_group_email, @c_is_app_login,
											@c_server_owner_email, @c_app_team_emails, @c_application_owner_emails;
		end

		CLOSE cur_sql_logins
		DEALLOCATE cur_sql_logins

		-- Create unique list of emails for login notification
		if OBJECT_ID('tempdb..#login_email_xref') is not null
			drop table #login_email_xref;
		select sql_instance, login_name, mail_recipient
		into #login_email_xref
		from #login_email_xref_raw
		group by sql_instance, login_name, mail_recipient;

		if @verbose >= 2
		begin
			select t.RunningQuery, s.*
			from #login_email_xref s
			full outer join 
				(select RunningQuery = '#login_email_xref') t
				on 1=1;
		end
	end -- 'Get-Unique-Emails-Per-Login'

	set @_style_css = '<style>		
		.tableContainerDiv {
			overflow: auto;
			max-height: 30em;
		}
		th {
			background-color: black;
			color: white;
			position: sticky;
			top: 0;
		}
		td {
			text-align: center;
		}
		tbody {
			display: block;
			/* height: 50px; */
			overflow: auto;
		}
		thead, tbody tr {
			display: table;
			width: 100%;
			table-layout: fixed;
		}
		thead {
			/* width: calc( 100% - 1em ) */
			width: calc( 100% )
		}

		.bg_desert {
			background-color: #FAD5A5;
		}
		.bg_green {
			background-color: green;
		}
		.bg_key {
			background-color: #7fd1f2;
		}
		.bg_metric_neutral {
			background-color: #C663AD;
		}
		.bg_pistachio {
			background-color: #93C572;
		}
		.bg_orange {
			background-color: orange;
		}
		.bg_red {
			background-color: red;
		}
		.bg_red_light {
			background-color: #F79F9D;
		}
		.bg_yellow {
			background-color: #FFFF00;
		}
		.bg_yellow_dark {
			background-color: #FFBF00;
		}
		.bg_yellow_medium {
			background-color: #FFEA00;
		}
		.bg_yellow_light {
			background-color: #FAFA33;
		}
		.bg_yellow_canary {
			background-color: #FFFF8F;
		}
		.bg_yellow_gold {
			background-color: #FFD700;
		}
		.scrollit {
			overflow: auto;
		}
		p.normal {
		  font-weight: normal;
		}

		p.light {
		  font-weight: lighter;
		}

		p.thick {
		  font-weight: bold;
		}

		p.thicker {
		  font-weight: 900;
		}

		span.underline {
			text-decoration: underline;
		}
		span.thick {
			font-weight: 900;
		}
		</style>';

	if @verbose > 0
	begin
		print @_long_star_line;
		print '@_style_css => '+@_crlf+@_style_css;
		print @_long_star_line;
	end

	if 'Send-Mail-Notification-2-Owners' = 'Send-Mail-Notification-2-Owners'
	begin
		declare cur_recipients cursor local fast_forward for
			select distinct x.mail_recipient
			from #login_email_xref x;

		open cur_recipients;
		fetch next from cur_recipients into @c_mail_recipient;

		while @@FETCH_STATUS = 0
		begin
			if @verbose >= 1
				print 'Sending mail for '''+@c_mail_recipient+'''..';

			begin try
				set @_table_data = null;
				
				set @_table_headline = N'<h3><a href="'+@_url_login_expiry_dashboard_panel+'" target="_blank">NOTE: Following login passwords are expiring/expired. Ensure to reset the password for continous working of applications.</a></h3>'+@_crlf+
									N'<div><p><span class="underline thick">How to Resolve - Method 01</span>: If login password has not expired yet, then password can be reset using following tsql - <pre><code> ALTER LOGIN [your_login_name_here] WITH PASSWORD=N''new_login_password_here'' </code></pre></p></div>'+@_crlf+
									N'<div><p><span class="underline thick">How to Resolve - Method 02</span>: Kindly raise a DBA request and share same on <a href="'+@url_for_dba_slack_channel+'" target="_blank">#dba slack channel</a>.</p></div>'+@_crlf+
									N'<div><p><span class="underline thick">How to Resolve - Method 03</span>: Utilize login reset portal <a href="'+@url_for_login_password_reset+'" target="_blank">'+@url_for_login_password_reset+'</a>.</p></div>'+@_crlf

				set @_table_header = N'<tr><th>SQL Instance</th> <th>Login Name</th> <th>Login Type</th> <th>Days Until Expiry</th>'
								+N'<th>Password Last Set</th> <th>Expired</th> <th>Locked</th>'
								+N'<th>Collection Time</th>'+@_crlf;
				
				;with t_login_info as (
					select lei.sql_instance, lei.login_name, lei.is_app_login, lei.days_until_expiration,
							lei.password_last_set_time, lei.is_expired, lei.is_locked,
							lei.collection_time
					from #login_email_xref lex
					inner join dbo.all_server_login_expiry_info_dashboard lei
						on lei.sql_instance = lex.sql_instance and lei.login_name = lex.login_name
					where lex.mail_recipient = @c_mail_recipient
				)
				,t_table_rows as (
					select	'<tr>'
							+'<td class="bg_key"><a href="'+@_url_login_expiry_dashboard_panel+'&var-log_expiry_sql_instance='+sql_instance+'" target="_blank">'+sql_instance+'</a></td>'
							+'<td class="bg_key"><a href="'+@_url_login_expiry_dashboard_panel+'&var-login_expiry_login_name='+login_name+'" target="_blank">'+login_name+'</a></td>'
							+'<td class="'+(case when is_app_login = 1 then 'bg_yellow' else 'bg_none' end)+'">'
										+(case when is_app_login = 1 then 'App' when is_app_login = 0 then 'Human User' else '' end)+'</td>'
							+'<td class="'+(case when days_until_expiration <= @critical_threshold_days then 'bg_red' else 'bg_orange' end)+'">'
										+convert(varchar,days_until_expiration)+'</td>'
							+'<td>'+isnull(convert(varchar,password_last_set_time,121),'')+'</td>'
							+'<td class="'+(case when is_expired = 1 then 'bg_red' else 'bg_none' end)+'">'
										+(case when is_expired = 1 then 'Yes' else 'No' end)+'</td>'
							+'<td class="'+(case when is_locked = 1 then 'bg_red' else 'bg_none' end)+'">'
										+(case when is_locked = 1 then 'Yes' else 'No' end)+'</td>'
							+'<td class="bg_key">'+convert(varchar,collection_time,121)+'</td>'
							+'</tr>' as [table_row]
					from t_login_info
				)
				select @_table_data = coalesce(@_table_data+' '+[table_row],[table_row])
				from t_table_rows
				--order by [table_row];

				set @_mail_html_body = @_table_headline+'<div class="tableContainerDiv"><table border="1">'
										+'<caption>@warning_threshold_days:'+convert(varchar,@warning_threshold_days)
										+' || @critical_threshold_days:'+convert(varchar,@critical_threshold_days)
										+' || @cto_threshold_days:'+convert(varchar,@cto_threshold_days)
										+'</caption>'
										+'<thead>'+@_table_header+'</thead><tbody>'+isnull(@_table_data,'')+'</tbody></table></div>'+@_crlf;

				set @_mail_subject = @mail_subject+' - '+convert(varchar,@_start_time,120);
				set @_mail_html = '<html>'
										+N'<head>'
										+N'<title>'+@_mail_subject+'</title>'
										+@_style_css
										+N'</head>'
										+N'<body>'
										+N'<h1><a href="'+@_url_login_expiry_dashboard_panel+'" target="_blank">'+@_mail_subject+'</a></h1>'
										+N'<p>'+@_mail_html_body+N'</p>'
										+N'<br><br><br><p>Regards,<br>Job ['+@job_name+']</p>'
										+N'</body>';	
				if @verbose >= 1
				begin
					print @_long_star_line
					print @_crlf+@_mail_html+@_crlf
				end

				if @send_mail = 1 or (@enable_dba_mail_while_testing = 1 and @c_mail_recipient = @dba_team_email_id)
				begin
					if @_table_data is not null
					begin
						if @send_mail = 0
							set @_mail_subject = 'Testing - '+@_mail_subject
						exec msdb.dbo.sp_send_dbmail 
										@recipients = @c_mail_recipient,
										@copy_recipients = @_copy_recipients,
										@subject = @_mail_subject,
										@body = @_mail_html,
										@body_format = 'HTML';
					end
				end

			end try
			begin catch
				SELECT	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
									'. State: '+convert(varchar,isnull(@_errorState,'')) +
									'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
									'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error Occurred while sending mail for '''+@c_mail_recipient+'''.'+@_crlf+@_errorMessage+@_crlf+@_long_star_line+@_crlf;

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_send_login_expiry_emails', 
						[function_call_arguments] = @c_mail_recipient, [server] = null, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = program_name();
			end catch

			fetch next from cur_recipients into @c_mail_recipient;
		end

		close cur_recipients
		deallocate cur_recipients

	end -- 'Send-Mail-Notification-2-Owners'


	if 'Send-Mail-Notification-2-NOC' = 'Send-Mail-Notification-2-NOC'
	begin
		set @c_mail_recipient = @noc_email_id+';'+@dba_team_email_id;

		if @verbose >= 1
			print 'Sending mail for '''+@noc_email_id+'''..';

		begin try
			set @_table_data = null;

			set @_table_headline = N'<h3><a href="'+@_url_login_expiry_dashboard_panel+'" target="_blank">NOTE: Following login passwords are expiring/expired within '+convert(varchar,@noc_threshold_days)+' days. Ensure to reset the password for continous working of applications.</a></h3>'+@_crlf+
									N'<div><p><span class="underline thick">How to Resolve - Method 01</span>: If login password has not expired yet, then password can be reset using following tsql - <pre><code> ALTER LOGIN [your_login_name_here] WITH PASSWORD=N''new_login_password_here'' </code></pre></p></div>'+@_crlf+
									N'<div><p><span class="underline thick">How to Resolve - Method 02</span>: Kindly raise a DBA request and share same on <a href="'+@url_for_dba_slack_channel+'" target="_blank">#angel-dba slack channel</a>.</p></div>'+@_crlf+
									N'<div><p><span class="underline thick">How to Resolve - Method 03</span>: Utilize login reset portal <a href="'+@url_for_login_password_reset+'" target="_blank">'+@url_for_login_password_reset+'</a>.</p></div>'+@_crlf

			set @_table_header = N'<tr><th>SQL Instance</th> <th>Login Name</th> <th>Login Type</th> <th>Days Until Expiry</th>'
							+N'<th>Password Last Set</th> <th>Expired</th> <th>Locked</th>'
							+N'<th>Collection Time</th>'+@_crlf;
				
			;with t_login_info as (
				select lei.sql_instance, lei.login_name, lei.is_app_login, lei.days_until_expiration,
						lei.password_last_set_time, lei.is_expired, lei.is_locked,
						lei.collection_time, lei.login_owner_group_email
				from dbo.all_server_login_expiry_info_dashboard lei
				--inner join #login_email_xref lex
				--	on lei.sql_instance = lex.sql_instance and lei.login_name = lex.login_name
				where 1=1
				and (		left(lower(lei.login_name),6) <> 'dba.' 
						--and coalesce(lei.login_owner_group_email,'') <> @dba_team_email_id
					)
				and lei.days_until_expiration <= @noc_threshold_days
			)
			,t_table_rows as (
				select	'<tr>'
							+'<td class="bg_key"><a href="'+@_url_login_expiry_dashboard_panel+'&var-log_expiry_sql_instance='+sql_instance+'" target="_blank">'+sql_instance+'</a></td>'
							+'<td class="bg_key"><a href="'+@_url_login_expiry_dashboard_panel+'&var-login_expiry_login_name='+login_name+'" target="_blank">'+login_name+'</a></td>'
						+'<td class="'+(case when is_app_login = 1 then 'bg_yellow' else 'bg_none' end)+'">'
										+(case when is_app_login = 1 then 'App' when is_app_login = 0 then 'Human User' else '' end)+'</td>'
						+'<td class="'+(case when days_until_expiration <= @critical_threshold_days then 'bg_red' else 'bg_orange' end)+'">'
									+convert(varchar,days_until_expiration)+'</td>'
						+'<td>'+isnull(convert(varchar,password_last_set_time,121),'')+'</td>'
						+'<td class="'+(case when is_expired = 1 then 'bg_red' else 'bg_none' end)+'">'
									+(case when is_expired = 1 then 'Yes' else 'No' end)+'</td>'
						+'<td class="'+(case when is_locked = 1 then 'bg_red' else 'bg_none' end)+'">'
									+(case when is_locked = 1 then 'Yes' else 'No' end)+'</td>'
						+'<td class="bg_key">'+convert(varchar,collection_time,121)+'</td>'
						+'</tr>' as [table_row]
				from t_login_info
			)
			select @_table_data = coalesce(@_table_data+' '+[table_row],[table_row])
			from t_table_rows

			set @_mail_html_body = @_table_headline+'<div class="tableContainerDiv"><table border="1">'
									+'<caption>@warning_threshold_days:'+convert(varchar,@warning_threshold_days)
									+' || @critical_threshold_days:'+convert(varchar,@critical_threshold_days)
									+' || @noc_threshold_days:'+convert(varchar,@noc_threshold_days)
									+' || @sre_vp_threshold_days:'+convert(varchar,@sre_vp_threshold_days)
									+' || @cto_threshold_days:'+convert(varchar,@cto_threshold_days)
									+'</caption>'
									+'<thead>'+@_table_header+'</thead><tbody>'+isnull(@_table_data,'')+'</tbody></table></div>'+@_crlf;

			set @_mail_subject = @mail_subject+' - '+convert(varchar,@_start_time,120);
			set @_mail_html = '<html>'
									+N'<head>'
									+N'<title>'+@_mail_subject+'</title>'
									+@_style_css
									+N'</head>'
									+N'<body>'
									+N'<h1><a href="'+@_url_login_expiry_dashboard_panel+'" target="_blank">'+@_mail_subject+'</a></h1>'
									+N'<p>'+@_mail_html_body+N'</p>'
									+N'<br><br><br><p>Regards,<br>Job ['+@job_name+']</p>'
									+N'</body>';	
			if @verbose >= 1
			begin
				print @_long_star_line
				print @_crlf+@_mail_html+@_crlf
			end

			if @send_mail = 1 or @enable_dba_mail_while_testing = 1
			begin
				if @_table_data is not null
				begin
					if @send_mail = 0
					begin
						set @_mail_subject = 'Testing - NOC - '+@_mail_subject
						set @c_mail_recipient = @dba_team_email_id;
					end
					exec msdb.dbo.sp_send_dbmail 
										@recipients = @c_mail_recipient,
										@copy_recipients = @_copy_recipients,
										@subject = @_mail_subject,
										@body = @_mail_html,
										@body_format = 'HTML';
				end
			end

		end try
		begin catch
			SELECT	@_errorNumber	 = Error_Number()
					,@_errorSeverity = Error_Severity()
					,@_errorState	 = Error_State()
					,@_errorLine	 = Error_Line()
					,@_errorMessage	 = Error_Message();

			set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

			print @_crlf+@_long_star_line+@_crlf+'Error Occurred while sending mail for '''+@c_mail_recipient+'''.'+@_crlf+@_errorMessage+@_crlf+@_long_star_line+@_crlf;

			insert [dbo].[sma_errorlog]
			([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
			select	[collection_time] = @_start_time, [function_name] = 'usp_send_login_expiry_emails', 
					[function_call_arguments] = @c_mail_recipient, [server] = null, [error] = @_errorMessage, 
					[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = program_name();
		end catch

	end -- 'Send-Mail-Notification-2-NOC'



	if 'Send-Mail-Notification-2-SreVP' = 'Send-Mail-Notification-2-SreVP'
	begin
		set @c_mail_recipient = @sre_vp_email_id+';'+@dba_team_email_id;

		if @verbose >= 1
			print 'Sending mail for '''+@sre_vp_email_id+'''..';

		begin try
			set @_table_data = null;

			set @_table_headline = N'<h3><a href="'+@_url_login_expiry_dashboard_panel+'" target="_blank">NOTE: Following login passwords are expiring/expired. Ensure to reset the password for continous working of applications.</a></h3>'+@_crlf+
									N'<div><p><span class="underline thick">How to Resolve - Method 01</span>: If login password has not expired yet, then password can be reset using following tsql - <pre><code> ALTER LOGIN [your_login_name_here] WITH PASSWORD=N''new_login_password_here'' </code></pre></p></div>'+@_crlf+
									N'<div><p><span class="underline thick">How to Resolve - Method 02</span>: Kindly raise a DBA request and share same on <a href="'+@url_for_dba_slack_channel+'" target="_blank">#angel-dba slack channel</a>.</p></div>'+@_crlf+
									N'<div><p><span class="underline thick">How to Resolve - Method 03</span>: Utilize login reset portal <a href="'+@url_for_login_password_reset+'" target="_blank">'+@url_for_login_password_reset+'</a>.</p></div>'+@_crlf

			set @_table_header = N'<tr><th>SQL Instance</th> <th>Login Name</th> <th>Login Type</th> <th>Days Until Expiry</th>'
							+N'<th>Password Last Set</th> <th>Expired</th> <th>Locked</th>'
							+N'<th>Collection Time</th>'+@_crlf;
				
			;with t_login_info as (
				select lei.sql_instance, lei.login_name, lei.is_app_login, lei.days_until_expiration,
						lei.password_last_set_time, lei.is_expired, lei.is_locked,
						lei.collection_time, lei.login_owner_group_email
				from dbo.all_server_login_expiry_info_dashboard lei
				--inner join #login_email_xref lex
				--	on lei.sql_instance = lex.sql_instance and lei.login_name = lex.login_name
				where 1=1
				and (		left(lower(lei.login_name),6) <> 'dba.' 
						--and coalesce(lei.login_owner_group_email,'') <> @dba_team_email_id
					)
				and lei.days_until_expiration <= @sre_vp_threshold_days
				and (lei.is_app_login = 1 or lei.is_app_login is null)
			)
			,t_table_rows as (
				select	'<tr>'
							+'<td class="bg_key"><a href="'+@_url_login_expiry_dashboard_panel+'&var-log_expiry_sql_instance='+sql_instance+'" target="_blank">'+sql_instance+'</a></td>'
							+'<td class="bg_key"><a href="'+@_url_login_expiry_dashboard_panel+'&var-login_expiry_login_name='+login_name+'" target="_blank">'+login_name+'</a></td>'
						+'<td class="'+(case when is_app_login = 1 then 'bg_yellow' else 'bg_none' end)+'">'
										+(case when is_app_login = 1 then 'App' when is_app_login = 0 then 'Human User' else '' end)+'</td>'
						+'<td class="'+(case when days_until_expiration <= @critical_threshold_days then 'bg_red' else 'bg_orange' end)+'">'
									+convert(varchar,days_until_expiration)+'</td>'
						+'<td>'+isnull(convert(varchar,password_last_set_time,121),'')+'</td>'
						+'<td class="'+(case when is_expired = 1 then 'bg_red' else 'bg_none' end)+'">'
									+(case when is_expired = 1 then 'Yes' else 'No' end)+'</td>'
						+'<td class="'+(case when is_locked = 1 then 'bg_red' else 'bg_none' end)+'">'
									+(case when is_locked = 1 then 'Yes' else 'No' end)+'</td>'
						+'<td class="bg_key">'+convert(varchar,collection_time,121)+'</td>'
						+'</tr>' as [table_row]
				from t_login_info
			)
			select @_table_data = coalesce(@_table_data+' '+[table_row],[table_row])
			from t_table_rows

			set @_mail_html_body = @_table_headline+'<div class="tableContainerDiv"><table border="1">'
									+'<caption>@warning_threshold_days:'+convert(varchar,@warning_threshold_days)
									+' || @critical_threshold_days:'+convert(varchar,@critical_threshold_days)
									+' || @sre_vp_threshold_days:'+convert(varchar,@sre_vp_threshold_days)
									+' || @cto_threshold_days:'+convert(varchar,@cto_threshold_days)
									+'</caption>'
									+'<thead>'+@_table_header+'</thead><tbody>'+isnull(@_table_data,'')+'</tbody></table></div>'+@_crlf;

			set @_mail_subject = @mail_subject+' - '+convert(varchar,@_start_time,120);
			set @_mail_html = '<html>'
									+N'<head>'
									+N'<title>'+@_mail_subject+'</title>'
									+@_style_css
									+N'</head>'
									+N'<body>'
									+N'<h1><a href="'+@_url_login_expiry_dashboard_panel+'" target="_blank">'+@_mail_subject+'</a></h1>'
									+N'<p>'+@_mail_html_body+N'</p>'
									+N'<br><br><br><p>Regards,<br>Job ['+@job_name+']</p>'
									+N'</body>';	
			if @verbose >= 1
			begin
				print @_long_star_line
				print @_crlf+@_mail_html+@_crlf
			end

			if @send_mail = 1 or @enable_dba_mail_while_testing = 1
			begin
				if @_table_data is not null
				begin
					if @send_mail = 0
					begin
						set @_mail_subject = 'Testing - SRE VP - '+@_mail_subject
						set @c_mail_recipient = @dba_team_email_id;
					end
					exec msdb.dbo.sp_send_dbmail 
										@recipients = @c_mail_recipient,
										@copy_recipients = @_copy_recipients,
										@subject = @_mail_subject,
										@body = @_mail_html,
										@body_format = 'HTML';
				end
			end

		end try
		begin catch
			SELECT	@_errorNumber	 = Error_Number()
					,@_errorSeverity = Error_Severity()
					,@_errorState	 = Error_State()
					,@_errorLine	 = Error_Line()
					,@_errorMessage	 = Error_Message();

			set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

			print @_crlf+@_long_star_line+@_crlf+'Error Occurred while sending mail for '''+@c_mail_recipient+'''.'+@_crlf+@_errorMessage+@_crlf+@_long_star_line+@_crlf;

			insert [dbo].[sma_errorlog]
			([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
			select	[collection_time] = @_start_time, [function_name] = 'usp_send_login_expiry_emails', 
					[function_call_arguments] = @c_mail_recipient, [server] = null, [error] = @_errorMessage, 
					[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = program_name();
		end catch

	end -- 'Send-Mail-Notification-2-SreVP'


	if 'Send-Mail-Notification-2-CTO' = 'Send-Mail-Notification-2-CTO'
	begin
		set @c_mail_recipient = @cto_email_id+';'+@sre_vp_email_id+';'+@dba_team_email_id;

		if @verbose >= 1
			print 'Sending mail for '''+@cto_email_id+'''..';

		begin try
			set @_table_data = null;

			set @_table_headline = N'<h3><a href="'+@_url_login_expiry_dashboard_panel+'" target="_blank">NOTE: Following login passwords are expiring/expired. Ensure to reset the password for continous working of applications.</a></h3>'+@_crlf+
									N'<div><p><span class="underline thick">How to Resolve - Method 01</span>: If login password has not expired yet, then password can be reset using following tsql - <pre><code> ALTER LOGIN [your_login_name_here] WITH PASSWORD=N''new_login_password_here'' </code></pre></p></div>'+@_crlf+
									N'<div><p><span class="underline thick">How to Resolve - Method 02</span>: Kindly raise a DBA request and share same on <a href="'+@url_for_dba_slack_channel+'" target="_blank">#angel-dba slack channel</a>.</p></div>'+@_crlf+
									N'<div><p><span class="underline thick">How to Resolve - Method 03</span>: Utilize login reset portal <a href="'+@url_for_login_password_reset+'" target="_blank">'+@url_for_login_password_reset+'</a>.</p></div>'+@_crlf

			set @_table_header = N'<tr><th>SQL Instance</th> <th>Login Name</th> <th>Login Type</th> <th>Days Until Expiry</th>'
							+N'<th>Password Last Set</th> <th>Expired</th> <th>Locked</th>'
							+N'<th>Collection Time</th>'+@_crlf;
				
			;with t_login_info as (
				select lei.sql_instance, lei.login_name, lei.is_app_login, lei.days_until_expiration,
						lei.password_last_set_time, lei.is_expired, lei.is_locked,
						lei.collection_time, lei.login_owner_group_email
				from dbo.all_server_login_expiry_info_dashboard lei
				--inner join #login_email_xref lex
				--	on lei.sql_instance = lex.sql_instance and lei.login_name = lex.login_name
				where 1=1
				and left(lower(lei.login_name),6) <> 'dba.' 
				and coalesce(lei.login_owner_group_email,'') <> @dba_team_email_id
				and lei.days_until_expiration <= @cto_threshold_days
				and (lei.is_app_login is null or lei.is_app_login = 1)
			)
			,t_table_rows as (
				select	'<tr>'
							+'<td class="bg_key"><a href="'+@_url_login_expiry_dashboard_panel+'&var-log_expiry_sql_instance='+sql_instance+'" target="_blank">'+sql_instance+'</a></td>'
							+'<td class="bg_key"><a href="'+@_url_login_expiry_dashboard_panel+'&var-login_expiry_login_name='+login_name+'" target="_blank">'+login_name+'</a></td>'
						+'<td class="'+(case when is_app_login = 1 then 'bg_yellow' else 'bg_none' end)+'">'
										+(case when is_app_login = 1 then 'App' when is_app_login = 0 then 'Human User' else '' end)+'</td>'
						+'<td class="'+(case when days_until_expiration <= @critical_threshold_days then 'bg_red' else 'bg_orange' end)+'">'
									+convert(varchar,days_until_expiration)+'</td>'
						+'<td>'+isnull(convert(varchar,password_last_set_time,121),'')+'</td>'
						+'<td class="'+(case when is_expired = 1 then 'bg_red' else 'bg_none' end)+'">'
									+(case when is_expired = 1 then 'Yes' else 'No' end)+'</td>'
						+'<td class="'+(case when is_locked = 1 then 'bg_red' else 'bg_none' end)+'">'
									+(case when is_locked = 1 then 'Yes' else 'No' end)+'</td>'
						+'<td class="bg_key">'+convert(varchar,collection_time,121)+'</td>'
						+'</tr>' as [table_row]
				from t_login_info
			)
			select @_table_data = coalesce(@_table_data+' '+[table_row],[table_row])
			from t_table_rows

			set @_mail_html_body = @_table_headline+'<div class="tableContainerDiv"><table border="1">'
									+'<caption>@warning_threshold_days:'+convert(varchar,@warning_threshold_days)
									+' || @critical_threshold_days:'+convert(varchar,@critical_threshold_days)
									+' || @sre_vp_threshold_days:'+convert(varchar,@sre_vp_threshold_days)
									+' || @cto_threshold_days:'+convert(varchar,@cto_threshold_days)
									+'</caption>'
									+'<thead>'+@_table_header+'</thead><tbody>'+isnull(@_table_data,'')+'</tbody></table></div>'+@_crlf;

			set @_mail_subject = @mail_subject+' - '+convert(varchar,@_start_time,120);
			set @_mail_html = '<html>'
									+N'<head>'
									+N'<title>'+@_mail_subject+'</title>'
									+@_style_css
									+N'</head>'
									+N'<body>'
									+N'<h1><a href="'+@_url_login_expiry_dashboard_panel+'" target="_blank">'+@_mail_subject+'</a></h1>'
									+N'<p>'+@_mail_html_body+N'</p>'
									+N'<br><br><br><p>Regards,<br>Job ['+@job_name+']</p>'
									+N'</body>';	
			if @verbose >= 1
			begin
				print @_long_star_line
				print @_crlf+@_mail_html+@_crlf
			end

			if @send_mail = 1 or @enable_dba_mail_while_testing = 1
			begin
				if @_table_data is not null
				begin
					if @send_mail = 0
					begin
						set @_mail_subject = 'Testing - CTO - '+@_mail_subject
						set @c_mail_recipient = @dba_team_email_id;
					end
					exec msdb.dbo.sp_send_dbmail 
										@recipients = @c_mail_recipient,
										@copy_recipients = @_copy_recipients,
										@subject = @_mail_subject,
										@body = @_mail_html,
										@body_format = 'HTML';
				end
			end

		end try
		begin catch
			SELECT	@_errorNumber	 = Error_Number()
					,@_errorSeverity = Error_Severity()
					,@_errorState	 = Error_State()
					,@_errorLine	 = Error_Line()
					,@_errorMessage	 = Error_Message();

			set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
								'. State: '+convert(varchar,isnull(@_errorState,'')) +
								'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
								'. Error Message::: '+ @_errorMessage;

			print @_crlf+@_long_star_line+@_crlf+'Error Occurred while sending mail for '''+@c_mail_recipient+'''.'+@_crlf+@_errorMessage+@_crlf+@_long_star_line+@_crlf;

			insert [dbo].[sma_errorlog]
			([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
			select	[collection_time] = @_start_time, [function_name] = 'usp_send_login_expiry_emails', 
					[function_call_arguments] = @c_mail_recipient, [server] = null, [error] = @_errorMessage, 
					[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = program_name();
		end catch

	end -- 'Send-Mail-Notification-2-CTO'
END
GO

-- exec dbo.usp_send_login_expiry_emails @verbose = 2, @send_mail = 0, @enable_dba_mail_while_testing = 1;
go

