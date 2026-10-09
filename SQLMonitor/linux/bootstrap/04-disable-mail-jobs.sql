/*
	Disables the two inventory jobs that need Database Mail, which the test rig
	does not have.

	Both jobs ship with the placeholder recipient baked into the job command:

	    EXEC dbo.usp_GetAllServerDashboardMail @recipients = 'dba_team@gmail.com', ...

	and both procs deliberately refuse that address:

	    IF (@recipients IS NULL OR @recipients = 'dba_team@gmail.com') AND @verbose = 0
	        raiserror ('@recipients is mandatory parameter', 20, -1) with log;

	A severity-20 raiserror terminates the connection, so the job reports
	"Failed" every run. On a real deployment Install-SQLMonitor.ps1 substitutes
	the real address; here there is no mail profile to send to at all, and
	Database Mail is not supported on SQL Server Express.

	Disabling them keeps `make verify` honest: everything still enabled is
	expected to succeed.
*/

USE [msdb];
GO
SET NOCOUNT ON;
GO

DECLARE @_mail_jobs table (job_name nvarchar(255) PRIMARY KEY);
INSERT INTO @_mail_jobs VALUES (N'(dba) Get-AllServerDashboardMail'), (N'(dba) Send Login Expiry EMails');

DECLARE @_name nvarchar(255);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT job_name FROM @_mail_jobs;
OPEN c; FETCH NEXT FROM c INTO @_name;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF EXISTS (SELECT * FROM msdb.dbo.sysjobs_view WHERE name = @_name AND enabled = 1)
    BEGIN
        PRINT 'Disabling ' + QUOTENAME(@_name) + ' - needs Database Mail, which the test rig has not configured.';
        EXEC msdb.dbo.sp_update_job @job_name = @_name, @enabled = 0;
    END
    FETCH NEXT FROM c INTO @_name;
END
CLOSE c; DEALLOCATE c;
GO
