SELECT name, CASE WHEN value_in_use=1 THEN 'ENABLED'
WHEN value_in_use=0 THEN 'DISABLED'
END AS [status]
FROM sys.configurations
WHERE name='default trace enabled'
go


SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO

CREATE TABLE [dbo].[SQLConfig_Changes](
[TextData] [varchar](500) NULL,
[HostName] [varchar](155) NULL,
[ApplicationName] [varchar](255) NULL,
[DatabaseName] [varchar](155) NULL,
[LoginName] [varchar](155) NULL,
[SPID] [int] NULL,
[StartTime] [datetime] NULL,
[EventSequence] [int] NULL
) ON [PRIMARY]
GO

SET ANSI_PADDING OFF
GO


