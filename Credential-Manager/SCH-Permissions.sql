--	Minimum permissions required to run sp_Blitz
	-- https://dba.stackexchange.com/a/188193/98923
--	Certificate Signing Stored Procedures in Multiple Databases
	-- https://www.sqlskills.com/blogs/jonathan/certificate-signing-stored-procedures-in-multiple-databases/

USE master
GO

CREATE CERTIFICATE credential_manager_cert ENCRYPTION BY PASSWORD = 'dbo.credential_manager' -- Save this password
	WITH EXPIRY_DATE = '2099-01-01', SUBJECT = 'Credential Manager'
GO

SELECT [LogPath] = SERVERPROPERTY('ErrorLogFileName'); -- Use this path to save certificate

BACKUP CERTIFICATE credential_manager_cert TO 
	FILE = 'D:\MSSQL15.MSSQLSERVER\MSSQL\Log\credential_manager_cert.cer'
	WITH PRIVATE KEY (
			FILE = 'D:\MSSQL15.MSSQLSERVER\MSSQL\Log\credential_manager_cert_WithKey.pvk', 
			ENCRYPTION BY PASSWORD = 'dbo.credential_manager', DECRYPTION BY PASSWORD = 'dbo.credential_manager'
		);
GO

/*
DECLARE @cmd NVARCHAR(MAX) = 'xp_cmdshell ''del "D:\MSSQL15.MSSQLSERVER\MSSQL\Log\credential_manager_cert.cer"'''; EXEC (@cmd);
SET @cmd = 'xp_cmdshell ''del "C:\temp\CodeSigningCertificate_WithKey.pvk"'''; EXEC (@cmd);
*/

CREATE LOGIN credential_manager_login FROM CERTIFICATE credential_manager_cert;
GO

GRANT AUTHENTICATE SERVER TO credential_manager_login;
EXEC master..sp_addsrvrolemember @loginame = N'credential_manager_login', @rolename = N'sysadmin';
GO

USE DBA
GO

DENY SELECT ON credential_manager TO PUBLIC; -- Stop direct access to table for Non-Sysadmin users
go

CREATE CERTIFICATE credential_manager_cert FROM 
	FILE = 'D:\MSSQL15.MSSQLSERVER\MSSQL\Log\credential_manager_cert.cer'
	WITH PRIVATE KEY (FILE = 'D:\MSSQL15.MSSQLSERVER\MSSQL\Log\credential_manager_cert_WithKey.pvk',
					  ENCRYPTION BY PASSWORD = 'dbo.credential_manager',
					  DECRYPTION BY PASSWORD = 'dbo.credential_manager'
					  );
GO

CREATE USER credential_manager_login FROM CERTIFICATE credential_manager_cert;
GO
EXEC sp_addrolemember N'db_owner', N'credential_manager_login'
GO

-- Start providing permissions
USE master
go

ADD SIGNATURE TO [dbo].[sp_WhoIsActive] BY CERTIFICATE credential_manager_cert WITH PASSWORD = 'dbo.credential_manager'
GO
GRANT EXECUTE ON OBJECT::[dbo].[sp_WhoIsActive] TO [public]
GO

USE DBA
GO
GRANT CONNECT TO [public]
GO
GRANT CONNECT TO [guest]
GO

ADD SIGNATURE TO [dbo].[usp_get_credential] BY CERTIFICATE credential_manager_cert 
	WITH PASSWORD = 'dbo.credential_manager'
GO
GRANT EXECUTE ON OBJECT::[dbo].[usp_get_credential] TO [public]
GO

ADD SIGNATURE TO [dbo].[usp_add_credential] BY CERTIFICATE credential_manager_cert 
	WITH PASSWORD = 'dbo.credential_manager'
GO
GRANT EXECUTE ON OBJECT::[dbo].[usp_add_credential] TO [public]
GO

ADD SIGNATURE TO [dbo].[usp_delete_credential] BY CERTIFICATE credential_manager_cert 
	WITH PASSWORD = 'dbo.credential_manager'
GO
GRANT EXECUTE ON OBJECT::[dbo].[usp_delete_credential] TO [public]
GO

ADD SIGNATURE TO [dbo].[usp_update_credential] BY CERTIFICATE credential_manager_cert 
	WITH PASSWORD = 'dbo.credential_manager'
GO
GRANT EXECUTE ON OBJECT::[dbo].[usp_update_credential] TO [public]
GO

/*
SELECT [Object Name] = object_name(cp.major_id),
       [Object Type] = obj.type_desc,   
       [Cert/Key] = coalesce(c.name, a.name),
       cp.crypt_type_desc
FROM   sys.crypt_properties cp
INNER JOIN sys.objects obj        ON obj.object_id = cp.major_id
LEFT   JOIN sys.certificates c    ON c.thumbprint = cp.thumbprint
LEFT   JOIN sys.asymmetric_keys a ON a.thumbprint = cp.thumbprint
ORDER BY [Object Name] ASC

*/

/*	Cleanup 
use master;
drop login credential_manager_login;
drop user credential_manager_login;
drop signature from [dbo].[sp_WhoIsActive] by certificate credential_manager_cert;
drop certificate credential_manager_cert;

use DBA;
drop user credential_manager_login;
drop certificate credential_manager_cert;
*/
