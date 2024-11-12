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

IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'usp_partition_maintenance')
    EXEC ('CREATE PROC dbo.usp_partition_maintenance AS SELECT ''stub version, to be replaced''')
GO

ALTER PROCEDURE dbo.usp_partition_maintenance
	@step varchar(100) = null, /* Any particular step */
	@hourly_retention_days int = 90, /* Hourly Partition Merge Threshold */
	@daily_retention_days int = 750, /* Daily Partition Merge Threshold */
	@monthly_retention_days int = 1770, /* Monthly Partition Merge Threshold */
	@quarterly_retention_days int = 1770, /* Quarterly Partition Merge Threshold */
	@verbose tinyint = 0, /* {0,1,2} = {no message, print messages, all messages} */
	@dry_run bit = 0 /* When enabled, don't execute actual code */
AS 
BEGIN

	/*
		Version:		1.0.1
		Date:			2022-10-10 - Added new partition scheme maintenance - Hourly, Daily, Monthly, Quarterly

		EXEC dbo.usp_partition_maintenance @step = 'add_partition_datetime2_hourly', @verbose = 2, @dry_run = 1;
		EXEC dbo.usp_partition_maintenance @step = 'remove_partition_datetime2_hourly', @verbose = 2, @dry_run = 1;
	*/
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET QUOTED_IDENTIFIER ON;
	SET DEADLOCK_PRIORITY HIGH;

	declare @err_message nvarchar(2000);
	declare @current_step_name varchar(50);
	declare @current_boundary_value datetime2;
	declare @target_boundary_value datetime2; /* last day of new quarter */
	declare @current_time datetime2;
	declare @partition_boundary datetime2;
	--declare @pf_name varchar(125);
	--declare @ps_name varchar(125);
	declare @sql nvarchar(max);
	declare @params nvarchar(max);
	declare @crlf nchar(2);
	declare @tab nchar(1);
	set @crlf = nchar(13)+nchar(10);
	set @tab = nchar(9);

	if @verbose > 0
		print 'Validate parameters..'

	if @step is not null and @step not in (	'add_partition_datetime2_hourly_old','add_partition_datetime2_hourly','add_partition_datetime2_daily',
											'add_partition_datetime2_monthly','add_partition_datetime2_quarterly',
											'add_partition_datetime_hourly_old','add_partition_datetime_hourly','add_partition_datetime_daily',
											'add_partition_datetime_monthly','add_partition_datetime_quarterly',
											--
											'remove_partition_datetime2_hourly_old','remove_partition_datetime2_hourly','remove_partition_datetime2_daily',
											'remove_partition_datetime2_monthly','remove_partition_datetime2_quarterly',
											'remove_partition_datetime_hourly_old','remove_partition_datetime_hourly','remove_partition_datetime_daily',
											'remove_partition_datetime_monthly','remove_partition_datetime_quarterly')
		raiserror ('@step parameter value not valid', 20, -1) with log;

	set @current_step_name = 'add_partition_datetime2_hourly_old'
	if ( (@step is null or @step = @current_step_name) and exists (select * from sys.partition_schemes ps where ps.name = 'ps_dba') )
	begin
		if @verbose > 0
			print @crlf+'@current_step_name = '+quotename(@current_step_name,'''');
		begin try
			set @current_time = (case when sysdatetime() > sysutcdatetime() then sysdatetime() else sysutcdatetime() end);
			set @target_boundary_value = DATEADD (dd, -1, DATEADD(qq, DATEDIFF(qq, 0, @current_time) +2, 0));

			if @verbose > 0
				print @tab+'Checking @current_boundary_value for [ps_dba] partition scheme';
			select top 1 @current_boundary_value = convert(datetime2,prv.value)
			from sys.partition_range_values prv
			join sys.partition_functions pf on pf.function_id = prv.function_id
			join sys.partition_schemes as ps on ps.function_id = pf.function_id
			where pf.name = 'pf_dba' and ps.name = 'ps_dba'
			order by prv.value desc;

			if(@current_boundary_value is null or @current_boundary_value < @current_time )
			begin
				print @tab+'Warning - @current_boundary_value is NULL or its previous to current time.';
				set @current_boundary_value = dateadd(hour,datediff(hour,convert(date,@current_time),@current_time),cast(convert(date,@current_time)as datetime2));
				if (@current_step_name not like '%hourly') -- convert to 12:00 am time
					set @current_boundary_value = convert(date,@current_boundary_value)
			end

			if @verbose > 0
			begin
				print @tab+'@current_boundary_value = '+ convert(varchar,@current_boundary_value,120);
				print @tab+'@target_boundary_value = '+ convert(varchar,@target_boundary_value,120);
			end

			if (@current_boundary_value < @target_boundary_value)
			begin
				set @sql =	N'alter partition scheme ps_dba next used [PRIMARY];'+@crlf+
							N'alter partition function pf_dba() split range (@current_boundary_value);';
				set @params = N'@current_boundary_value datetime2';

				if @verbose > 0
				begin
					print @tab+'Start loop if (@current_boundary_value < @target_boundary_value)..';
					print @crlf+'declare '+@params+';';
					print @sql+@crlf+@crlf;
				end
			end
			else
			begin
				if @verbose > 0
					print @tab+'No action required in this step.';
			end

			while (@current_boundary_value < @target_boundary_value)
			begin
				set @current_boundary_value = DATEADD(hour,1,@current_boundary_value);
				if @verbose > 0
					print @tab+@tab+'@current_boundary_value = '+ convert(varchar,@current_boundary_value,120);

				set @sql = '/* usp_partition_maintenance */ '+@sql;
				if @dry_run = 0
					exec sp_executesql @sql, @params, @current_boundary_value;
				else
					print @tab+@tab+'DRY RUN: add partition boundary..'
			end
		end try
		begin catch
			set @err_message = isnull(@err_message,'') + char(10) + 'Error in step ['+@current_step_name+'.'+char(10)+ ERROR_MESSAGE()+char(10);
		end catch
	end


	set @current_step_name = 'add_partition_datetime2_hourly'
	if ( (@step is null or @step = @current_step_name) and exists (select * from sys.partition_schemes ps where ps.name = 'ps_dba_datetime2_hourly') )
	begin
		if @verbose > 0
			print @crlf+'@current_step_name = '+quotename(@current_step_name,'''');
		begin try
			set @current_time = (case when sysdatetime() > sysutcdatetime() then sysdatetime() else sysutcdatetime() end);
			set @target_boundary_value = DATEADD (dd, -1, DATEADD(qq, DATEDIFF(qq, 0, @current_time) +2, 0));

			if @verbose > 0
				print @tab+'Checking @current_boundary_value for [ps_dba_datetime2_hourly] partition scheme';
			select top 1 @current_boundary_value = convert(datetime2,prv.value)
			from sys.partition_range_values prv
			join sys.partition_functions pf on pf.function_id = prv.function_id
			join sys.partition_schemes as ps on ps.function_id = pf.function_id
			where pf.name = 'pf_dba_datetime2_hourly' and ps.name = 'ps_dba_datetime2_hourly'
			order by prv.value desc;

			if(@current_boundary_value is null or @current_boundary_value < @current_time )
			begin
				print @tab+'Warning - @current_boundary_value is NULL or its previous to current time.';
				set @current_boundary_value = dateadd(hour,datediff(hour,convert(date,@current_time),@current_time),cast(convert(date,@current_time)as datetime2));
				if (@current_step_name not like '%hourly') -- convert to 12:00 am time
					set @current_boundary_value = convert(date,@current_boundary_value)
			end

			if @verbose > 0
			begin
				print @tab+'@current_boundary_value = '+ convert(varchar,@current_boundary_value,120);
				print @tab+'@target_boundary_value = '+ convert(varchar,@target_boundary_value,120);
			end

			if (@current_boundary_value < @target_boundary_value)
			begin
				set @sql =	N'alter partition scheme ps_dba_datetime2_hourly next used [PRIMARY];'+@crlf+
							N'alter partition function pf_dba_datetime2_hourly() split range (@current_boundary_value);';
				set @params = N'@current_boundary_value datetime2';

				if @verbose > 0
				begin
					print @tab+'Start loop if (@current_boundary_value < @target_boundary_value)..';
					print @crlf+'declare '+@params+';';
					print @sql+@crlf+@crlf;
				end
			end
			else
			begin
				if @verbose > 0
					print @tab+'No action required in this step.';
			end

			while (@current_boundary_value < @target_boundary_value)
			begin
				set @current_boundary_value = DATEADD(hour,1,@current_boundary_value);
				if @verbose > 0
					print @tab+@tab+'@current_boundary_value = '+ convert(varchar,@current_boundary_value,120);

				set @sql = '/* usp_partition_maintenance */ '+@sql;
				if @dry_run = 0
					exec sp_executesql @sql, @params, @current_boundary_value;
				else
					print @tab+@tab+'DRY RUN: add partition boundary..'
			end
		end try
		begin catch
			set @err_message = isnull(@err_message,'') + char(10) + 'Error in step ['+@current_step_name+'.'+char(10)+ ERROR_MESSAGE()+char(10);
		end catch
	end


	set @current_step_name = 'add_partition_datetime2_daily'
	if ( (@step is null or @step = @current_step_name) and exists (select * from sys.partition_schemes ps where ps.name = 'ps_dba_datetime2_daily') )
	begin
		if @verbose > 0
			print @crlf+'@current_step_name = '+quotename(@current_step_name,'''');
		begin try
			set @current_time = (case when sysdatetime() > sysutcdatetime() then sysdatetime() else sysutcdatetime() end);
			set @target_boundary_value = DATEADD (dd, -1, DATEADD(qq, DATEDIFF(qq, 0, @current_time) +4, 0));

			if @verbose > 0
				print @tab+'Checking @current_boundary_value for [ps_dba_datetime2_daily] partition scheme';
			select top 1 @current_boundary_value = convert(datetime2,prv.value)
			from sys.partition_range_values prv
			join sys.partition_functions pf on pf.function_id = prv.function_id
			join sys.partition_schemes as ps on ps.function_id = pf.function_id
			where pf.name = 'pf_dba_datetime2_daily' and ps.name = 'ps_dba_datetime2_daily'
			order by prv.value desc;

			if(@current_boundary_value is null or @current_boundary_value < @current_time )
			begin
				print @tab+'Warning - @current_boundary_value is NULL or its previous to current time.';
				set @current_boundary_value = dateadd(hour,datediff(hour,convert(date,@current_time),@current_time),cast(convert(date,@current_time)as datetime2));
				if (@current_step_name not like '%hourly') -- convert to 12:00 am time
					set @current_boundary_value = convert(date,@current_boundary_value)
			end

			if @verbose > 0
			begin
				print @tab+'@current_boundary_value = '+ convert(varchar,@current_boundary_value,120);
				print @tab+'@target_boundary_value = '+ convert(varchar,@target_boundary_value,120);
			end

			if (@current_boundary_value < @target_boundary_value)
			begin
				set @sql =	N'alter partition scheme ps_dba_datetime2_daily next used [PRIMARY];'+@crlf+
							N'alter partition function pf_dba_datetime2_daily() split range (@current_boundary_value);';
				set @params = N'@current_boundary_value datetime2';

				if @verbose > 0
				begin
					print @tab+'Start loop if (@current_boundary_value < @target_boundary_value)..';
					print @crlf+'declare '+@params+';';
					print @sql+@crlf+@crlf;
				end
			end
			else
			begin
				if @verbose > 0
					print @tab+'No action required in this step.';
			end

			while (@current_boundary_value < @target_boundary_value)
			begin
				set @current_boundary_value = DATEADD(DAY,1,@current_boundary_value);
				if @verbose > 0
					print @tab+@tab+'@current_boundary_value = '+ convert(varchar,@current_boundary_value,120);

				set @sql = '/* usp_partition_maintenance */ '+@sql;
				if @dry_run = 0
					exec sp_executesql @sql, @params, @current_boundary_value;
				else
					print @tab+@tab+'DRY RUN: add partition boundary..'
			end
		end try
		begin catch
			set @err_message = isnull(@err_message,'') + char(10) + 'Error in step ['+@current_step_name+'.'+char(10)+ ERROR_MESSAGE()+char(10);
		end catch
	end


	set @current_step_name = 'add_partition_datetime2_monthly'
	if ( (@step is null or @step = @current_step_name) and exists (select * from sys.partition_schemes ps where ps.name = 'ps_dba_datetime2_monthly') )
	begin
		if @verbose > 0
			print @crlf+'@current_step_name = '+quotename(@current_step_name,'''');
		begin try
			set @current_time = (case when sysdatetime() > sysutcdatetime() then sysdatetime() else sysutcdatetime() end);
			set @target_boundary_value = DATEADD (dd, -1, DATEADD(qq, DATEDIFF(qq, 0, @current_time) +4, 0));

			if @verbose > 0
				print @tab+'Checking @current_boundary_value for [ps_dba_datetime2_monthly] partition scheme';
			select top 1 @current_boundary_value = convert(datetime2,prv.value)
			from sys.partition_range_values prv
			join sys.partition_functions pf on pf.function_id = prv.function_id
			join sys.partition_schemes as ps on ps.function_id = pf.function_id
			where pf.name = 'pf_dba_datetime2_monthly' and ps.name = 'ps_dba_datetime2_monthly'
			order by prv.value desc;

			if(@current_boundary_value is null or @current_boundary_value < @current_time )
			begin
				print @tab+'Warning - @current_boundary_value is NULL or its previous to current time.';
				set @current_boundary_value = dateadd(hour,datediff(hour,convert(date,@current_time),@current_time),cast(convert(date,@current_time)as datetime2));
				if (@current_step_name not like '%hourly') -- convert to 12:00 am time
					set @current_boundary_value = convert(date,@current_boundary_value)
			end
			
			if @verbose > 0
			begin
				print @tab+'@current_boundary_value = '+ convert(varchar,@current_boundary_value,120);
				print @tab+'@target_boundary_value = '+ convert(varchar,@target_boundary_value,120);
			end

			if (@current_boundary_value < @target_boundary_value)
			begin
				set @sql =	N'alter partition scheme ps_dba_datetime2_monthly next used [PRIMARY];'+@crlf+
							N'alter partition function pf_dba_datetime2_monthly() split range (@current_boundary_value);';
				set @params = N'@current_boundary_value datetime2';

				if @verbose > 0
				begin
					print @tab+'Start loop if (@current_boundary_value < @target_boundary_value)..';
					print @crlf+'declare '+@params+';';
					print @sql+@crlf+@crlf;
				end
			end
			else
			begin
				if @verbose > 0
					print @tab+'No action required in this step.';
			end

			while (@current_boundary_value < @target_boundary_value)
			begin
				set @current_boundary_value = DATEADD(month, DATEDIFF(month, 0, DATEADD(MONTH,1,@current_boundary_value)), 0);
				if @verbose > 0
					print @tab+@tab+'@current_boundary_value = '+ convert(varchar,@current_boundary_value,120);
				set @sql = '/* usp_partition_maintenance */ '+@sql;
				if @dry_run = 0
					exec sp_executesql @sql, @params, @current_boundary_value;
				else
					print @tab+@tab+'DRY RUN: add partition boundary..'
			end
		end try
		begin catch
			set @err_message = isnull(@err_message,'') + char(10) + 'Error in step ['+@current_step_name+'.'+char(10)+ ERROR_MESSAGE()+char(10);
		end catch
	end


	set @current_step_name = 'add_partition_datetime2_quarterly'
	if ( (@step is null or @step = @current_step_name) and exists (select * from sys.partition_schemes ps where ps.name = 'ps_dba_datetime2_quarterly') )
	begin
		if @verbose > 0
			print @crlf+'@current_step_name = '+quotename(@current_step_name,'''');
		begin try
			set @current_time = (case when sysdatetime() > sysutcdatetime() then sysdatetime() else sysutcdatetime() end);
			set @target_boundary_value = DATEADD (dd, -1, DATEADD(qq, DATEDIFF(qq, 0, @current_time) +6, 0));

			if @verbose > 0
				print @tab+'Checking @current_boundary_value for [ps_dba_datetime2_quarterly] partition scheme';
			select top 1 @current_boundary_value = convert(datetime2,prv.value)
			from sys.partition_range_values prv
			join sys.partition_functions pf on pf.function_id = prv.function_id
			join sys.partition_schemes as ps on ps.function_id = pf.function_id
			where pf.name = 'pf_dba_datetime2_quarterly' and ps.name = 'ps_dba_datetime2_quarterly'
			order by prv.value desc;

			if(@current_boundary_value is null or @current_boundary_value < @current_time )
			begin
				print @tab+'Warning - @current_boundary_value is NULL or its previous to current time.';
				set @current_boundary_value = dateadd(hour,datediff(hour,convert(date,@current_time),@current_time),cast(convert(date,@current_time)as datetime2));
				if (@current_step_name not like '%hourly') -- convert to 12:00 am time
					set @current_boundary_value = convert(date,@current_boundary_value)
			end
			
			if @verbose > 0
			begin
				print @tab+'@current_boundary_value = '+ convert(varchar,@current_boundary_value,120);
				print @tab+'@target_boundary_value = '+ convert(varchar,@target_boundary_value,120);
			end

			if (@current_boundary_value < @target_boundary_value)
			begin
				set @sql =	N'alter partition scheme ps_dba_datetime2_quarterly next used [PRIMARY];'+@crlf+
							N'alter partition function pf_dba_datetime2_quarterly() split range (@current_boundary_value);';
				set @params = N'@current_boundary_value datetime2';

				if @verbose > 0
				begin
					print @tab+'Start loop if (@current_boundary_value < @target_boundary_value)..';
					print @crlf+'declare '+@params+';';
					print @sql+@crlf+@crlf;
				end
			end
			else
			begin
				if @verbose > 0
					print @tab+'No action required in this step.';
			end

			while (@current_boundary_value < @target_boundary_value)
			begin
				set @current_boundary_value = DATEADD(month, DATEDIFF(month, 0, DATEADD(MONTH,3,@current_boundary_value)), 0);
				if @verbose > 0
					print @tab+@tab+'@current_boundary_value = '+ convert(varchar,@current_boundary_value,120);
				set @sql = '/* usp_partition_maintenance */ '+@sql;
				if @dry_run = 0
					exec sp_executesql @sql, @params, @current_boundary_value;
				else
					print @tab+@tab+'DRY RUN: add partition boundary..'
			end
		end try
		begin catch
			set @err_message = isnull(@err_message,'') + char(10) + 'Error in step ['+@current_step_name+'.'+char(10)+ ERROR_MESSAGE()+char(10);
		end catch
	end


	set @current_step_name = 'add_partition_datetime_hourly_old'
	if ( (@step is null or @step = @current_step_name) and exists (select * from sys.partition_schemes ps where ps.name = 'ps_dba_datetime') )
	begin
		if @verbose > 0
			print @crlf+'@current_step_name = '+quotename(@current_step_name,'''');
		begin try
			set @current_time = (case when getdate() > getutcdate() then getdate() else getutcdate() end);
			set @target_boundary_value = DATEADD (dd, -1, DATEADD(qq, DATEDIFF(qq, 0, @current_time) +2, 0));

			if @verbose > 0
				print @tab+'Checking @current_boundary_value for [ps_dba_datetime] partition scheme';
			select top 1 @current_boundary_value = convert(datetime,prv.value)
			from sys.partition_range_values prv
			join sys.partition_functions pf on pf.function_id = prv.function_id
			join sys.partition_schemes as ps on ps.function_id = pf.function_id
			where pf.name = 'pf_dba_datetime' and ps.name = 'ps_dba_datetime'
			order by prv.value desc;

			if(@current_boundary_value is null or @current_boundary_value < @current_time )
			begin
				print @tab+'Warning - @current_boundary_value is NULL or its previous to current time.';
				set @current_boundary_value = dateadd(hour,datediff(hour,convert(date,@current_time),@current_time),cast(convert(date,@current_time)as datetime));
				if (@current_step_name not like '%hourly') -- convert to 12:00 am time
					set @current_boundary_value = convert(date,@current_boundary_value)
			end

			if @verbose > 0
			begin
				print @tab+'@current_boundary_value = '+ convert(varchar,@current_boundary_value,120);
				print @tab+'@target_boundary_value = '+ convert(varchar,@target_boundary_value,120);
			end

			if (@current_boundary_value < @target_boundary_value)
			begin
				set @sql =	N'alter partition scheme ps_dba_datetime next used [PRIMARY];'+@crlf+
							N'alter partition function pf_dba_datetime() split range (@current_boundary_value);';
				set @params = N'@current_boundary_value datetime';

				if @verbose > 0
				begin
					print @tab+'Start loop if (@current_boundary_value < @target_boundary_value)..';
					print @crlf+'declare '+@params+';';
					print @sql+@crlf+@crlf;
				end
			end
			else
			begin
				if @verbose > 0
					print @tab+'No action required in this step.';
			end

			while (@current_boundary_value < @target_boundary_value)
			begin
				set @current_boundary_value = DATEADD(hour,1,@current_boundary_value);
				if @verbose > 0
					print @tab+@tab+'@current_boundary_value = '+ convert(varchar,@current_boundary_value,120);				
				set @sql = '/* usp_partition_maintenance */ '+@sql;
				if @dry_run = 0
					exec sp_executesql @sql, @params, @current_boundary_value;
				else
					print @tab+@tab+'DRY RUN: add partition boundary..'
			end
		end try
		begin catch
			set @err_message = isnull(@err_message,'') + char(10) + 'Error in step ['+@current_step_name+'.'+char(10)+ ERROR_MESSAGE()+char(10);
		end catch
	end


	set @current_step_name = 'add_partition_datetime_hourly'
	if ( (@step is null or @step = @current_step_name) and exists (select * from sys.partition_schemes ps where ps.name = 'ps_dba_datetime_hourly') )
	begin
		if @verbose > 0
			print @crlf+'@current_step_name = '+quotename(@current_step_name,'''');
		begin try
			set @current_time = (case when getdate() > getutcdate() then getdate() else getutcdate() end);
			set @target_boundary_value = DATEADD (dd, -1, DATEADD(qq, DATEDIFF(qq, 0, @current_time) +2, 0));

			if @verbose > 0
				print @tab+'Checking @current_boundary_value for [ps_dba_datetime_hourly] partition scheme';
			select top 1 @current_boundary_value = convert(datetime,prv.value)
			from sys.partition_range_values prv
			join sys.partition_functions pf on pf.function_id = prv.function_id
			join sys.partition_schemes as ps on ps.function_id = pf.function_id
			where pf.name = 'pf_dba_datetime_hourly' and ps.name = 'ps_dba_datetime_hourly'
			order by prv.value desc;

			if(@current_boundary_value is null or @current_boundary_value < @current_time )
			begin
				print @tab+'Warning - @current_boundary_value is NULL or its previous to current time.';
				set @current_boundary_value = dateadd(hour,datediff(hour,convert(date,@current_time),@current_time),cast(convert(date,@current_time)as datetime));
				if (@current_step_name not like '%hourly') -- convert to 12:00 am time
					set @current_boundary_value = convert(date,@current_boundary_value)
			end

			if @verbose > 0
			begin
				print @tab+'@current_boundary_value = '+ convert(varchar,@current_boundary_value,120);
				print @tab+'@target_boundary_value = '+ convert(varchar,@target_boundary_value,120);
			end

			if (@current_boundary_value < @target_boundary_value)
			begin
				set @sql =	N'alter partition scheme ps_dba_datetime_hourly next used [PRIMARY];'+@crlf+
							N'alter partition function pf_dba_datetime_hourly() split range (@current_boundary_value);';
				set @params = N'@current_boundary_value datetime';

				if @verbose > 0
				begin
					print @tab+'Start loop if (@current_boundary_value < @target_boundary_value)..';
					print @crlf+'declare '+@params+';';
					print @sql+@crlf+@crlf;
				end
			end
			else
			begin
				if @verbose > 0
					print @tab+'No action required in this step.';
			end

			while (@current_boundary_value < @target_boundary_value)
			begin
				set @current_boundary_value = DATEADD(hour,1,@current_boundary_value);
				if @verbose > 0
					print @tab+@tab+'@current_boundary_value = '+ convert(varchar,@current_boundary_value,120);				
				set @sql = '/* usp_partition_maintenance */ '+@sql;
				if @dry_run = 0
					exec sp_executesql @sql, @params, @current_boundary_value;
				else
					print @tab+@tab+'DRY RUN: add partition boundary..'
			end
		end try
		begin catch
			set @err_message = isnull(@err_message,'') + char(10) + 'Error in step ['+@current_step_name+'.'+char(10)+ ERROR_MESSAGE()+char(10);
		end catch
	end


	set @current_step_name = 'add_partition_datetime_daily'
	if ( (@step is null or @step = @current_step_name) and exists (select * from sys.partition_schemes ps where ps.name = 'ps_dba_datetime_daily') )
	begin
		if @verbose > 0
			print @crlf+'@current_step_name = '+quotename(@current_step_name,'''');
		begin try
			set @current_time = (case when getdate() > getutcdate() then getdate() else getutcdate() end);
			set @target_boundary_value = DATEADD (dd, -1, DATEADD(qq, DATEDIFF(qq, 0, @current_time) +4, 0));

			if @verbose > 0
				print @tab+'Checking @current_boundary_value for [ps_dba_datetime_daily] partition scheme';
			select top 1 @current_boundary_value = convert(datetime,prv.value)
			from sys.partition_range_values prv
			join sys.partition_functions pf on pf.function_id = prv.function_id
			join sys.partition_schemes as ps on ps.function_id = pf.function_id
			where pf.name = 'pf_dba_datetime_daily' and ps.name = 'ps_dba_datetime_daily'
			order by prv.value desc;

			if(@current_boundary_value is null or @current_boundary_value < @current_time )
			begin
				print @tab+'Warning - @current_boundary_value is NULL or its previous to current time.';
				set @current_boundary_value = dateadd(hour,datediff(hour,convert(date,@current_time),@current_time),cast(convert(date,@current_time)as datetime));
				if (@current_step_name not like '%hourly') -- convert to 12:00 am time
					set @current_boundary_value = convert(date,@current_boundary_value)
			end

			if @verbose > 0
			begin
				print @tab+'@current_boundary_value = '+ convert(varchar,@current_boundary_value,120);
				print @tab+'@target_boundary_value = '+ convert(varchar,@target_boundary_value,120);
			end

			if (@current_boundary_value < @target_boundary_value)
			begin
				set @sql =	N'alter partition scheme ps_dba_datetime_daily next used [PRIMARY];'+@crlf+
							N'alter partition function pf_dba_datetime_daily() split range (@current_boundary_value);';
				set @params = N'@current_boundary_value datetime';

				if @verbose > 0
				begin
					print @tab+'Start loop if (@current_boundary_value < @target_boundary_value)..';
					print @crlf+'declare '+@params+';';
					print @sql+@crlf+@crlf;
				end
			end
			else
			begin
				if @verbose > 0
					print @tab+'No action required in this step.';
			end

			while (@current_boundary_value < @target_boundary_value)
			begin
				set @current_boundary_value = DATEADD(DAY,1,@current_boundary_value);
				if @verbose > 0
					print @tab+@tab+'@current_boundary_value = '+ convert(varchar,@current_boundary_value,120);				
				set @sql = '/* usp_partition_maintenance */ '+@sql;
				if @dry_run = 0
					exec sp_executesql @sql, @params, @current_boundary_value;
				else
					print @tab+@tab+'DRY RUN: add partition boundary..'
			end
		end try
		begin catch
			set @err_message = isnull(@err_message,'') + char(10) + 'Error in step ['+@current_step_name+'.'+char(10)+ ERROR_MESSAGE()+char(10);
		end catch
	end


	set @current_step_name = 'add_partition_datetime_monthly'
	if ( (@step is null or @step = @current_step_name) and exists (select * from sys.partition_schemes ps where ps.name = 'ps_dba_datetime_monthly') )
	begin
		if @verbose > 0
			print @crlf+'@current_step_name = '+quotename(@current_step_name,'''');
		begin try
			set @current_time = (case when getdate() > getutcdate() then getdate() else getutcdate() end);
			set @target_boundary_value = DATEADD (dd, -1, DATEADD(qq, DATEDIFF(qq, 0, @current_time) +4, 0));

			if @verbose > 0
				print @tab+'Checking @current_boundary_value for [ps_dba_datetime_monthly] partition scheme';
			select top 1 @current_boundary_value = convert(datetime,prv.value)
			from sys.partition_range_values prv
			join sys.partition_functions pf on pf.function_id = prv.function_id
			join sys.partition_schemes as ps on ps.function_id = pf.function_id
			where pf.name = 'pf_dba_datetime_monthly' and ps.name = 'ps_dba_datetime_monthly'
			order by prv.value desc;

			if(@current_boundary_value is null or @current_boundary_value < @current_time )
			begin
				print @tab+'Warning - @current_boundary_value is NULL or its previous to current time.';
				set @current_boundary_value = dateadd(hour,datediff(hour,convert(date,@current_time),@current_time),cast(convert(date,@current_time)as datetime));
				if (@current_step_name not like '%hourly') -- convert to 12:00 am time
					set @current_boundary_value = convert(date,@current_boundary_value)
			end
			
			if @verbose > 0
			begin
				print @tab+'@current_boundary_value = '+ convert(varchar,@current_boundary_value,120);
				print @tab+'@target_boundary_value = '+ convert(varchar,@target_boundary_value,120);
			end

			if (@current_boundary_value < @target_boundary_value)
			begin
				set @sql =	N'alter partition scheme ps_dba_datetime_monthly next used [PRIMARY];'+@crlf+
							N'alter partition function pf_dba_datetime_monthly() split range (@current_boundary_value);';
				set @params = N'@current_boundary_value datetime';

				if @verbose > 0
				begin
					print @tab+'Start loop if (@current_boundary_value < @target_boundary_value)..';
					print @crlf+'declare '+@params+';';
					print @sql+@crlf+@crlf;
				end
			end
			else
			begin
				if @verbose > 0
					print @tab+'No action required in this step.';
			end

			while (@current_boundary_value < @target_boundary_value)
			begin
				set @current_boundary_value = DATEADD(month, DATEDIFF(month, 0, DATEADD(MONTH,1,@current_boundary_value)), 0);
				if @verbose > 0
					print @tab+@tab+'@current_boundary_value = '+ convert(varchar,@current_boundary_value,120);				
				set @sql = '/* usp_partition_maintenance */ '+@sql;
				if @dry_run = 0
					exec sp_executesql @sql, @params, @current_boundary_value;
				else
					print @tab+@tab+'DRY RUN: add partition boundary..'
			end
		end try
		begin catch
			set @err_message = isnull(@err_message,'') + char(10) + 'Error in step ['+@current_step_name+'.'+char(10)+ ERROR_MESSAGE()+char(10);
		end catch
	end


	set @current_step_name = 'add_partition_datetime_quarterly'
	if ( (@step is null or @step = @current_step_name) and exists (select * from sys.partition_schemes ps where ps.name = 'ps_dba_datetime_quarterly') )
	begin
		if @verbose > 0
			print @crlf+'@current_step_name = '+quotename(@current_step_name,'''');
		begin try
			set @current_time = (case when getdate() > getutcdate() then getdate() else getutcdate() end);
			set @target_boundary_value = DATEADD (dd, -1, DATEADD(qq, DATEDIFF(qq, 0, @current_time) +6, 0));

			if @verbose > 0
				print @tab+'Checking @current_boundary_value for [ps_dba_datetime_quarterly] partition scheme';
			select top 1 @current_boundary_value = convert(datetime,prv.value)
			from sys.partition_range_values prv
			join sys.partition_functions pf on pf.function_id = prv.function_id
			join sys.partition_schemes as ps on ps.function_id = pf.function_id
			where pf.name = 'pf_dba_datetime_quarterly' and ps.name = 'ps_dba_datetime_quarterly'
			order by prv.value desc;

			if(@current_boundary_value is null or @current_boundary_value < @current_time )
			begin
				print @tab+'Warning - @current_boundary_value is NULL or its previous to current time.';
				set @current_boundary_value = dateadd(hour,datediff(hour,convert(date,@current_time),@current_time),cast(convert(date,@current_time)as datetime));
				if (@current_step_name not like '%hourly') -- convert to 12:00 am time
					set @current_boundary_value = convert(date,@current_boundary_value)
			end
			
			if @verbose > 0
			begin
				print @tab+'@current_boundary_value = '+ convert(varchar,@current_boundary_value,120);
				print @tab+'@target_boundary_value = '+ convert(varchar,@target_boundary_value,120);
			end

			if (@current_boundary_value < @target_boundary_value)
			begin
				set @sql =	N'alter partition scheme ps_dba_datetime_quarterly next used [PRIMARY];'+@crlf+
							N'alter partition function pf_dba_datetime_quarterly() split range (@current_boundary_value);';
				set @params = N'@current_boundary_value datetime';

				if @verbose > 0
				begin
					print @tab+'Start loop if (@current_boundary_value < @target_boundary_value)..';
					print @crlf+'declare '+@params+';';
					print @sql+@crlf+@crlf;
				end
			end
			else
			begin
				if @verbose > 0
					print @tab+'No action required in this step.';
			end

			while (@current_boundary_value < @target_boundary_value)
			begin
				set @current_boundary_value = DATEADD(month, DATEDIFF(month, 0, DATEADD(MONTH,3,@current_boundary_value)), 0);
				if @verbose > 0
					print @tab+@tab+'@current_boundary_value = '+ convert(varchar,@current_boundary_value,120);				
				set @sql = '/* usp_partition_maintenance */ '+@sql;
				if @dry_run = 0
					exec sp_executesql @sql, @params, @current_boundary_value;
				else
					print @tab+@tab+'DRY RUN: add partition boundary..'
			end
		end try
		begin catch
			set @err_message = isnull(@err_message,'') + char(10) + 'Error in step ['+@current_step_name+'.'+char(10)+ ERROR_MESSAGE()+char(10);
		end catch
	end


	set @current_step_name = 'remove_partition_datetime2_hourly_old'
	if ( (@step is null or @step = @current_step_name) and exists (select * from sys.partition_functions pf where pf.name = 'pf_dba') )
	begin
		if @verbose > 0
			print @crlf+'@current_step_name = '+quotename(@current_step_name,'''');
		begin try			
			set @target_boundary_value = DATEADD(DAY,-@hourly_retention_days,GETDATE());

			if @verbose > 0
			begin
				print @tab+'@hourly_retention_days = '+ convert(varchar,@hourly_retention_days);
				print @tab+'@target_boundary_value = '+ convert(varchar,@target_boundary_value,120);
			end
			
			set @sql =	N'alter partition function pf_dba() merge range (@partition_boundary);';
			set @params = N'@partition_boundary datetime2';

			if @verbose > 0
			begin
				print @tab+'Get [pf_dba] partitions less than @target_boundary_value & open Cursor..';
				print @crlf+'declare '+@params+';';
				print @sql+@crlf+@crlf;
			end

			declare cur_boundaries cursor local fast_forward for
					select convert(datetime2,prv.value) as boundary_value
					from sys.partition_range_values prv
					join sys.partition_functions pf on pf.function_id = prv.function_id
					join sys.partition_schemes as ps on ps.function_id = pf.function_id
					where pf.name = 'pf_dba' and ps.name = 'ps_dba'
						and convert(datetime2,prv.value) < @target_boundary_value
					order by prv.value asc;

			open cur_boundaries;
			fetch next from cur_boundaries into @partition_boundary;
			while @@FETCH_STATUS = 0
			begin
				if @verbose > 0
					print @tab+@tab+'@partition_boundary = '+ convert(varchar,@partition_boundary,120);
				
				set @sql = '/* usp_partition_maintenance */ '+@sql;
				if @dry_run = 0
					exec sp_executesql @sql, @params, @partition_boundary;
				else
					print @tab+@tab+'DRY RUN: remove partition boundary..'

				fetch next from cur_boundaries into @partition_boundary;
			end
			close cur_boundaries
			deallocate cur_boundaries;
		end try
		begin catch
			set @err_message = isnull(@err_message,'') + char(10) + 'Error in step ['+@current_step_name+'.'+char(10)+ ERROR_MESSAGE()+char(10);
		end catch
	end


	set @current_step_name = 'remove_partition_datetime2_hourly'
	if ( (@step is null or @step = @current_step_name) and exists (select * from sys.partition_functions pf where pf.name = 'pf_dba_datetime2_hourly') )
	begin
		if @verbose > 0
			print @crlf+'@current_step_name = '+quotename(@current_step_name,'''');
		begin try			
			set @target_boundary_value = DATEADD(DAY,-@hourly_retention_days,GETDATE());

			if @verbose > 0
			begin
				print @tab+'@hourly_retention_days = '+ convert(varchar,@hourly_retention_days);
				print @tab+'@target_boundary_value = '+ convert(varchar,@target_boundary_value,120);
			end
			
			set @sql =	N'alter partition function pf_dba_datetime2_hourly() merge range (@partition_boundary);';
			set @params = N'@partition_boundary datetime2';

			if @verbose > 0
			begin
				print @tab+'Get [pf_dba_datetime2_hourly] partitions less than @target_boundary_value & open Cursor..';
				print @crlf+'declare '+@params+';';
				print @sql+@crlf+@crlf;
			end

			declare cur_boundaries cursor local fast_forward for
					select convert(datetime2,prv.value) as boundary_value
					from sys.partition_range_values prv
					join sys.partition_functions pf on pf.function_id = prv.function_id
					join sys.partition_schemes as ps on ps.function_id = pf.function_id
					where pf.name = 'pf_dba_datetime2_hourly' and ps.name = 'ps_dba_datetime2_hourly'
						and convert(datetime2,prv.value) < @target_boundary_value
					order by prv.value asc;

			open cur_boundaries;
			fetch next from cur_boundaries into @partition_boundary;
			while @@FETCH_STATUS = 0
			begin
				if @verbose > 0
					print @tab+@tab+'@partition_boundary = '+ convert(varchar,@partition_boundary,120);
				
				set @sql = '/* usp_partition_maintenance */ '+@sql;
				if @dry_run = 0
					exec sp_executesql @sql, @params, @partition_boundary;
				else
					print @tab+@tab+'DRY RUN: remove partition boundary..'

				fetch next from cur_boundaries into @partition_boundary;
			end
			close cur_boundaries
			deallocate cur_boundaries;
		end try
		begin catch
			set @err_message = isnull(@err_message,'') + char(10) + 'Error in step ['+@current_step_name+'.'+char(10)+ ERROR_MESSAGE()+char(10);
		end catch
	end


	set @current_step_name = 'remove_partition_datetime2_daily'
	if ( (@step is null or @step = @current_step_name) and exists (select * from sys.partition_functions pf where pf.name = 'pf_dba_datetime2_daily') )
	begin
		if @verbose > 0
			print @crlf+'@current_step_name = '+quotename(@current_step_name,'''');
		begin try			
			set @target_boundary_value = DATEADD(DAY,-@daily_retention_days,GETDATE());

			if @verbose > 0
			begin
				print @tab+'@daily_retention_days = '+ convert(varchar,@daily_retention_days);
				print @tab+'@target_boundary_value = '+ convert(varchar,@target_boundary_value,120);
			end
			
			set @sql =	N'alter partition function pf_dba_datetime2_daily() merge range (@partition_boundary);';
			set @params = N'@partition_boundary datetime2';

			if @verbose > 0
			begin
				print @tab+'Get [pf_dba_datetime2_daily] partitions less than @target_boundary_value & open Cursor..';
				print @crlf+'declare '+@params+';';
				print @sql+@crlf+@crlf;
			end

			declare cur_boundaries cursor local fast_forward for
					select convert(datetime2,prv.value) as boundary_value
					from sys.partition_range_values prv
					join sys.partition_functions pf on pf.function_id = prv.function_id
					join sys.partition_schemes as ps on ps.function_id = pf.function_id
					where pf.name = 'pf_dba_datetime2_daily' and ps.name = 'ps_dba_datetime2_daily'
						and convert(datetime2,prv.value) < @target_boundary_value
					order by prv.value asc;

			open cur_boundaries;
			fetch next from cur_boundaries into @partition_boundary;
			while @@FETCH_STATUS = 0
			begin
				if @verbose > 0
					print @tab+@tab+'@partition_boundary = '+ convert(varchar,@partition_boundary,120);
				
				set @sql = '/* usp_partition_maintenance */ '+@sql;
				if @dry_run = 0
					exec sp_executesql @sql, @params, @partition_boundary;
				else
					print @tab+@tab+'DRY RUN: remove partition boundary..'

				fetch next from cur_boundaries into @partition_boundary;
			end
			close cur_boundaries
			deallocate cur_boundaries;
		end try
		begin catch
			set @err_message = isnull(@err_message,'') + char(10) + 'Error in step ['+@current_step_name+'.'+char(10)+ ERROR_MESSAGE()+char(10);
		end catch
	end


	set @current_step_name = 'remove_partition_datetime2_monthly'
	if ( (@step is null or @step = @current_step_name) and exists (select * from sys.partition_functions pf where pf.name = 'pf_dba_datetime2_monthly') )
	begin
		if @verbose > 0
			print @crlf+'@current_step_name = '+quotename(@current_step_name,'''');
		begin try			
			set @target_boundary_value = DATEADD(DAY,-@monthly_retention_days,GETDATE());

			if @verbose > 0
			begin
				print @tab+'@monthly_retention_days = '+ convert(varchar,@monthly_retention_days);
				print @tab+'@target_boundary_value = '+ convert(varchar,@target_boundary_value,120);
			end
			
			set @sql =	N'alter partition function pf_dba_datetime2_monthly() merge range (@partition_boundary);';
			set @params = N'@partition_boundary datetime2';

			if @verbose > 0
			begin
				print @tab+'Get [pf_dba_datetime2_monthly] partitions less than @target_boundary_value & open Cursor..';
				print @crlf+'declare '+@params+';';
				print @sql+@crlf+@crlf;
			end

			declare cur_boundaries cursor local fast_forward for
					select convert(datetime2,prv.value) as boundary_value
					from sys.partition_range_values prv
					join sys.partition_functions pf on pf.function_id = prv.function_id
					join sys.partition_schemes as ps on ps.function_id = pf.function_id
					where pf.name = 'pf_dba_datetime2_monthly' and ps.name = 'ps_dba_datetime2_monthly'
						and convert(datetime2,prv.value) < @target_boundary_value
					order by prv.value asc;

			open cur_boundaries;
			fetch next from cur_boundaries into @partition_boundary;
			while @@FETCH_STATUS = 0
			begin
				if @verbose > 0
					print @tab+@tab+'@partition_boundary = '+ convert(varchar,@partition_boundary,120);
				
				set @sql = '/* usp_partition_maintenance */ '+@sql;
				if @dry_run = 0
					exec sp_executesql @sql, @params, @partition_boundary;
				else
					print @tab+@tab+'DRY RUN: remove partition boundary..'

				fetch next from cur_boundaries into @partition_boundary;
			end
			close cur_boundaries
			deallocate cur_boundaries;
		end try
		begin catch
			set @err_message = isnull(@err_message,'') + char(10) + 'Error in step ['+@current_step_name+'.'+char(10)+ ERROR_MESSAGE()+char(10);
		end catch
	end


	set @current_step_name = 'remove_partition_datetime2_quarterly'
	if ( (@step is null or @step = @current_step_name) and exists (select * from sys.partition_functions pf where pf.name = 'pf_dba_datetime2_quarterly') )
	begin
		if @verbose > 0
			print @crlf+'@current_step_name = '+quotename(@current_step_name,'''');
		begin try			
			set @target_boundary_value = DATEADD(DAY,-@quarterly_retention_days,GETDATE());

			if @verbose > 0
			begin
				print @tab+'@quarterly_retention_days = '+ convert(varchar,@quarterly_retention_days);
				print @tab+'@target_boundary_value = '+ convert(varchar,@target_boundary_value,120);
			end
			
			set @sql =	N'alter partition function pf_dba_datetime2_quarterly() merge range (@partition_boundary);';
			set @params = N'@partition_boundary datetime2';

			if @verbose > 0
			begin
				print @tab+'Get [pf_dba_datetime2_quarterly] partitions less than @target_boundary_value & open Cursor..';
				print @crlf+'declare '+@params+';';
				print @sql+@crlf+@crlf;
			end

			declare cur_boundaries cursor local fast_forward for
					select convert(datetime2,prv.value) as boundary_value
					from sys.partition_range_values prv
					join sys.partition_functions pf on pf.function_id = prv.function_id
					join sys.partition_schemes as ps on ps.function_id = pf.function_id
					where pf.name = 'pf_dba_datetime2_quarterly' and ps.name = 'ps_dba_datetime2_quarterly'
						and convert(datetime2,prv.value) < @target_boundary_value
					order by prv.value asc;

			open cur_boundaries;
			fetch next from cur_boundaries into @partition_boundary;
			while @@FETCH_STATUS = 0
			begin
				if @verbose > 0
					print @tab+@tab+'@partition_boundary = '+ convert(varchar,@partition_boundary,120);
				
				set @sql = '/* usp_partition_maintenance */ '+@sql;
				if @dry_run = 0
					exec sp_executesql @sql, @params, @partition_boundary;
				else
					print @tab+@tab+'DRY RUN: remove partition boundary..'

				fetch next from cur_boundaries into @partition_boundary;
			end
			close cur_boundaries
			deallocate cur_boundaries;
		end try
		begin catch
			set @err_message = isnull(@err_message,'') + char(10) + 'Error in step ['+@current_step_name+'.'+char(10)+ ERROR_MESSAGE()+char(10);
		end catch
	end


	set @current_step_name = 'remove_partition_datetime_hourly_old'
	if ( (@step is null or @step = @current_step_name) and exists (select * from sys.partition_functions pf where pf.name = 'pf_dba_datetime') )
	begin
		if @verbose > 0
			print @crlf+'@current_step_name = '+quotename(@current_step_name,'''');
		begin try			
			set @target_boundary_value = DATEADD(DAY,-@hourly_retention_days,GETDATE());

			if @verbose > 0
			begin
				print @tab+'@hourly_retention_days = '+ convert(varchar,@hourly_retention_days);
				print @tab+'@target_boundary_value = '+ convert(varchar,@target_boundary_value,120);
			end
			
			set @sql =	N'alter partition function pf_dba_datetime() merge range (@partition_boundary);';
			set @params = N'@partition_boundary datetime2';

			if @verbose > 0
			begin
				print @tab+'Get [pf_dba_datetime] partitions less than @target_boundary_value & open Cursor..';
				print @crlf+'declare '+@params+';';
				print @sql+@crlf+@crlf;
			end

			declare cur_boundaries cursor local fast_forward for
					select convert(datetime2,prv.value) as boundary_value
					from sys.partition_range_values prv
					join sys.partition_functions pf on pf.function_id = prv.function_id
					join sys.partition_schemes as ps on ps.function_id = pf.function_id
					where pf.name = 'pf_dba_datetime' and ps.name = 'ps_dba_datetime'
						and convert(datetime2,prv.value) < @target_boundary_value
					order by prv.value asc;

			open cur_boundaries;
			fetch next from cur_boundaries into @partition_boundary;
			while @@FETCH_STATUS = 0
			begin
				if @verbose > 0
					print @tab+@tab+'@partition_boundary = '+ convert(varchar,@partition_boundary,120);
				
				set @sql = '/* usp_partition_maintenance */ '+@sql;
				if @dry_run = 0
					exec sp_executesql @sql, @params, @partition_boundary;
				else
					print @tab+@tab+'DRY RUN: remove partition boundary..'

				fetch next from cur_boundaries into @partition_boundary;
			end
			close cur_boundaries
			deallocate cur_boundaries;
		end try
		begin catch
			set @err_message = isnull(@err_message,'') + char(10) + 'Error in step ['+@current_step_name+'.'+char(10)+ ERROR_MESSAGE()+char(10);
		end catch
	end


	set @current_step_name = 'remove_partition_datetime_hourly'
	if ( (@step is null or @step = @current_step_name) and exists (select * from sys.partition_functions pf where pf.name = 'pf_dba_datetime_hourly') )
	begin
		if @verbose > 0
			print @crlf+'@current_step_name = '+quotename(@current_step_name,'''');
		begin try			
			set @target_boundary_value = DATEADD(DAY,-@hourly_retention_days,GETDATE());

			if @verbose > 0
			begin
				print @tab+'@hourly_retention_days = '+ convert(varchar,@hourly_retention_days);
				print @tab+'@target_boundary_value = '+ convert(varchar,@target_boundary_value,120);
			end
			
			set @sql =	N'alter partition function pf_dba_datetime_hourly() merge range (@partition_boundary);';
			set @params = N'@partition_boundary datetime2';

			if @verbose > 0
			begin
				print @tab+'Get [pf_dba_datetime_hourly] partitions less than @target_boundary_value & open Cursor..';
				print @crlf+'declare '+@params+';';
				print @sql+@crlf+@crlf;
			end

			declare cur_boundaries cursor local fast_forward for
					select convert(datetime2,prv.value) as boundary_value
					from sys.partition_range_values prv
					join sys.partition_functions pf on pf.function_id = prv.function_id
					join sys.partition_schemes as ps on ps.function_id = pf.function_id
					where pf.name = 'pf_dba_datetime_hourly' and ps.name = 'ps_dba_datetime_hourly'
						and convert(datetime2,prv.value) < @target_boundary_value
					order by prv.value asc;

			open cur_boundaries;
			fetch next from cur_boundaries into @partition_boundary;
			while @@FETCH_STATUS = 0
			begin
				if @verbose > 0
					print @tab+@tab+'@partition_boundary = '+ convert(varchar,@partition_boundary,120);
				
				set @sql = '/* usp_partition_maintenance */ '+@sql;
				if @dry_run = 0
					exec sp_executesql @sql, @params, @partition_boundary;
				else
					print @tab+@tab+'DRY RUN: remove partition boundary..'

				fetch next from cur_boundaries into @partition_boundary;
			end
			close cur_boundaries
			deallocate cur_boundaries;
		end try
		begin catch
			set @err_message = isnull(@err_message,'') + char(10) + 'Error in step ['+@current_step_name+'.'+char(10)+ ERROR_MESSAGE()+char(10);
		end catch
	end


	set @current_step_name = 'remove_partition_datetime_daily'
	if ( (@step is null or @step = @current_step_name) and exists (select * from sys.partition_functions pf where pf.name = 'pf_dba_datetime_daily') )
	begin
		if @verbose > 0
			print @crlf+'@current_step_name = '+quotename(@current_step_name,'''');
		begin try			
			set @target_boundary_value = DATEADD(DAY,-@daily_retention_days,GETDATE());

			if @verbose > 0
			begin
				print @tab+'@daily_retention_days = '+ convert(varchar,@daily_retention_days);
				print @tab+'@target_boundary_value = '+ convert(varchar,@target_boundary_value,120);
			end
			
			set @sql =	N'alter partition function pf_dba_datetime_daily() merge range (@partition_boundary);';
			set @params = N'@partition_boundary datetime';

			if @verbose > 0
			begin
				print @tab+'Get [pf_dba_datetime_daily] partitions less than @target_boundary_value & open Cursor..';
				print @crlf+'declare '+@params+';';
				print @sql+@crlf+@crlf;
			end

			declare cur_boundaries cursor local fast_forward for
					select convert(datetime2,prv.value) as boundary_value
					from sys.partition_range_values prv
					join sys.partition_functions pf on pf.function_id = prv.function_id
					join sys.partition_schemes as ps on ps.function_id = pf.function_id
					where pf.name = 'pf_dba_datetime_daily' and ps.name = 'ps_dba_datetime_daily'
						and convert(datetime2,prv.value) < @target_boundary_value
					order by prv.value asc;

			open cur_boundaries;
			fetch next from cur_boundaries into @partition_boundary;
			while @@FETCH_STATUS = 0
			begin
				if @verbose > 0
					print @tab+@tab+'@partition_boundary = '+ convert(varchar,@partition_boundary,120);
				
				set @sql = '/* usp_partition_maintenance */ '+@sql;
				if @dry_run = 0
					exec sp_executesql @sql, @params, @partition_boundary;
				else
					print @tab+@tab+'DRY RUN: remove partition boundary..'

				fetch next from cur_boundaries into @partition_boundary;
			end
			close cur_boundaries
			deallocate cur_boundaries;
		end try
		begin catch
			set @err_message = isnull(@err_message,'') + char(10) + 'Error in step ['+@current_step_name+'.'+char(10)+ ERROR_MESSAGE()+char(10);
		end catch
	end


	set @current_step_name = 'remove_partition_datetime_monthly'
	if ( (@step is null or @step = @current_step_name) and exists (select * from sys.partition_functions pf where pf.name = 'pf_dba_datetime_monthly') )
	begin
		if @verbose > 0
			print @crlf+'@current_step_name = '+quotename(@current_step_name,'''');
		begin try			
			set @target_boundary_value = DATEADD(DAY,-@monthly_retention_days,GETDATE());

			if @verbose > 0
			begin
				print @tab+'@monthly_retention_days = '+ convert(varchar,@monthly_retention_days);
				print @tab+'@target_boundary_value = '+ convert(varchar,@target_boundary_value,120);
			end
			
			set @sql =	N'alter partition function pf_dba_datetime_monthly() merge range (@partition_boundary);';
			set @params = N'@partition_boundary datetime2';

			if @verbose > 0
			begin
				print @tab+'Get [pf_dba_datetime_monthly] partitions less than @target_boundary_value & open Cursor..';
				print @crlf+'declare '+@params+';';
				print @sql+@crlf+@crlf;
			end

			declare cur_boundaries cursor local fast_forward for
					select convert(datetime2,prv.value) as boundary_value
					from sys.partition_range_values prv
					join sys.partition_functions pf on pf.function_id = prv.function_id
					join sys.partition_schemes as ps on ps.function_id = pf.function_id
					where pf.name = 'pf_dba_datetime_monthly' and ps.name = 'ps_dba_datetime_monthly'
						and convert(datetime2,prv.value) < @target_boundary_value
					order by prv.value asc;

			open cur_boundaries;
			fetch next from cur_boundaries into @partition_boundary;
			while @@FETCH_STATUS = 0
			begin
				if @verbose > 0
					print @tab+@tab+'@partition_boundary = '+ convert(varchar,@partition_boundary,120);
				
				set @sql = '/* usp_partition_maintenance */ '+@sql;
				if @dry_run = 0
					exec sp_executesql @sql, @params, @partition_boundary;
				else
					print @tab+@tab+'DRY RUN: remove partition boundary..'

				fetch next from cur_boundaries into @partition_boundary;
			end
			close cur_boundaries
			deallocate cur_boundaries;
		end try
		begin catch
			set @err_message = isnull(@err_message,'') + char(10) + 'Error in step ['+@current_step_name+'.'+char(10)+ ERROR_MESSAGE()+char(10);
		end catch
	end


	set @current_step_name = 'remove_partition_datetime_quarterly'
	if ( (@step is null or @step = @current_step_name) and exists (select * from sys.partition_functions pf where pf.name = 'pf_dba_datetime_quarterly') )
	begin
		if @verbose > 0
			print @crlf+'@current_step_name = '+quotename(@current_step_name,'''');
		begin try			
			set @target_boundary_value = DATEADD(DAY,-@quarterly_retention_days,GETDATE());

			if @verbose > 0
			begin
				print @tab+'@quarterly_retention_days = '+ convert(varchar,@quarterly_retention_days);
				print @tab+'@target_boundary_value = '+ convert(varchar,@target_boundary_value,120);
			end
			
			set @sql =	N'alter partition function pf_dba_datetime_quarterly() merge range (@partition_boundary);';
			set @params = N'@partition_boundary datetime2';

			if @verbose > 0
			begin
				print @tab+'Get [pf_dba_datetime_quarterly] partitions less than @target_boundary_value & open Cursor..';
				print @crlf+'declare '+@params+';';
				print @sql+@crlf+@crlf;
			end

			declare cur_boundaries cursor local fast_forward for
					select convert(datetime2,prv.value) as boundary_value
					from sys.partition_range_values prv
					join sys.partition_functions pf on pf.function_id = prv.function_id
					join sys.partition_schemes as ps on ps.function_id = pf.function_id
					where pf.name = 'pf_dba_datetime_quarterly' and ps.name = 'ps_dba_datetime_quarterly'
						and convert(datetime2,prv.value) < @target_boundary_value
					order by prv.value asc;

			open cur_boundaries;
			fetch next from cur_boundaries into @partition_boundary;
			while @@FETCH_STATUS = 0
			begin
				if @verbose > 0
					print @tab+@tab+'@partition_boundary = '+ convert(varchar,@partition_boundary,120);
				
				set @sql = '/* usp_partition_maintenance */ '+@sql;
				if @dry_run = 0
					exec sp_executesql @sql, @params, @partition_boundary;
				else
					print @tab+@tab+'DRY RUN: remove partition boundary..'

				fetch next from cur_boundaries into @partition_boundary;
			end
			close cur_boundaries
			deallocate cur_boundaries;
		end try
		begin catch
			set @err_message = isnull(@err_message,'') + char(10) + 'Error in step ['+@current_step_name+'.'+char(10)+ ERROR_MESSAGE()+char(10);
		end catch
	end


	if @err_message is not null
    raiserror (@err_message, 20, -1) with log;
END
GO
