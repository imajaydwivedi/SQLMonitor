use DBA
go

IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

-- Check all Logins
select server_ip, server_name, [user_name], is_sql_user, is_rdp_user, password_hash, salt, 
created_date, created_by, updated_date, updated_by, delegate_login_01, delegate_login_02, remarks 
from dbo.credential_manager
go


/* Insert Credentials */
exec dbo.usp_add_credential
			@server_ip = '*',
			--@server_name = '<server_name>',
			@user_name = 'sa',
			@password_string = 'SomeStringPassword',
			--@passphrase_string = '421',
			--@is_sql_user = 1,
			--@is_rdp_user = 1,
			--@save_passphrase = 1,
			@remarks = 'sa Credential';
go

/* Fetch Credentials */
declare @password varchar(256);
exec dbo.usp_get_credential 
		@server_ip = '*',
		@user_name = 'Lab\SQLServices',
		@password = @password output;
select @password as [@password];
go


/* Remove Credential */
exec dbo.usp_delete_credential
	@server_ip = '*',
	@user_name = 'Test',
	@password = 'SomeStringPassword'
go


/* Update Credential */
exec dbo.usp_update_credential
	@server_ip = '*',
	@user_name = 'Test',
	@new_password_string = 'SomeStringPassword',
	@confirm_forgot_password = 1
go


/* Get All Credential for Specific Server */
declare @server_ip char(25) = '*'
select server_ip, server_name, [user_name], is_sql_user, is_rdp_user, 
		password_hash, [password] = cast(DecryptByPassPhrase(cast(salt as varchar(255)),password_hash ,1, isnull(server_ip,@server_ip)) as varchar(255)),
		salt, salt_raw = cast(salt as varchar(255)),	created_date, created_by, updated_date, updated_by, 
		delegate_login_01, delegate_login_02, remarks 
from dbo.credential_manager
where @server_ip is null or server_ip = @server_ip
go


/* Get All Credentials */
select server_ip, server_name, [user_name], is_sql_user, is_rdp_user, 
		password_hash, [password] = cast(DecryptByPassPhrase(cast(salt as varchar(255)),password_hash ,1, server_ip) as varchar(500)),
		salt, salt_raw = cast(salt as varchar(255)),	created_date, created_by, updated_date, updated_by, 
		delegate_login_01, delegate_login_02, remarks 
from dbo.credential_manager cm
where cm.server_ip = 'SomeServer'
go