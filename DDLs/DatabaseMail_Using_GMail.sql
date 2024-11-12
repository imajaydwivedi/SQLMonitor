--	http://ajaydwivedi.com/2017/09/errorfix-database-mails-using-gmail-getting-unsent-items/
select @@SERVERNAME
use master
go
sp_configure 'show advanced options',1
go
reconfigure with override
go
sp_configure 'Database Mail XPs',1
--go
--sp_configure 'SQL Mail XPs',0
go
reconfigure
go

--#################################################################################################
-- BEGIN Mail Settings admin
--#################################################################################################
IF NOT EXISTS(SELECT * FROM msdb.dbo.sysmail_profile WHERE  name = 'gmail') 
BEGIN
--CREATE Profile [admin]
EXECUTE msdb.dbo.sysmail_add_profile_sp
    @profile_name = 'gmail',
    @description  = 'Profile for sending Automated DBA Notifications using GMail';
END --IF EXISTS profile
  
IF NOT EXISTS(SELECT * FROM msdb.dbo.sysmail_account WHERE  name = 'SQLGMailAgent')
BEGIN
--CREATE Account [SQLAgent]
EXECUTE msdb.dbo.sysmail_add_account_sp
@account_name            = 'SQLGMailAgent',
@email_address           = 'sqlagentservice@gmail.com',
@display_name            = 'SQLAlerts',
@replyto_address         = 'sqlagentservice@gmail.com',
@description             = '',
@mailserver_name         = 'smtp.gmail.com',
@mailserver_type         = 'SMTP',
@port                    = 587,
@username                = 'sqlagentservice@gmail.com',
@password                = 'asdfasdfasrewdfvzxgaw', -- Generate Latest Password
@use_default_credentials =  0 ,
@enable_ssl              =  1 ;
END --IF EXISTS  account

IF NOT EXISTS(SELECT *
            FROM msdb.dbo.sysmail_profileaccount pa
            INNER JOIN msdb.dbo.sysmail_profile p ON pa.profile_id = p.profile_id
            INNER JOIN msdb.dbo.sysmail_account a ON pa.account_id = a.account_id  
            WHERE p.name = 'admin'
            AND a.name = 'SQLAgent') 
BEGIN
-- Associate Account [SQLAgent] to Profile [admin]
EXECUTE msdb.dbo.sysmail_add_profileaccount_sp
    @profile_name = 'gmail',
    @account_name = 'SQLGMailAgent',
    @sequence_number = 1 ;
END --IF EXISTS associate accounts to profiles

-- Set the mail profile to be default global
EXECUTE msdb.dbo.sysmail_add_principalprofile_sp  
			@profile_name = 'gmail',  
			@principal_name = 'public',
			@is_default = 1 ;
--#################################################################################################
-- Drop Settings For admin

DECLARE @_Subject VARCHAR(200), @_Body VARCHAR(2000);
SET @_Subject = 'Test Mail from latop Server '+@@SERVERNAME ;
SET @_Body = 'Hi Ajay,

This is a test mail from latop Server '+@@SERVERNAME+'. Please ignore it.

Regards,
SQL Server Agent
';

EXEC msdb.dbo.sp_send_dbmail  
    --@profile_name = 'gmail',  
    @recipients = 'ajay.dwivedi2007@gmail.com',  
    @body = @_Body,  
    @subject = @_Subject ;  
	

select * from msdb.dbo.sysmail_sentitems 
select * from msdb.dbo.sysmail_unsentitems 
select * from msdb.dbo.sysmail_faileditems 

SELECT items.subject,
    items.last_mod_date
    ,l.description FROM msdb.dbo.sysmail_faileditems as items
INNER JOIN msdb.dbo.sysmail_event_log AS l
    ON items.mailitem_id = l.mailitem_id
GO

/*
The mail could not be sent to the recipients because of the mail server failure. (Sending Mail using Account 1 (2016-11-13T22:29:31). Exception Message: Could not connect to mail server. (A connection attempt failed because the connected party did not properly respond after a period of time, or established connection failed because connected host has failed to respond 74.125.200.109:587).
)

The mail could not be sent to the recipients because of the mail server failure. (Sending Mail using Account 1 (2016-11-15T13:20:41). Exception Message: Could not connect to mail server. (A connection attempt failed because the connected party did not properly respond after a period of time, or established connection failed because connected host has failed to respond 74.125.200.108:587).
)
*/

SELECT p.name as profile_name, p.description as profile_description, a.name as mail_account, 
		a.email_address, a.display_name, a.replyto_address, s.servername, s.port, s.servername,
		pp.is_default
FROM msdb.dbo.sysmail_profile p 
JOIN msdb.dbo.sysmail_principalprofile pp ON pp.profile_id = p.profile_id AND pp.is_default = 1
JOIN msdb.dbo.sysmail_profileaccount pa ON p.profile_id = pa.profile_id 
JOIN msdb.dbo.sysmail_account a ON pa.account_id = a.account_id 
JOIN msdb.dbo.sysmail_server s ON a.account_id = s.account_id;
go

