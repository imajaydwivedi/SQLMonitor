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

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_purge_tables')
    EXEC ('CREATE PROC dbo.usp_purge_tables AS SELECT ''stub version, to be replaced''')
GO

ALTER PROCEDURE dbo.usp_purge_tables
	@verbose tinyint = 0,
	@dry_run bit = 0
AS 
BEGIN

	/*
		Version:		1.0.1
		Date:			2022-10-01 - Parameterization

		EXEC dbo.usp_purge_tables @verbose = 2, @dry_run = 1;
	*/
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	declare @c_table_name sysname;
	declare @c_date_key sysname;
	declare @c_retention_days smallint;
	declare @c_purge_row_size int;
	declare @_sql nvarchar(max);
	declare @_params nvarchar(max);
	declare @_err_message nvarchar(2000);
	declare @_crlf nchar(2);
	declare @_tab nchar(1);
	declare @_tables nvarchar(2000);

	set @_crlf = nchar(13)+nchar(10);
	set @_tab = nchar(9);
	

	if @verbose >= 2
	begin
		select running_query = 'dbo.purge_table', 
				is_existing = case when OBJECT_ID(table_name) is null then 0 else 1 end, 
				* 
		from dbo.purge_table 
		--where OBJECT_ID(table_name) is not null;
	end

	-- Find tables that do not exist
	select @_tables = coalesce(@_tables+','+@_crlf+@_tab+table_name,table_name)
	from dbo.purge_table where OBJECT_ID(table_name) is null;

	if @_tables is not null
		print 'WARNING:- Following tables do not exists.'+@_crlf+@_tab+@_tables+@_crlf+@_crlf;

	declare cur_purge_tables cursor local forward_only for
		select table_name, date_key, retention_days, purge_row_size 
		from dbo.purge_table where OBJECT_ID(table_name) is not null;

	open cur_purge_tables;
	fetch next from cur_purge_tables into @c_table_name, @c_date_key, @c_retention_days, @c_purge_row_size;

	while @@FETCH_STATUS = 0
	begin
		print 'Processing table '+@c_table_name;

		set @_params = N'@purge_row_size int, @retention_days smallint';

		--set quoted_identifier off;
		set @_sql = '
		DECLARE @r INT;
	
		SET @r = 1;
		while @r > 0
		begin
			/* dbo.usp_purge_tables */
			delete top (@purge_row_size) pt
			from '+@c_table_name+' pt
			where '+@c_date_key+' < dateadd(day,-@retention_days,cast(getdate() as date));

			set @r = @@ROWCOUNT;
		end
		'
		--set quoted_identifier on;
		begin try
			if @verbose > 0
				print @_crlf+@_tab+@_tab+'declare '+@_params+';'+@_crlf+@_sql+@_crlf;
			if @dry_run = 0
			begin
				exec sp_executesql @_sql, @_params, @c_purge_row_size, @c_retention_days;
				update dbo.purge_table set latest_purge_datetime = SYSDATETIME() where table_name = @c_table_name;
			end
		end try
		begin catch
			set @_err_message = isnull(@_err_message,'') + char(10) + 'Error while purging table '+@c_table_name+'.'+char(10)+ ERROR_MESSAGE()+char(10);
		end catch
		fetch next from cur_purge_tables into @c_table_name, @c_date_key, @c_retention_days, @c_purge_row_size;
	end
	close cur_purge_tables;
	deallocate cur_purge_tables;

	if @_err_message is not null
    raiserror (@_err_message, 20, -1) with log;
END
GO
