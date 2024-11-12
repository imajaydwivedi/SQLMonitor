USE [DBA];
-- Find long running statements
declare @collection_time_start smalldatetime --= dateadd(day,-5,getdate()) --'2024-01-25 00:00';
declare @collection_time_end smalldatetime --= getdate() --'2024-02-05 00:00';
declare @no_of_days tinyint = 7;
declare @database_name nvarchar(255) = 'StackOverflow';
declare @table_name nvarchar(225) = 'Posts';
declare @force_plan_search bit = 1;
declare @index_name nvarchar(255) = 'CreatedDate';
declare @query_text nvarchar(500) = 'Posts';
declare @program_name nvarchar(255) --= 'SQLQueryStress';
declare @login_name nvarchar(255) --= 'SQLQueryStress';
declare @session_id int = null;
declare @host_name nvarchar(255) --= '';
declare @duration_threshold_minutes smallint = 0;
declare @memory_threshold_mb smallint --= 1;
declare @handle_xml_error bit = 0;
declare @ignore_blocking bit = 1;
declare @sql nvarchar(max);
declare @params nvarchar(max);

set @params = N'@collection_time_start smalldatetime,
				@collection_time_end smalldatetime,
				@table_name nvarchar(225),
				@query_text nvarchar(500),
				@database_name nvarchar(255), 
				@program_name nvarchar(255),
				@login_name nvarchar(255),
				@host_name nvarchar(255),
				@index_name nvarchar(255), 
				@duration_threshold_minutes smallint,
				@memory_threshold_mb smallint,
				@session_id int';

if @collection_time_start is not null and @no_of_days is not null
	throw 50000, 'Parameters @collection_time_start & @no_of_days are not compatible.', 1;
else if @no_of_days is not null
begin
	set @collection_time_end = coalesce(@collection_time_end, getdate());
	set @collection_time_start = dateadd(day,-@no_of_days,@collection_time_end);
end

