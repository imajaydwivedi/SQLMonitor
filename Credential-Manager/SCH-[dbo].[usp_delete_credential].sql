use DBA
go

IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

--drop procedure dbo.usp_delete_credential
create or alter procedure dbo.usp_delete_credential
	@server_ip char(15) = null,
	@server_name varchar(125) = null,
	@user_name varchar(125),
	@password varchar(256) = null,
	@passphrase_string varchar(125) = null,
	@confirm_forgot_password bit = 0
with encryption
as
begin
	set nocount on;
	if (@server_ip is null and @server_name is null)
		throw 50000, 'Kindly provide either server_ip or server_name along with user_name.', 1;

	if IS_SRVROLEMEMBER('SYSADMIN') <> 1 and @password is null
		throw 50000, 'Since caller is not a sysadmin, kindly provide password to validate the user_name before any action.', 1;

	if IS_SRVROLEMEMBER('SYSADMIN') = 1 and @password is null
		throw 50000, 'Since caller is a sysadmin, kindly either provide existing password or execute with parameter @confirm_forgot_password = 1.', 1;

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
			(	(@password is not null and @password = cast(DecryptByPassPhrase(cast(salt as varchar),password_hash ,1, server_ip) as varchar))
				or
				(@password is not null and @password = cast(DecryptByPassPhrase(cast(@passphrase_string as varchar),password_hash ,1, server_ip) as varchar))
				or
				(@password is null and @confirm_forgot_password = 1)
			)
		);

	if (select count(*) from #matched_credentials) > 1
		throw 50000, 'More than one credentials found. Kindly provide both server_ip and user_name to narrow down credential search.', 1;
	if (select count(*) from #matched_credentials) = 0
		throw 50000, 'No matching credentials found.', 1;
	
	if (select count(*) from #matched_credentials) = 1
	begin
		delete cm
		--select cm.server_ip, cm.server_name, cm.[user_name], cm.is_sql_user, cm.is_rdp_user, cm.password_hash, cm.salt, 
		--		cm.created_date, cm.created_by, cm.updated_date, cm.updated_by, cm.delegate_login_01, cm.delegate_login_02, cm.remarks 
		from dbo.credential_manager cm
		join #matched_credentials t
		on t.server_ip = cm.server_ip and t.user_name = cm.user_name;

		if @@ROWCOUNT > 0
			select 'Credential removed.';
	end
end
go
