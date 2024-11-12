USE tempdb
GO

-- Add partition boundaries in Future, and merge older than threshold
exec dbo.usp_partition_maintenance @daily_retention_days = 1460;
GO

-- Add partition boundaries in Past
declare @start_date datetime2 = '2020-01-01';
declare @end_date datetime2 = '2023-12-18';
declare @counter_date datetime2 = @start_date;
declare @crlf nchar(2) = char(10)+char(13);
declare @sql nvarchar(max);
declare @params nvarchar(max);

set @params = N'@current_boundary_value datetime2';
set @sql =	N'alter partition scheme ps_dba_datetime2_daily next used [PRIMARY];'+@crlf+
			N'alter partition function pf_dba_datetime2_daily() split range (@current_boundary_value);';

while (@counter_date < @end_date)
begin
	print convert(varchar,@counter_date);
	
	exec sp_executesql @sql, @params, @current_boundary_value = @counter_date;
	
	set @counter_date = dateadd(day,1, @counter_date);
end
go
