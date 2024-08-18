IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

use DBA
go

create table dbo.sm_error
( 	collection_time_utc datetime2 not null default getutcdate(), 
	server varchar(500) null,
    cmdlet varchar(125) not null, 
	command varchar(1000) null, 
	error varchar(500) not null, 
    remark varchar(1000) null
)
go


