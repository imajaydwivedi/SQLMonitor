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

create or alter procedure dbo.usp_wrapper_populate_sma_sql_instance
	@job_name varchar(255) = '(dba) Populate Inventory Tables',
	@send_mail bit = 1,
	@verbose tinyint = 0,
	@truncate_log_table bit = 0
as
begin
/*	Purpose:		Populate inventory tables from SQLMonitor tables
	Modifications:	2025-01-30 - Add support for Managed Instances (PAAS)
					2024-07-31 - Initial Draft
	Examples:		

		exec dbo.usp_wrapper_populate_sma_sql_instance @send_mail = 0, @verbose = 2, @truncate_log_table = 0

		exec dbo.usp_wrapper_populate_sma_sql_instance @send_mail = 1, @verbose = 2, @truncate_log_table = 0

*/
	set nocount on;

	declare @_start_time datetime2 = sysdatetime();
	if @verbose >= 1
		print 'Declare variables..'

	declare @dba_team_email_id varchar(125) = 'dba_team@gmail.com'
	declare @dba_manager_email_id varchar(125) = 'dba.manager@gmail.com' /* Email for DBA Manager */
	declare @sre_vp_email_id varchar(125) = 'sre.vp@gmail.com' /* Email for SRE Senior VP */
	declare @cto_email_id varchar(125) = 'cto@gmail.com' /* Email for CTO */
	declare @noc_email_id varchar(125) = 'noc@gmail.com' /* NOC team */
	declare @url_for_GrafanaDashboardPortal varchar(1000) = 'http://localhost:3000/d/';

	select @dba_team_email_id = p.param_value from dbo.sma_params p where p.param_key = 'dba_team_email_id';
	select @dba_manager_email_id = p.param_value from dbo.sma_params p where p.param_key = 'dba_manager_email_id';
	select @sre_vp_email_id = p.param_value from dbo.sma_params p where p.param_key = 'sre_vp_email_id';
	select @cto_email_id = p.param_value from dbo.sma_params p where p.param_key = 'cto_email_id';
	select @noc_email_id = p.param_value from dbo.sma_params p where p.param_key = 'noc_email_id';
	select @url_for_GrafanaDashboardPortal = p.param_value from dbo.sma_params p where p.param_key = 'GrafanaDashboardPortal';
	

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

	declare @_sql_instance varchar(125);
	declare @_id int;
	declare @_crlf nchar(2) = char(10)+char(13);
	declare @_long_star_line varchar(500) = replicate('*',75);

	declare @_url_individual_server_dashboard varchar(2000) = @url_for_GrafanaDashboardPortal+'distributed_live_dashboard/monitoring-live-distributed?orgId=1'

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
	declare @_table_row_count int = 0;

	DECLARE	@_errorNumber int,
				@_errorSeverity int,
				@_errorState int,
				@_errorLine int,
				@_errorMessage nvarchar(4000);

	if object_id('tempdb..#vw_all_server_info') is not null
		drop table #vw_all_server_info;
	select * into #vw_all_server_info from dbo.vw_all_server_info asi;

	if ('Populate-Inventory-Tables' = 'Populate-Inventory-Tables')
	begin
		-- This table contains host entries that need DBA attention
		if @verbose >= 1
			print 'truncate table dbo.sma_wrapper_sql_server_hosts;'
		truncate table dbo.sma_wrapper_sql_server_hosts;

		if @truncate_log_table = 1
		begin
			if @verbose >= 1
				print 'truncate table dbo.sma_servers_logs;'
			truncate table dbo.sma_servers_logs;
		end

		if @verbose >= 2
		begin
			;with t_servers as (
				select distinct sql_instance = ltrim(rtrim(id.sql_instance))
				from dbo.instance_details id
				where id.is_enabled = 1 and id.is_alias = 0
				and id.sql_instance not in ('DBAInventoryServer')
				and not exists (select * from dbo.sma_servers_logs l where l.sql_instance = id.sql_instance and l.status = 'Successful')
			)
			select t.*, s.*
			from t_servers s
			full outer join
				(select RunningQuery = 'Servers-2-Process') t
				on 1=1;
		end

		declare cur_servers cursor local forward_only for
				select distinct ltrim(rtrim(id.sql_instance))
				from dbo.instance_details id
				where id.is_enabled = 1 and id.is_alias = 0
				and id.sql_instance not in ('DBAInventoryServer')
				and not exists (select * from dbo.sma_servers_logs l where l.sql_instance = id.sql_instance and l.status = 'Successful');

		open cur_servers;
		fetch next from cur_servers into @_sql_instance;

		while @@FETCH_STATUS = 0
		begin
			set @_errorMessage = null;
			set @_id = null;

			print 'Working on @_sql_instance = '+quotename(@_sql_instance)+'..'

			insert dbo.sma_servers_logs (sql_instance)
			select @_sql_instance;

			set @_id = SCOPE_IDENTITY();
	
			begin try
				if @verbose > 0
					print 'exec dbo.usp_populate_sma_sql_instance @server = '''+@_sql_instance+''', @execute = 1 ,@verbose = 2;'
				exec dbo.usp_populate_sma_sql_instance @server = @_sql_instance ,@collection_time = @_start_time ,@execute = 1 ,@verbose = 0;
			end try
			begin catch
				select	@_errorNumber	 = Error_Number()
						,@_errorSeverity = Error_Severity()
						,@_errorState	 = Error_State()
						,@_errorLine	 = Error_Line()
						,@_errorMessage	 = Error_Message();

				set @_errorMessage = 'Error Details => Severity: '+convert(varchar,isnull(@_errorSeverity,''))+
									'. State: '+convert(varchar,isnull(@_errorState,'')) +
									'. Error Line: '+convert(varchar,isnull(@_errorLine,'')) + 
									'. Error Message::: '+ @_errorMessage;

				print @_crlf+@_long_star_line+@_crlf+'Error Occurred while processing server ['+@_sql_Instance+'].'+@_crlf+@_errorMessage+@_crlf+@_long_star_line+@_crlf;

				update dbo.sma_servers_logs
				set status = 'Failed', remarks = @_errorMessage
				where id = @_id;
			end catch

			if @_errorMessage is null
				update dbo.sma_servers_logs set status = 'Successful' where id = @_id;

			fetch next from cur_servers into @_sql_instance;
		end

		close cur_servers;
		deallocate cur_servers;
	end -- 'Populate-Inventory-Tables'

	if ('Use-CSS-in-Mail' = 'Use-CSS-in-Mail')
	begin
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
	end

	-- Send mail for Missing Server Owners
	set @_table_row_count = (select count(*) from dbo.sma_servers s	where s.is_decommissioned = 0 and server_owner_email is null);
	if @_table_row_count > 0
	begin
		print 'Send mail for Missing Server Owners..'

		if @verbose >= 2
		begin
			;with cte_missing_owners as (
				select * from dbo.sma_servers s	where s.is_decommissioned = 0 and server_owner_email is null
			)
			select t.*, m.*
			from cte_missing_owners m
			full outer join
				(select RunningQuery = 'Missing-Owners-List') t
				on 1=1;
		end

		set @_recepient = @dba_team_email_id;
		set @_copy_recipients = @dba_manager_email_id

		begin try
			set @_table_data = null;

			set @_table_headline = N'<h3>Following server have no Owner Email set in <code>dbo.sma_servers</code></h3>'+@_crlf

			set @_table_header = N'<tr><th>Server</th> <th>Port</th> <th>Domain</th>'
							+N'<th>Stability</th> <th>Priority</th> <th>Server Type</th>'
							+N'<th>HADR</th> <th>Collection Time</th></tr>'+@_crlf;
				
			;with t_login_info as (
				select s.server, s.server_port, s.domain, s.stability, s.priority, s.server_type, s.hadr_strategy,
						created_date = DATEADD(mi, DATEDIFF(mi, GETUTCDATE(), GETDATE()), s.created_date_utc)
				from dbo.sma_servers s	
				where s.is_decommissioned = 0 and server_owner_email is null
			)
			,t_table_rows as (
				select	'<tr>'
							+'<td class="bg_key"><a href="'+@_url_individual_server_dashboard+'&var-server='+server+'" target="_blank">'+server+'</a></td>'
							+'<td>'+coalesce(convert(varchar,server_port),' ')+'</td>'
							+'<td>'+coalesce(domain,' ')+'</td>'
							+'<td>'+convert(varchar,stability)+'</td>'
							+'<td>'+convert(varchar,priority)+'</td>'
							+'<td>'+coalesce(server_type,' ')+'</td>'
							+'<td>'+coalesce(hadr_strategy,' ')+'</td>'
							+'<td>'+convert(varchar,created_date,121)+'</td>'
						+'</tr>' as [table_row]
				from t_login_info
			)
			select @_table_data = coalesce(@_table_data+' '+[table_row],[table_row])
			from t_table_rows

			set @_mail_html_body = @_table_headline+'<div class="tableContainerDiv"><table border="1">'
									+'<caption>'+convert(varchar,@_table_row_count)+' rows || select * from dbo.sma_servers where is_decommissioned = 0 and server_owner_email is null</caption>'
									+'<thead>'+@_table_header+'</thead><tbody>'+isnull(@_table_data,'')+'</tbody></table></div>'+@_crlf;

			set @_mail_subject = 'Servers with Missing Owner'+' - '+convert(varchar,@_start_time,120);
			set @_mail_html = '<html>'
									+N'<head>'
									+N'<title>'+@_mail_subject+'</title>'
									+@_style_css
									+N'</head>'
									+N'<body>'
									+N'<h1><a href="'+@_url_individual_server_dashboard+'" target="_blank">'+@_mail_subject+'</a></h1>'
									+N'<p>'+@_mail_html_body+N'</p>'
									+N'<br><br><br><p>Regards,<br>Job ['+@job_name+']</p>'
									+N'</body>';	
			if @verbose >= 1
			begin
				print @_long_star_line
				print '@_table_headline => '+@_crlf+@_table_headline
				print '@_table_header => '+@_crlf+@_table_header
				print '@_mail_html_body => '+@_crlf+@_mail_html_body
				print '@_table_data => '+@_crlf+@_table_data
				print '@_mail_html => '+@_crlf+@_mail_html+@_crlf
			end

			if @send_mail = 1
			begin
				if @_table_data is not null
				begin
					exec msdb.dbo.sp_send_dbmail 
										@recipients = @_recepient,
										@copy_recipients = @_copy_recipients,
										@subject = @_mail_subject,
										@body = @_mail_html,
										@importance = 'High',
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

			print @_crlf+@_long_star_line+@_crlf+'Error Occurred while sending mail.'+@_crlf+@_errorMessage+@_crlf+@_long_star_line+@_crlf;

			insert [dbo].[sma_errorlog]
			([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
			select	[collection_time] = @_start_time, [function_name] = 'usp_wrapper_populate_sma_sql_instance', 
					[function_call_arguments] = 'Missing Server Owners', [server] = null, [error] = @_errorMessage, 
					[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = program_name();
		end catch
	end

	-- Send mail for Wrong Linked Server Port
	if ('Send-Mail-4-Wrong-LinkedServer-Port' = 'Send-Mail-4-Wrong-LinkedServer-Port')
	begin
		print 'Send mail for Wrong Linked Server Port..'

		set @_table_row_count = 0;
		if OBJECT_ID('tempdb..#LinkedServers') is not null
			drop table #LinkedServers;
		;with t_servers as (
			select id.sql_instance, id.sql_instance_port
					,[linked_server_data_source] = s.data_source 
					,sql_instance_with_port = case when sql_instance_port is not null
												then sql_instance+','+sql_instance_port 
												else sql_instance
												end
					,id.collector_powershell_jobs_server, 
					id.collector_tsql_jobs_server, 
					id.data_destination_sql_instance
			from master.sys.servers s
			cross apply (select top 1 * from dbo.instance_details id
							where id.sql_instance = s.name
							and id.is_enabled = 1
							and id.is_alias = 0
						) id
		)
		select *
		into #LinkedServers
		from t_servers
		where [linked_server_data_source] <> sql_instance_with_port;

		if @verbose >= 2
		begin
			select t.*, m.*
			from #LinkedServers m
			full outer join
				(select RunningQuery = 'Wrong-LinkedServer-Port') t
				on 1=1;
		end

		set @_table_row_count = (select count(*) from #LinkedServers);
		set @_recepient = @dba_team_email_id;
		set @_copy_recipients = @dba_manager_email_id

		begin try
			set @_table_data = null;

			set @_table_headline = N'<h3>Following servers have mismatched Linked Server port compared to <code>dbo.instance_details</code></h3>'+@_crlf

			set @_table_header = N'<tr><th>SQLInstance/th> <th>Port</th> <th>Linked Server Data Source</th>'
							+N'<th>SQLInstance With Port</th> <th>Collector TSQL Jobs Server</th></tr>'+@_crlf;
				
			;with t_table_rows as (
				select	'<tr>'
							+'<td class="bg_key"><a href="'+@_url_individual_server_dashboard+'&var-server='+sql_instance+'" target="_blank">'+sql_instance+'</a></td>'
							+'<td>'+coalesce(convert(varchar,sql_instance_port),' ')+'</td>'
							+'<td>'+coalesce(linked_server_data_source,' ')+'</td>'
							+'<td>'+coalesce(sql_instance_with_port,' ')+'</td>'
							+'<td>'+coalesce(collector_tsql_jobs_server,' ')+'</td>'
						+'</tr>' as [table_row]
				from #LinkedServers
			)
			select @_table_data = coalesce(@_table_data+' '+[table_row],[table_row])
			from t_table_rows

			set @_mail_html_body = @_table_headline+'<div class="tableContainerDiv"><table border="1">'
									+'<caption>'+convert(varchar,@_table_row_count)+' rows</caption>'
									+'<thead>'+@_table_header+'</thead><tbody>'+isnull(@_table_data,'')+'</tbody></table></div>'+@_crlf;

			set @_mail_subject = 'SQLMonitor - Wrong Linked Server Port'+' - '+convert(varchar,@_start_time,120);
			set @_mail_html = '<html>'
									+N'<head>'
									+N'<title>'+@_mail_subject+'</title>'
									+@_style_css
									+N'</head>'
									+N'<body>'
									+N'<h1><a href="'+@_url_individual_server_dashboard+'" target="_blank">'+@_mail_subject+'</a></h1>'
									+N'<p>'+@_mail_html_body+N'</p>'
									+N'<br><br><br><p>Regards,<br>Job ['+@job_name+']</p>'
									+N'</body>';	
			if @verbose >= 1
			begin
				print @_long_star_line
				print '@_table_headline => '+@_crlf+@_table_headline
				print '@_table_header => '+@_crlf+@_table_header
				print '@_mail_html_body => '+@_crlf+@_mail_html_body
				print '@_table_data => '+@_crlf+@_table_data
				print '@_mail_html => '+@_crlf+@_mail_html+@_crlf
			end

			if @send_mail = 1
			begin
				if @_table_data is not null
				begin
					exec msdb.dbo.sp_send_dbmail 
										@recipients = @_recepient,
										@copy_recipients = @_copy_recipients,
										@subject = @_mail_subject,
										@body = @_mail_html,										
										@importance = 'High',
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

			print @_crlf+@_long_star_line+@_crlf+'Error Occurred while sending mail.'+@_crlf+@_errorMessage+@_crlf+@_long_star_line+@_crlf;

			insert [dbo].[sma_errorlog]
			([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
			select	[collection_time] = @_start_time, [function_name] = 'usp_wrapper_populate_sma_sql_instance', 
					[function_call_arguments] = 'Send-Mail-4-Wrong-LinkedServer-Port', [server] = null, [error] = @_errorMessage, 
					[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = program_name();
		end catch
	end -- 'Send-Mail-4-Wrong-LinkedServer-Port'

	if ('Send-Mail-4-Missing-Servers' = 'Send-Mail-4-Missing-Servers')
	begin
		set @_table_row_count = 0;

		-- Probable List of hosts missing in SQLMonitor
		if object_id('tempdb..#hosts') is not null
			drop table #hosts;
		;with t_hosts as (
			select *
			from (
					select h.server, s.server_port, [host_name] = ltrim(rtrim(h.host_name)), h.host_ips, source = 'sma_sql_server_hosts' 
					from dbo.sma_sql_server_hosts h join dbo.sma_servers s on s.server = h.server
					where s.is_decommissioned = 0 and h.is_decommissioned = 0 -- covers standalone + cluster nodes
					--
					union
					--
					select	ag.server, s.server_port,
							[host_name] = rh.[replica_host], 
							h.host_ips,
							source = 'sma_hadr_ag' 
					from dbo.sma_hadr_ag ag join dbo.sma_servers s on s.server = ag.server
					cross apply (select replica_name = Value from string_split(ag.ag_replicas_CSV,',')) r
					cross apply (select top 1 [replica_host] = ltrim(rtrim(Value)) from string_split(ltrim(rtrim(r.replica_name)),'\')o) rh
					outer apply (select top 1 host_ips from dbo.sma_sql_server_hosts h where h.is_decommissioned = 0 and h.host_name = rh.replica_host ) h
					where s.is_decommissioned = 0 and ag.is_decommissioned = 0 -- get list of ag replicas	
				)h
		)
		select	[related_server] = h.server, h.server_port, [sql_instance_port] = c.sql_instance_port, 
				h.[host_name], host_ips,
				possible_type = case when h.source = 'sma_hadr_ag' then 'ag replica' else 'sql cluster' end,
				asi.domain,
				[host_fqdn] = case when asi.domain = 'LAB' then h.host_name+'.Lab.com'
									when asi.domain = 'Contoso' then h.host_name+'.Contoso.com'
									when asi.domain = 'Contso' then h.host_name+'.Contso.com'
									when asi.domain is null then h.host_name
									else h.host_name
								end
		into #hosts
		from t_hosts h
		outer apply (select * from #vw_all_server_info asi where asi.srv_name = h.server) asi
		outer apply (select top 1 * from dbo.instance_details id where is_enabled = 1 and is_alias = 0 and id.sql_instance = h.server) c
		where 1=1
		and (	(	h.source = 'sma_sql_server_hosts'
					and not exists (select * from dbo.instance_details id where id.is_enabled = 1 and id.is_alias = 0 
								and id.sql_instance = h.server and id.host_name = h.host_name
							)
				)
				or
				(	h.source = 'sma_hadr_ag'
					and not exists (select * from dbo.instance_details id where id.is_enabled = 1 and id.is_alias = 0 
								and id.host_name = h.host_name
							)
				)
			);

		-- Send mail for Missing Servers
		if exists (select * from #hosts)
		begin
			print 'Send mail for Missing Servers..';

			set @_table_row_count = (select count(*) from #hosts);

			if @verbose >= 2
			begin
				select t.*, h.*
				from #hosts h
				full outer join
					(select RunningQuery = 'Missing-Hosts') t
					on 1=1;
			end

			set @_recepient = @dba_team_email_id;
			set @_copy_recipients = @dba_manager_email_id

			begin try
				set @_table_data = null;

				set @_table_headline = N'<h3>Possible list of Hosts missing in SQLMonitor table <code>dbo.instance_details</code></h3>'+@_crlf

				set @_table_header = N'<tr><th>Related Server</th> <th>Possible Port</th> <th>Host Name</th>'
											+'<th>Host Ip</th> <th>Possible Type</th> <th>Host FQDN</th> </tr>'+@_crlf;
				
				;with t_login_info as (
					select h.related_server, h.server_port, h.sql_instance_port, h.host_name, h.host_ips, h.possible_type, domain, h.host_fqdn
					from #hosts h
				)
				,t_table_rows as (
					select	'<tr>'
								+'<td class="bg_key"><a href="'+@_url_individual_server_dashboard+'&var-server='+related_server+'" target="_blank">'+related_server+'</a></td>'
								+'<td>'+coalesce(sql_instance_port,server_port,' ')+'</td>'
								+'<td>'+coalesce(host_name,' ')+'</td>'
								+'<td>'+coalesce(host_ips,' ')+'</td>'
								+'<td>'+coalesce(possible_type,' ')+'</td>'
								+'<td>'+coalesce(host_fqdn,' ')+'</td>'
							+'</tr>' as [table_row]
					from t_login_info
				)
				select @_table_data = coalesce(@_table_data+' '+[table_row],[table_row])
				from t_table_rows

				set @_mail_html_body = @_table_headline+'<div class="tableContainerDiv"><table border="1">'
										+'<caption>'+convert(varchar,@_table_row_count)+' rows</caption>'
										+'<thead>'+@_table_header+'</thead><tbody>'+isnull(@_table_data,'')+'</tbody></table></div>'+@_crlf;

				set @_mail_subject = 'Possible Hosts Missing in SQLMonitor'+' - '+convert(varchar,@_start_time,120);
				set @_mail_html = '<html>'
										+N'<head>'
										+N'<title>'+@_mail_subject+'</title>'
										+@_style_css
										+N'</head>'
										+N'<body>'
										+N'<h1><a href="'+@_url_individual_server_dashboard+'" target="_blank">'+@_mail_subject+'</a></h1>'
										+N'<p>'+@_mail_html_body+N'</p>'
										+N'<br><br><br><p>Regards,<br>Job ['+@job_name+']</p>'
										+N'</body>';	
				if @verbose >= 1
				begin
					print @_long_star_line
					print '@_table_headline => '+@_crlf+@_table_headline
					print '@_table_header => '+@_crlf+@_table_header
					print '@_mail_html_body => '+@_crlf+@_mail_html_body
					print '@_table_data => '+@_crlf+@_table_data
					print '@_mail_html => '+@_crlf+@_mail_html+@_crlf
				end

				if @send_mail = 1
				begin
					if @_table_data is not null
					begin
						exec msdb.dbo.sp_send_dbmail 
											@recipients = @_recepient,
											@copy_recipients = @_copy_recipients,
											@subject = @_mail_subject,
											@body = @_mail_html,
											@importance = 'High',
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

				print @_crlf+@_long_star_line+@_crlf+'Error Occurred while sending mail.'+@_crlf+@_errorMessage+@_crlf+@_long_star_line+@_crlf;

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_wrapper_populate_sma_sql_instance', 
						[function_call_arguments] = 'Send-Mail-4-Missing-Servers', [server] = null, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = program_name();
			end catch
		end
	end -- 'Send-Mail-4-Missing-Servers'

	if ('Send-Mail-4-Wrong-Host-Entries' = 'Send-Mail-4-Wrong-Host-Entries__Wrong')
	begin
		set @_table_row_count = 0;

		-- Probable List of hosts missing in SQLMonitor
		if object_id('tempdb..#hosts') is not null
			drop table #hosts;
		select	*
		--into #hosts
		from dbo.sma_wrapper_sql_server_hosts h

		-- Send mail for Missing Servers
		if exists (select * from #hosts)
		begin
			print 'Send mail for Missing Servers..';

			set @_table_row_count = (select count(*) from #hosts);

			if @verbose >= 2
			begin
				select t.*, h.*
				from #hosts h
				full outer join
					(select RunningQuery = 'Missing-Hosts') t
					on 1=1;
			end

			set @_recepient = @dba_team_email_id;
			set @_copy_recipients = @dba_manager_email_id

			begin try
				set @_table_data = null;

				set @_table_headline = N'<h3>Possible list of Hosts missing in SQLMonitor table <code>dbo.instance_details</code></h3>'+@_crlf

				set @_table_header = N'<tr><th>Related Server</th> <th>Possible Port</th> <th>Host Name</th>'
											+'<th>Host Ip</th> <th>Possible Type</th> <th>Host FQDN</th> </tr>'+@_crlf;
				
				;with t_login_info as (
					select h.related_server, h.server_port, h.sql_instance_port, h.host_name, h.host_ips, h.possible_type, domain, h.host_fqdn
					from #hosts h
				)
				,t_table_rows as (
					select	'<tr>'
								+'<td class="bg_key"><a href="'+@_url_individual_server_dashboard+'&var-server='+related_server+'" target="_blank">'+related_server+'</a></td>'
								+'<td>'+coalesce(sql_instance_port,server_port,' ')+'</td>'
								+'<td>'+coalesce(host_name,' ')+'</td>'
								+'<td>'+coalesce(host_ips,' ')+'</td>'
								+'<td>'+coalesce(possible_type,' ')+'</td>'
								+'<td>'+coalesce(host_fqdn,' ')+'</td>'
							+'</tr>' as [table_row]
					from t_login_info
				)
				select @_table_data = coalesce(@_table_data+' '+[table_row],[table_row])
				from t_table_rows

				set @_mail_html_body = @_table_headline+'<div class="tableContainerDiv"><table border="1">'
										+'<caption>'+convert(varchar,@_table_row_count)+' rows</caption>'
										+'<thead>'+@_table_header+'</thead><tbody>'+isnull(@_table_data,'')+'</tbody></table></div>'+@_crlf;

				set @_mail_subject = 'Possible Hosts Missing in SQLMonitor'+' - '+convert(varchar,@_start_time,120);
				set @_mail_html = '<html>'
										+N'<head>'
										+N'<title>'+@_mail_subject+'</title>'
										+@_style_css
										+N'</head>'
										+N'<body>'
										+N'<h1><a href="'+@_url_individual_server_dashboard+'" target="_blank">'+@_mail_subject+'</a></h1>'
										+N'<p>'+@_mail_html_body+N'</p>'
										+N'<br><br><br><p>Regards,<br>Job ['+@job_name+']</p>'
										+N'</body>';	
				if @verbose >= 1
				begin
					print @_long_star_line
					print '@_table_headline => '+@_crlf+@_table_headline
					print '@_table_header => '+@_crlf+@_table_header
					print '@_mail_html_body => '+@_crlf+@_mail_html_body
					print '@_table_data => '+@_crlf+@_table_data
					print '@_mail_html => '+@_crlf+@_mail_html+@_crlf
				end

				if @send_mail = 1
				begin
					if @_table_data is not null
					begin
						exec msdb.dbo.sp_send_dbmail 
											@recipients = @_recepient,
											@copy_recipients = @_copy_recipients,
											@subject = @_mail_subject,
											@body = @_mail_html,
											@importance = 'High',
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

				print @_crlf+@_long_star_line+@_crlf+'Error Occurred while sending mail.'+@_crlf+@_errorMessage+@_crlf+@_long_star_line+@_crlf;

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_wrapper_populate_sma_sql_instance', 
						[function_call_arguments] = 'Send-Mail-4-Missing-Servers', [server] = null, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = program_name();
			end catch
		end
	end -- 'Send-Mail-4-Wrong-Host-Entries'

	-- Send mail for Probable list of Decomissioned Servers
	if ('Send-Mail-4-Decomissioned-Server' = 'Send-Mail-4-Decomissioned-Server')
	begin
		print 'Send mail for Probable Decomissioned Server..'
		set @_table_row_count = 0;

		if OBJECT_ID('tempdb..#DecomissedServers') is not null
			drop table #DecomissedServers;
		select	s.server, s.server_port, s.domain, s.friendly_name, 
				s.stability, s.priority, s.hadr_strategy, s.server_owner_email,
				s.more_info
		into #DecomissedServers
		from dbo.sma_servers s
		--join dbo.sma_sql_server_extended_info ei
		--	on ei.server = s.server	
		where s.is_decommissioned = 0
		and not exists (select * from dbo.instance_details id 
						where id.is_enabled = 1 and id.is_alias = 0 
						and id.sql_instance = s.server)
		and (more_info is null or more_info <> 'DBA Inventory Server');

		if @verbose >= 2
		begin
			select t.*, m.*
			from #DecomissedServers m
			full outer join
				(select RunningQuery = 'Probable-Decomissioned-Server') t
				on 1=1;
		end

		set @_table_row_count = (select count(*) from #DecomissedServers);
		set @_recepient = @dba_team_email_id;
		set @_copy_recipients = @dba_manager_email_id

		begin try
			set @_table_data = null;

			set @_table_headline = N'<h3>Following servers have probably been decomissioned, but are still active in <code>dbo.sma_servers & dbo.sma_sql_server_extended_info</code></h3>'+@_crlf

			set @_table_header = N'<tr><th>SQLInstance/th> <th>Port</th> <th>Domain</th>'
							+N'<th>Friendly Name</th> <th>Stability</th> <th>Priority</th>'
							+N'<th>HADR</th> <th>Owner Email</th> <th>More Info</th> </tr>'+@_crlf;
				
			;with t_table_rows as (
				select	'<tr>'
							+'<td class="bg_key"><a href="'+@_url_individual_server_dashboard+'&var-server='+server+'" target="_blank">'+server+'</a></td>'
							+'<td>'+coalesce(convert(varchar,server_port),' ')+'</td>'
							+'<td>'+coalesce(domain,' ')+'</td>'
							+'<td>'+coalesce(friendly_name,' ')+'</td>'
							+'<td>'+coalesce(stability,' ')+'</td>'
							+'<td>'+coalesce(convert(varchar,priority),' ')+'</td>'
							+'<td>'+coalesce(hadr_strategy,' ')+'</td>'
							+'<td>'+coalesce(server_owner_email,' ')+'</td>'
							+'<td>'+coalesce(more_info,' ')+'</td>'
						+'</tr>' as [table_row]
				from #DecomissedServers
			)
			select @_table_data = coalesce(@_table_data+' '+[table_row],[table_row])
			from t_table_rows

			set @_mail_html_body = @_table_headline+'<div class="tableContainerDiv"><table border="1">'
									+'<caption>'+convert(varchar,@_table_row_count)+' rows</caption>'
									+'<thead>'+@_table_header+'</thead><tbody>'+isnull(@_table_data,'')+'</tbody></table></div>'+@_crlf;

			set @_mail_subject = 'DBA Inventory - Possibile Decomissioned Servers'+' - '+convert(varchar,@_start_time,120);
			set @_mail_html = '<html>'
									+N'<head>'
									+N'<title>'+@_mail_subject+'</title>'
									+@_style_css
									+N'</head>'
									+N'<body>'
									+N'<h1><a href="'+@_url_individual_server_dashboard+'" target="_blank">'+@_mail_subject+'</a></h1>'
									+N'<p>'+@_mail_html_body+N'</p>'
									+N'<br><br><br><p>Regards,<br>Job ['+@job_name+']</p>'
									+N'</body>';	
			if @verbose >= 1
			begin
				print @_long_star_line
				print '@_table_headline => '+@_crlf+@_table_headline
				print '@_table_header => '+@_crlf+@_table_header
				print '@_mail_html_body => '+@_crlf+@_mail_html_body
				print '@_table_data => '+@_crlf+@_table_data
				print '@_mail_html => '+@_crlf+@_mail_html+@_crlf
			end

			if @send_mail = 1
			begin
				if @_table_data is not null
				begin
					exec msdb.dbo.sp_send_dbmail 
										@recipients = @_recepient,
										@copy_recipients = @_copy_recipients,
										@subject = @_mail_subject,
										@body = @_mail_html,
										@importance = 'High',
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

			print @_crlf+@_long_star_line+@_crlf+'Error Occurred while sending mail.'+@_crlf+@_errorMessage+@_crlf+@_long_star_line+@_crlf;

			insert [dbo].[sma_errorlog]
			([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
			select	[collection_time] = @_start_time, [function_name] = 'usp_wrapper_populate_sma_sql_instance', 
					[function_call_arguments] = 'Send-Mail-4-Wrong-LinkedServer-Port', [server] = null, [error] = @_errorMessage, 
					[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = program_name();
		end catch
	end -- 'Send-Mail-4-Decomissioned-Server'

	if ('Send-Mail-4-Missing-AgListener-Alias' = 'Send-Mail-4-Missing-AgListener-Alias')
	begin
		set @_table_row_count = 0;

		-- Probable List of Missing AG Listener Alias in SQLMonitor
		if OBJECT_ID('tempdb..#missing_ag_listeners') is not null
			drop table #missing_ag_listeners;
		;with t_ags as (
			select ag.ag_listener_name, ag_listener_ip = ag.ag_listener_ip1
			from dbo.sma_servers s
			join dbo.sma_hadr_ag ag
				on ag.server = s.server
			where s.is_decommissioned = 0
			and ag.is_decommissioned = 0
			and s.hadr_strategy = 'ag'
			and ag.ag_listener_ip1 is not null
			--
			union
			--
			select ag.ag_listener_name, ag_listener_ip = ag.ag_listener_ip2
			from dbo.sma_servers s
			join dbo.sma_hadr_ag ag
				on ag.server = s.server
			where s.is_decommissioned = 0
			and ag.is_decommissioned = 0
			and s.hadr_strategy = 'ag'
			and ag.ag_listener_ip2 is not null
		)
		select related_server = hadr.server, hadr.ag_replicas_CSV, ag.*
		into #missing_ag_listeners
		from t_ags ag
		outer apply (select top 1 server, ag_replicas_CSV from dbo.sma_hadr_ag hadr 
							where hadr.is_decommissioned = 0 and hadr.ag_listener_name = ag.ag_listener_name) hadr
		where 1=1
		and not exists (select * from dbo.instance_details id
				where id.is_enabled = 1
				and id.is_alias = 1 and id.sql_instance = ag.ag_listener_ip);
			
		set @_table_row_count = (select count(*) from #missing_ag_listeners);

		if @_table_row_count > 0
		begin
			print 'Send mail for Missing Alias..';

			if @verbose >= 2
			begin
				select t.*, ag.*
				from #missing_ag_listeners ag				
				full outer join
					(select RunningQuery = 'Missing-Alias-in-SQLMonitor') t
					on 1=1;
			end

			set @_recepient = @dba_team_email_id;
			set @_copy_recipients = @dba_manager_email_id

			begin try
				set @_table_data = null;

				set @_table_headline = N'<h3>Following Ag Listener/IPs Alias are missing in SQLMonitor table <code>dbo.instance_details.</code> Kindly added them as <b>Alias</b>.</h3>'+@_crlf

				set @_table_header = N'<tr><th>Related Server</th> <th>AG Replicas</th> <th>Ag Listener Name</th>'
											+'<th>Ag Listener IP</th> </tr>'+@_crlf;
				
				;with t_login_info as (
					select al.related_server, al.ag_replicas_CSV, al.ag_listener_name, al.ag_listener_ip
					from #missing_ag_listeners al
				)
				,t_table_rows as (
					select	'<tr>'
								+'<td class="bg_key"><a href="'+@_url_individual_server_dashboard+'&var-server='+related_server+'" target="_blank">'+related_server+'</a></td>'
								+'<td>'+coalesce(ag_replicas_CSV,' ')+'</td>'
								+'<td>'+coalesce(ag_listener_name,' ')+'</td>'
								+'<td>'+coalesce(ag_listener_ip,' ')+'</td>'
							+'</tr>' as [table_row]
					from t_login_info
				)
				select @_table_data = coalesce(@_table_data+' '+[table_row],[table_row])
				from t_table_rows

				set @_mail_html_body = @_table_headline+'<div class="tableContainerDiv"><table border="1">'
										+'<caption>'+convert(varchar,@_table_row_count)+' rows</caption>'
										+'<thead>'+@_table_header+'</thead><tbody>'+isnull(@_table_data,'')+'</tbody></table></div>'+@_crlf;

				set @_mail_subject = 'AG Listener Alias missing in SQLMonitor'+' - '+convert(varchar,@_start_time,120);
				set @_mail_html = '<html>'
										+N'<head>'
										+N'<title>'+@_mail_subject+'</title>'
										+@_style_css
										+N'</head>'
										+N'<body>'
										+N'<h1><a href="'+@_url_individual_server_dashboard+'" target="_blank">'+@_mail_subject+'</a></h1>'
										+N'<p>'+@_mail_html_body+N'</p>'
										+N'<br><br><br><p>Regards,<br>Job ['+@job_name+']</p>'
										+N'</body>';	
				if @verbose >= 1
				begin
					print @_long_star_line
					print '@_table_headline => '+@_crlf+@_table_headline
					print '@_table_header => '+@_crlf+@_table_header
					print '@_mail_html_body => '+@_crlf+@_mail_html_body
					print '@_table_data => '+@_crlf+@_table_data
					print '@_mail_html => '+@_crlf+@_mail_html+@_crlf
				end

				if @send_mail = 1
				begin
					if @_table_data is not null
					begin
						exec msdb.dbo.sp_send_dbmail 
											@recipients = @_recepient,
											@copy_recipients = @_copy_recipients,
											@subject = @_mail_subject,
											@body = @_mail_html,
											@importance = 'High',
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

				print @_crlf+@_long_star_line+@_crlf+'Error Occurred while sending mail.'+@_crlf+@_errorMessage+@_crlf+@_long_star_line+@_crlf;

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_wrapper_populate_sma_sql_instance', 
						[function_call_arguments] = 'Send-Mail-4-Missing-Servers', [server] = null, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = program_name();
			end catch
		end
	end -- 'Send-Mail-4-Missing-AgListener-Alias'


	if ('Send-Mail-4-Wrong-SqlInstance-Entry' = 'Send-Mail-4-Wrong-SqlInstance-Entry')
	begin
		set @_table_row_count = 0;

		-- Wrong SQLInstance Entry in SQLMonitor Using AG Listener
		if OBJECT_ID('tempdb..#wrong_entry_on_listeners') is not null
			drop table #wrong_entry_on_listeners;
		;with t_ags as (
			select ag.ag_listener_name, ag_listener_ip = ag.ag_listener_ip1
			from dbo.sma_servers s
			join dbo.sma_hadr_ag ag
				on ag.server = s.server
			where s.is_decommissioned = 0
			and ag.is_decommissioned = 0
			and s.hadr_strategy = 'ag'
			and ag.ag_listener_ip1 is not null
			--
			union
			--
			select ag.ag_listener_name, ag_listener_ip = ag.ag_listener_ip2
			from dbo.sma_servers s
			join dbo.sma_hadr_ag ag
				on ag.server = s.server
			where s.is_decommissioned = 0
			and ag.is_decommissioned = 0
			and s.hadr_strategy = 'ag'
			and ag.ag_listener_ip2 is not null
		)
		select id.sql_instance, id.sql_instance_port, id.host_name, id.is_enabled, id.data_destination_sql_instance, id.created_date_utc
		into #wrong_entry_on_listeners
		from dbo.instance_details id
		where id.is_enabled = 1
		and id.is_alias = 0 
		and id.sql_instance in (select ag.ag_listener_ip from t_ags ag);

			
		set @_table_row_count = (select count(*) from #wrong_entry_on_listeners);

		if @_table_row_count > 0
		begin
			print 'Send mail for Wrong AG Listener Entry in dbo.instance_details..';

			if @verbose >= 2
			begin
				select t.*, ag.*
				from #wrong_entry_on_listeners ag				
				full outer join
					(select RunningQuery = 'Wrong-Entry-in-SQLMonitor') t
					on 1=1;
			end

			set @_recepient = @dba_team_email_id;
			set @_copy_recipients = @dba_manager_email_id

			begin try
				set @_table_data = null;

				set @_table_headline = N'<h3>Following Ag Listener are added as SQLInstance in SQLMonitor table <code>dbo.instance_details instead of being an Alias Entry.</code> Kindly remove them, and re-added them as <b>Alias</b>.</h3>'+@_crlf

				set @_table_header = N'<tr><th>SQL Instance</th> <th>Port</th> <th>Host Name</th> <th>Is Enabled</th>'
											+'<th>Data Destination Server</th> <th>Created Date</th> </tr>'+@_crlf;
				
				;with t_login_info as (
					select al.sql_instance, al.sql_instance_port, al.host_name, al.is_enabled, 
							al.data_destination_sql_instance, 
							[created_date] = DATEADD(mi, DATEDIFF(mi, GETUTCDATE(), GETDATE()), al.created_date_utc)
					from #wrong_entry_on_listeners al
				)
				,t_table_rows as (
					select	'<tr>'
								+'<td class="bg_key"><a href="'+@_url_individual_server_dashboard+'&var-server='+sql_instance+'" target="_blank">'+sql_instance+'</a></td>'
								+'<td>'+coalesce(convert(varchar,sql_instance_port),' ')+'</td>'
								+'<td>'+coalesce([host_name],' ')+'</td>'
								+'<td>'+coalesce(convert(varchar,is_enabled),' ')+'</td>'
								+'<td>'+coalesce(data_destination_sql_instance,' ')+'</td>'
								+'<td>'+coalesce(convert(varchar,[created_date]),' ')+'</td>'
							+'</tr>' as [table_row]
					from t_login_info
				)
				select @_table_data = coalesce(@_table_data+' '+[table_row],[table_row])
				from t_table_rows

				set @_mail_html_body = @_table_headline+'<div class="tableContainerDiv"><table border="1">'
										+'<caption>'+convert(varchar,@_table_row_count)+' rows</caption>'
										+'<thead>'+@_table_header+'</thead><tbody>'+isnull(@_table_data,'')+'</tbody></table></div>'+@_crlf;

				set @_mail_subject = 'Wrong AG Listener entries in SQLMonitor'+' - '+convert(varchar,@_start_time,120);
				set @_mail_html = '<html>'
										+N'<head>'
										+N'<title>'+@_mail_subject+'</title>'
										+@_style_css
										+N'</head>'
										+N'<body>'
										+N'<h1><a href="'+@_url_individual_server_dashboard+'" target="_blank">'+@_mail_subject+'</a></h1>'
										+N'<p>'+@_mail_html_body+N'</p>'
										+N'<br><br><br><p>Regards,<br>Job ['+@job_name+']</p>'
										+N'</body>';	
				if @verbose >= 1
				begin
					print @_long_star_line
					print '@_table_headline => '+@_crlf+@_table_headline
					print '@_table_header => '+@_crlf+@_table_header
					print '@_mail_html_body => '+@_crlf+@_mail_html_body
					print '@_table_data => '+@_crlf+@_table_data
					print '@_mail_html => '+@_crlf+@_mail_html+@_crlf
				end

				if @send_mail = 1
				begin
					if @_table_data is not null
					begin
						exec msdb.dbo.sp_send_dbmail 
											@recipients = @_recepient,
											@copy_recipients = @_copy_recipients,
											@subject = @_mail_subject,
											@body = @_mail_html,
											@importance = 'High',
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

				print @_crlf+@_long_star_line+@_crlf+'Error Occurred while sending mail.'+@_crlf+@_errorMessage+@_crlf+@_long_star_line+@_crlf;

				insert [dbo].[sma_errorlog]
				([collection_time], [function_name], [function_call_arguments], [server], [error], [remark], [executed_by], [executor_program_name])
				select	[collection_time] = @_start_time, [function_name] = 'usp_wrapper_populate_sma_sql_instance', 
						[function_call_arguments] = 'Send-Mail-4-Wrong-SqlInstance-Entry', [server] = null, [error] = @_errorMessage, 
						[remark] = null, [executed_by] = SUSER_NAME(), [executor_program_name] = program_name();
			end catch
		end
	end -- 'Send-Mail-4-Wrong-SqlInstance-Entry'


	if ('Update-Host-Ips' = 'Update-Host-Ips')
	begin
		print 'Update host ip addresses in dbo.sma_sql_server_hosts..';

		if object_id('tempdb..#sma_sql_server_hosts_wrapper') is not null
			drop table #sma_sql_server_hosts_wrapper;
		select w.*
		into #sma_sql_server_hosts_wrapper
		from dbo.sma_sql_server_hosts_wrapper w
		join dbo.sma_sql_server_hosts h
			on h.server = w.sql_instance
			and h.host_name = w.host_name
		join dbo.sma_servers s
			on s.server = h.server
		where 1=1
		and s.is_decommissioned = 0
		and h.is_decommissioned = 0
		and h.host_ips is null;

		if @verbose >= 2
		begin
			select t.*, h.*
			from #sma_sql_server_hosts_wrapper h
			full outer join
				(select RunningQuery = 'Host-IPs-dbo.sma_sql_server_hosts_wrapper') t
				on 1=1;
		end

		update h set host_ips = w.Ip
		from #sma_sql_server_hosts_wrapper w
		join dbo.sma_sql_server_hosts h
			on h.server = w.sql_instance
			and h.host_name = w.host_name
		where 1=1;
	end -- 'Update-Host-Ips'

	if ('Update-Hadr-SQLCluster' = 'Update-Hadr-SQLCluster')
	begin
		print 'Update dbo.sma_servers hadr_strategy column for SQLClusters..';

		if object_id('tempdb..#sql_clusters') is not null
			drop table #sql_clusters;
		select *
		into #sql_clusters
		from dbo.sma_servers s
		where s.is_decommissioned = 0
		and ( s.hadr_strategy is null or s.hadr_strategy <> 'sqlcluster')
		and exists (select * from dbo.sma_hadr_sql_cluster sc 
						where sc.is_decommissioned = 0 and sc.server = s.server);

		if @verbose >= 2
		begin
			select t.*, h.*
			from #sql_clusters h
			full outer join
				(select RunningQuery = 'Update-Hadr-SQLCluster') t
				on 1=1;
		end

		update s set has_hadr = 1, hadr_strategy = 'sqlcluster'
		from #sql_clusters sc
		join dbo.sma_servers s
			on s.server = sc.server
		where 1=1;
	end -- 'Update-Hadr-SQLCluster'

	if ('Update-Hadr-AG' = 'Update-Hadr-AG')
	begin
		print 'Update dbo.sma_servers hadr_strategy column for AGs..';

		if object_id('tempdb..#sql_ag') is not null
			drop table #sql_ag;
		select *
		into #sql_ag
		from dbo.sma_servers s
		where s.is_decommissioned = 0
		and ( s.hadr_strategy is null or s.hadr_strategy <> 'ag')
		and exists (select * from dbo.sma_hadr_ag ag where ag.is_decommissioned = 0 and ag.server = s.server);

		if @verbose >= 2
		begin
			select t.*, h.*
			from #sql_ag h
			full outer join
				(select RunningQuery = 'Update-Hadr-AG') t
				on 1=1;
		end

		update s set has_hadr = 1, hadr_strategy = 'ag'
		from #sql_ag ag
		join dbo.sma_servers s
			on s.server = ag.server
		where 1=1;
	end -- 'Update-Hadr-AG'
end
go


--exec dbo.usp_wrapper_populate_sma_sql_instance
--					@dba_team_email_id = 'sqlagentservice@gmail.com',
--					@dba_manager_email_id = 'sqlagentservice@gmail.com',
--					@sre_vp_email_id = 'sqlagentservice@gmail.com',
--					@send_mail = 1, @verbose = 2, @truncate_log_table = 0
go


-- select * from dbo.sma_servers_logs l;
go
--exec dbo.usp_populate_sma_sql_instance @server = '192.168.1.5' ,@execute = 1 ,@verbose = 2;
go