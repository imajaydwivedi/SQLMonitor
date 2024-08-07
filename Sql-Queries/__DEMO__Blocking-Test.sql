use tempdb
go

create table dbo.BlockingTest (name varchar(50), city varchar(100))
go

declare @loop int = 10; -- consider it days
declare @counter int = 0;

begin tran
	insert dbo.BlockingTest
	select 'Ajay', 'Rewa'

	while @counter <= @loop
	begin
		waitfor delay '23:00:00'
		set @counter += 1;
	end
rollback tran

/*
use tempdb
go

select * from dbo.BlockingTest
*/

