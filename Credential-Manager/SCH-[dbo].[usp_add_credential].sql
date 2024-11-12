use DBA
go

IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

--drop procedure dbo.usp_add_credential
create or alter procedure dbo.usp_add_credential
	@server_ip char(15), 
	@server_name varchar(125) = null, 
	@user_name varchar(125), 
	@password_string varchar(256),
	@passphrase_string varchar(125) = null,
	@is_sql_user bit = 0,
	@is_rdp_user bit = 0,
	@save_passphrase bit = 1,
	@delegate_login_01 varchar(125) = null,
	@delegate_login_02 varchar(125) = null,
	@remarks nvarchar(2000) = null
with  encryption
as
begin
	if @save_passphrase = 0 and @passphrase_string is null
		throw 50000, 'Kindly provide passphrase_string.', 1;
	else
	begin
		-- If salt is null, assign one randomly
		if @passphrase_string is null
			set @passphrase_string = convert(varchar(125),100000+abs(checksum(NEWID()))%100000);
	end
	
	insert dbo.credential_manager
	(server_ip, server_name, [user_name], password_hash, salt, is_sql_user, is_rdp_user, delegate_login_01, delegate_login_02, remarks)
	select server_ip = @server_ip, server_name = @server_name, [user_name] = @user_name,
			password_hash = EncryptByPassPhrase(@passphrase_string, @password_string, 1, @server_ip),
			salt = case when @save_passphrase = 0 then null else convert(varbinary(125),@passphrase_string) end,
			is_sql_user = @is_sql_user, is_rdp_user = @is_rdp_user, @delegate_login_01, @delegate_login_02, remarks = @remarks;
	

	if @@ROWCOUNT > 0
		select 'Credential Saved.' as [result];
end
go