IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

-- Drop Existing PK
USE [DBA];
IF OBJECT_ID('dbo.WhoIsActive') IS NOT NULL
BEGIN
	IF NOT EXISTS (select * from sys.indexes where [object_id] = OBJECT_ID('dbo.WhoIsActive') and data_space_id > 1)
		IF EXISTS (select * from sys.indexes where [object_id] = OBJECT_ID('dbo.WhoIsActive') and name = 'ci_WhoIsActive')
			DROP INDEX ci_WhoIsActive ON dbo.WhoIsActive;
	ELSE
		SELECT '[dbo].[WhoIsActive] table already partitioned.';
END
ELSE
	SELECT '[dbo].[WhoIsActive] table not found';
GO

-- Create PK with Partitioning
USE [DBA];
IF OBJECT_ID('dbo.WhoIsActive') IS NOT NULL AND NOT EXISTS (select * from sys.indexes where [object_id] = OBJECT_ID('dbo.WhoIsActive') and type_desc = 'CLUSTERED')
	CREATE CLUSTERED INDEX ci_WhoIsActive ON dbo.WhoIsActive ( [collection_time] ASC )
		ON [ps_dba_datetime_daily] (collection_time);
GO
