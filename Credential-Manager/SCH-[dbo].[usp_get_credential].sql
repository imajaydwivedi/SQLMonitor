use DBA
go

IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

--drop procedure dbo.usp_get_credential
create or alter procedure dbo.usp_get_credential
	@server_ip char(15) = null, 
	@server_name varchar(125) = null, 
	@user_name varchar(125) = null,
	@passphrase_string varchar(125) = null,
	@password varchar(256) = null output,
	@verbose tinyint = 0 /* 0=none, 1=messages, 2=all */
with  encryption
as
begin
/*	Purpose:		This procedure helps to retrieve a credential password based on provided server & user_name
	Modification:	2024-Oct-12 - Ajay - Bux fix where password is getting truncated when its very long
					2023-Dec-17 - Ajay - Bux fix where IS_SRVROLEMEMBER was incorrecting displaying other users passwords

*/
	set nocount on;

	declare @_sql nvarchar(max);
	declare @_params nvarchar(max);
	declare @_rows_affected int = 0;
	declare @_caller_user varchar(125) = SUSER_NAME();
	declare @_is_caller_sysadmin int = IS_SRVROLEMEMBER('SYSADMIN', @_caller_user);
	declare @_privilege varchar(10);
	declare @_privilege_table table (
		account_name varchar(255), acc_type varchar(50),
		privilege varchar(10), mapped_login_name varchar(255),
		permission_path varchar(500));

	if ( (charindex('\',@_caller_user) <> 0) and (@_is_caller_sysadmin is null) )
	begin
		insert @_privilege_table (account_name, acc_type, privilege, mapped_login_name, permission_path)
		exec xp_logininfo @acctname = @_caller_user --, @privilege = @_privilege OUTPUT;
	end

	if exists (select * from @_privilege_table where privilege = 'admin')
	begin
		set @_is_caller_sysadmin = 1;
		set @_privilege = 'admin';
	end

	if @verbose > 0
	begin
		print 'Start validation of variables..';
		select [current_user] = @_caller_user, [is_sysadmin] = @_is_caller_sysadmin;
	end

	if (@server_ip is null and @user_name is null and @server_name is null) and (@_is_caller_sysadmin <> 1)
		throw 50000, 'Kindly provide both server_ip/server_name or user_name.', 1;

	if @_is_caller_sysadmin <> 1
		print 'Since caller is not a sysadmin, Only look for credentials created/updated by caller, or caller is delegate.'

	if @verbose > 0
		print 'Create #matched_credentials..';
	if object_id('tempdb..#matched_credentials') is not null
		drop table #matched_credentials;
	create table #matched_credentials
	(	server_ip char(15) not null,
		server_name varchar(125) null,
		[user_name] varchar(125) not null,
		is_sql_user bit not null default 0,
		is_rdp_user bit not null default 0,
		[password_hash] varbinary(256) not null,
		salt varbinary(125) null,		
		created_date datetime2 not null,
		created_by varchar(125) not null,
		updated_date datetime2 not null,
		updated_by varchar(125) not null,
		delegate_login_01 varchar(125) null,
		delegate_login_02 varchar(125) null,
		remarks nvarchar(2000),
		is_sysadmin bit,
		context_user varchar(125)
	);

	set @_params = '@server_ip char(15), @server_name varchar(125), @user_name varchar(125), @passphrase_string varchar(125), @caller_user varchar(125), @is_caller_sysadmin int';
	set @_sql = '
	insert #matched_credentials 
	(server_ip, server_name, [user_name], is_sql_user, is_rdp_user, password_hash, salt, created_date, created_by, updated_date, updated_by, delegate_login_01, delegate_login_02, remarks, is_sysadmin, context_user )
	select /* dbo.usp_get_credential */ 
			server_ip, server_name, [user_name], is_sql_user, is_rdp_user, 
			password_hash, salt, created_date, created_by, updated_date, updated_by, 
			delegate_login_01, delegate_login_02, remarks
			,[is_sysadmin] = @is_caller_sysadmin
			,[context_user] = @caller_user
	from dbo.credential_manager
	where 1=1
	'+(case when @server_ip is null then '--' else '' end)+ 'and server_ip = @server_ip
	'+(case when @server_name is null then '--' else '' end)+ 'and server_name = @server_name
	'+(case when @user_name is null then '--' else '' end)+ 'and [user_name] = @user_name
	and (	@is_caller_sysadmin = 1
		or	[user_name] = @caller_user
		or	created_by = @caller_user
		or	updated_by = @caller_user
		or	(delegate_login_01 is not null and delegate_login_01 = @caller_user)
		or	(delegate_login_02 is not null and delegate_login_02 = @caller_user)
		);
	';
	if @verbose >= 2
		print char(10)+@_sql+char(10);

	exec sp_executesql @_sql, @_params, @server_ip, @server_name, @user_name, @passphrase_string, @caller_user = @_caller_user, @is_caller_sysadmin = @_is_caller_sysadmin;
	set @_rows_affected = @@ROWCOUNT;

	if @verbose > 0
		print 'Matching Credentials (@_rows_affected) = '+convert(varchar,@_rows_affected);

	if @verbose >= 2
	begin
		select [RunningQuery], cm.* 
		from #matched_credentials cm
		full outer join (select [RunningQuery] = '#matched_credentials') d
		on 1=1
	end

	if(@passphrase_string is not null) and @_rows_affected > 1
		throw 50000, 'More than one credentials found. Kindly provide both server_ip and user_name to narrow down credential search.', 1;

	if @_is_caller_sysadmin <> 1 and @_rows_affected > 1
		throw 50000, 'More than one credentials found. Kindly provide both server_ip and user_name to narrow down credential search.', 1;
	
	if @_rows_affected > 0
	begin
		if @_rows_affected = 1
		begin
			print 'exact one match found. Decrypting password, and storing to output variable..';
			select @password = case when @passphrase_string is null 
										then cast(DecryptByPassPhrase(cast(salt as varchar(500)),password_hash ,1, isnull(@server_ip,server_ip)) as varchar(500))
										else cast(DecryptByPassPhrase(@passphrase_string,password_hash ,1, isnull(@server_ip,server_ip)) as varchar(500))
										end
			from #matched_credentials
		end
		else
		begin
			select server_ip, server_name, [user_name], is_sql_user, is_rdp_user,
				[password] = case when @passphrase_string is null 
									then cast(DecryptByPassPhrase(cast(salt as varchar(500)),password_hash ,1, isnull(@server_ip,server_ip)) as varchar(500))
									else cast(DecryptByPassPhrase(@passphrase_string,password_hash ,1, isnull(@server_ip,server_ip)) as varchar(500))
									end,
				created_date, created_by, updated_date, updated_by, remarks
			from #matched_credentials
		end
	end
	else
		throw 50000, 'No matching credentials found.', 1;
end
go

/*
ADD SIGNATURE TO [dbo].[usp_get_credential] BY CERTIFICATE credential_manager_cert 
	WITH PASSWORD = 'dbo.credential_manager'
GO
GRANT EXECUTE ON OBJECT::[dbo].[usp_get_credential] TO [public]
GO
*/