declare @crlf nvarchar(10) = char(13)+char(10);
set quoted_identifier off;
set @sql = "
;with xmlnamespaces ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' as qp),
t_WhoIsActive as (
	select * 
			,[sql_handle] = additional_info.value('(/additional_info/sql_handle)[1]','varchar(500)')
			,[command_type] = additional_info.value('(/additional_info/command_type)[1]','varchar(50)')
			,[used_memory_mb] = used_memory*8.0/1024
			,[granted_memory_mb] = granted_memory*8.0/1024
			,[duration_minutes] = DATEDIFF_BIG(MILLISECOND,start_time,collection_time)/1000/60
			,[duration_ms] = DATEDIFF_BIG(MILLISECOND,start_time,collection_time)
			--"+(case when @handle_xml_error = 1 then '' else '--' end)+",[Microsoft SQL Server 2005 XML Showplan] = w.query_plan
	from dbo.WhoIsActive w
	where w.collection_time between @collection_time_start and @collection_time_end
	and additional_info.value('(/additional_info/command_type)[1]','varchar(50)') not in ('ALTER INDEX','UPDATE STATISTICS','DBCC','BACKUP LOG','BACKUP DATABASE')
	"+(case when @program_name is null then "--" else '' end)+"and w.program_name = @program_name
	"+(case when @login_name is null then "--" else '' end)+"and w.login_name = @login_name
	"+(case when @host_name is null then "--" else '' end)+"and w.host_name = @host_name
	"+(case when @session_id is null then "--" else '' end)+"and w.session_id = @session_id
	"+(case when @ignore_blocking = 1 then "" else "--" end)+"and w.blocking_session_id is null
	"+(case when @duration_threshold_minutes is null then "--" else '' end)+"and w.start_time <= dateadd(minute,-@duration_threshold_minutes,w.collection_time)
	"+(case when @force_plan_search = 1 and @table_name is not null then "" else "--" end)+"and convert(nvarchar(max),w.[query_plan]) like ('% Table=""!['+@table_name+'!]""%') escape '!'
	"+(case when @index_name is null then "--" else '' end)+" and convert(nvarchar(max),w.[query_plan]) like ('% Index=""!['+@index_name+'!]""%') escape '!'

	"+(case when @query_text is null then "" else '--' end)+"/*
	and (	w.sql_text like ('%'+@query_text+'%') escape '!'
			or w.sql_command like ('%'+@query_text+'%') escape '!'
		)
	"+(case when @query_text is null then "" else '--' end)+"*/	

	"+(case when @database_name is null then "" else '--' end)+"/*
	and	(	w.database_name = @database_name
			or convert(nvarchar(max),w.[query_plan]) like ('%Database=""!['+@database_name+'!]""%') escape '!'
		)
	"+(case when @database_name is null then "" else '--' end)+"*/	

	"+(case when @table_name is null then "" else '--' end)+"/*
	and	(		w.sql_text like ('%'+@table_name+'%') escape '!'
			or	w.sql_command like ('%'+@table_name+'%') escape '!'
			or	convert(nvarchar(max),w.[query_plan]) like ('% Table=""!['+@table_name+'!]""%') escape '!'
		)
	"+(case when @table_name is null then "" else '--' end)+"*/	
)
,t_queries as (
	select	* 
			"+(case when @handle_xml_error = 1 then "--" else '' end)+",[query_hash] = [query_plan].value('(/*:ShowPlanXML/*:BatchSequence/*:Batch/*:Statements/*:StmtSimple)[1]/@QueryHash','varchar(100)')
			"+(case when @handle_xml_error = 1 then "--" else '' end)+",[query_plan_hash] = [query_plan].value('(/*:ShowPlanXML/*:BatchSequence/*:Batch/*:Statements/*:StmtSimple)[1]/@QueryPlanHash','varchar(100)')
			"+(case when @handle_xml_error = 1 then "--" else '' end)+",[NonParallelPlanReason] = [query_plan].value('(/*:ShowPlanXML/*:BatchSequence/*:Batch/*:Statements/*:StmtSimple/*:QueryPlan)[1]/@NonParallelPlanReason','varchar(200)')

			"+(case when @handle_xml_error = 1 then "--" else '' end)+"/*
			,[query_hash] = null
			,[query_plan_hash] = null
			,[NonParallelPlanReason] = null
			"+(case when @handle_xml_error = 1 then "--" else '' end)+"*/
	from t_WhoIsActive w	
	where 1=1
)
,t_capture_interval as (
	select [capture_interval_sec] = DATEDIFF(SECOND,snap1.collection_time_min, collection_time_snap2) 
	from (select min(collection_time) as collection_time_min from t_queries) snap1
	outer apply (select min(s2.collection_time) as collection_time_snap2 from t_queries s2 where s2.collection_time > snap1.collection_time_min) snap2
)
,top_queries as (
	select	*,
			[query_identity] = left((case when [query_hash] is not null then [query_hash] 
											when [sql_handle] is not null then [sql_handle]
											else isnull(sql_text,[sql_command]) 
											end),20)
			,[query_identity_type] = (case when [query_hash] is not null then 'query_hash'
											when [sql_handle] is not null then 'sql_handle'
											when sql_text is not null then 'sql_text'
											when sql_command is not null then 'sql_command'
											else 'none' 
											end)
			,[query_hash_count] = COUNT(session_id)over(partition by (case when [query_hash] is not null then [query_hash] 
																		  when [sql_handle] is not null then [sql_handle]
																		  else isnull(sql_text,[sql_command])
																		  end))
			,[query_plan_count] = COUNT(1) over (partition by [query_hash], [query_plan_hash])
			,[query_identifier_rowid] = ROW_NUMBER()over(partition by left((case when [query_hash] is not null then [query_hash] 
											when [sql_handle] is not null then [sql_handle]
											else isnull(sql_text,[sql_command]) 
											end),20) order by [duration_minutes] desc)
	from t_queries w
	where 1=1
	"+(case when @memory_threshold_mb is null then '--' else '' end)+"and [used_memory_mb] > @memory_threshold_mb
)
select top 200 
		[dd hh:mm:ss.mss] = right('0000'+convert(varchar, duration_ms/86400000),3)+ ' '+
									convert(varchar,dateadd(MILLISECOND,duration_ms,'1900-01-01 00:00:00'),114),
		[query_hash_count], [identifier] = [query_identity_type]+' ('+[query_identity]+')', 	
		[command_type], [sql_command], [sql_text], [query_plan], 
		[session_details] = 'login=>'+login_name+' || '+'program=>'+program_name+' || '+'database=>'+[database_name]+' || '+'host_name=>'+host_name,
		[reads], [CPU], [used_memory_mb], [open_tran_count], 
		[status], [wait_info],  [blocked_session_count],  [writes], [tempdb_allocations], [tasks], 		 
		[query_plan_hash], [NonParallelPlanReason], [host_name], [additional_info], [program_name], [login_name], 
		[database_name], [duration_minutes],
		[session_id], [blocking_session_id], [batch_start_time] = [start_time], [capture_interval_sec],
		[query_hash], 
		[sql_handle],
		[collection_time]
from top_queries,t_capture_interval
where [query_identifier_rowid] = 1
order by [query_hash_count] desc
option (recompile);
"
set quoted_identifier on;

print @sql

exec sp_ExecuteSql @sql, @params, 
						@collection_time_start, @collection_time_end, @table_name, @query_text, @database_name, @program_name,
						@login_name, @host_name, @index_name, @duration_threshold_minutes, @memory_threshold_mb,
						@session_id;

/*
select top 10000 sql_text2 = convert(xml,(select sql_text for xml path(''))),*
from dbo.xevent_metrics rc
where rc.event_time >= dateadd(day,-7,getdate()) and event_time <= getdate()
and (	convert(nvarchar(max),sql_text) like '%[[. ]Posts[!] ]%' escape '!' )

*/
