use DBA
go

IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

--drop procedure dbo.usp_update_credential
create or alter procedure dbo.usp_update_credential
	@server_ip char(15) = null, 
	@server_name varchar(125) = null, 
	@user_name varchar(125), 
	@old_password_string varchar(256) = null,
	@new_password_string varchar(256) = null,
	@old_passphrase_string varchar(125) = null,
	@new_passphrase_string varchar(125) = null,
	@is_sql_user bit = null,
	@is_rdp_user bit = null,
	@save_passphrase bit = 1,
	@delegate_login_01 varchar(125) = null,
	@delegate_login_02 varchar(125) = null,
	@remarks nvarchar(2000) = null,
	@confirm_forgot_password bit = 0
with  encryption
as
begin
	set nocount on;
	if (@server_ip is null and @server_name is null)
		throw 50000, 'Kindly provide either server_ip or server_name along with user_name.', 1;

	if IS_SRVROLEMEMBER('SYSADMIN') <> 1 and @old_password_string is null
		throw 50000, 'Since caller is not a sysadmin, kindly provide @old_password_string to validate the user_name before any action.', 1;

	if IS_SRVROLEMEMBER('SYSADMIN') = 1 and @old_password_string is null and @confirm_forgot_password = 0
		throw 50000, 'Since caller is a sysadmin, kindly either provide existing @old_password_string or execute with parameter @confirm_forgot_password = 1.', 1;

	if @save_passphrase = 0 and @new_passphrase_string is null
		throw 50000, 'Kindly provide @new_passphrase_string.', 1;

	if object_id('tempdb..#matched_credentials') is not null
		drop table #matched_credentials;
	select server_ip, server_name, [user_name], is_sql_user, is_rdp_user, 
			password_hash, --[password] = cast(DecryptByPassPhrase(cast(salt as varchar),password_hash ,1, @server_ip) as varchar),
			salt, --salt_raw = cast(salt as varchar),		
			created_date, created_by, updated_date, updated_by, 
			delegate_login_01, delegate_login_02, remarks
	into #matched_credentials
	from dbo.credential_manager
	where (@server_ip is null or server_ip = @server_ip)
	and (@server_name is null or server_name = @server_name)
	and [user_name] = @user_name
	and (	(	(IS_SRVROLEMEMBER('SYSADMIN') = 1)
				or	
				(created_by = SUSER_NAME() or updated_by = SUSER_NAME() or delegate_login_01 = SUSER_NAME() or delegate_login_02 = SUSER_NAME())
			)
			and
			(	(@old_password_string is not null and @old_password_string = cast(DecryptByPassPhrase(cast(salt as varchar),password_hash ,1, server_ip) as varchar))
				or
				(@old_password_string is not null and @old_password_string = cast(DecryptByPassPhrase(cast(@old_passphrase_string as varchar),password_hash ,1, server_ip) as varchar))
				or
				(@old_password_string is null and @confirm_forgot_password = 1)
			)
		);

	if (select count(*) from #matched_credentials) > 1
		throw 50000, 'More than one credentials found. Kindly provide both server_ip and user_name to narrow down credential search.', 1;
	if (select count(*) from #matched_credentials) = 0
		throw 50000, 'No matching credentials found.', 1;
	
	if (select count(*) from #matched_credentials) = 1
	begin
		update cm set
		--select cm.server_ip, cm.server_name, cm.[user_name], 
				is_sql_user = case when @is_sql_user is null then cm.is_sql_user else @is_sql_user end, 
				is_rdp_user = case when @is_rdp_user is null then cm.is_rdp_user else @is_rdp_user end, 
				password_hash = case when @new_password_string is not null or @new_passphrase_string is not null
									then EncryptByPassPhrase((case when @new_passphrase_string is not null then @new_passphrase_string else isnull(@old_passphrase_string,cast(cm.salt as varchar)) end), (case when @new_password_string is not null then @new_password_string else isnull(@old_password_string,cast(DecryptByPassPhrase(cast(cm.salt as varchar),cm.password_hash ,1, cm.server_ip) as varchar)) end), 1, @server_ip) 
									else cm.password_hash end,
				--salt = case when @new_passphrase_string is not null then cm.is_sql_user else @is_sql_user end, 
				salt = case when @save_passphrase = 0 then null 
							when @new_passphrase_string is not null then convert(varbinary(125),@new_passphrase_string)
							else cm.salt end,
				updated_date = sysdatetime(), 
				updated_by = SUSER_NAME(), 
				delegate_login_01 = case when @delegate_login_01 is null then cm.delegate_login_01 else @delegate_login_01 end, 
				delegate_login_02 = case when @delegate_login_02 is null then cm.delegate_login_02 else @delegate_login_02 end, 
				remarks = case when @remarks is null then cm.remarks else @remarks end
		from dbo.credential_manager cm
		join #matched_credentials t
		on t.server_ip = cm.server_ip and t.user_name = cm.user_name;

		if @@ROWCOUNT > 0
			select 'Credential Updated.' as [result];
	end
end
go
