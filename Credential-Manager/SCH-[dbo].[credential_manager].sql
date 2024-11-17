use DBA
go

IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

-- alter table dbo.credential_manager set (system_versioning = off);
-- drop table dbo.credential_manager
-- drop table credential_manager_history
create table dbo.credential_manager
(	server_ip char(15) not null,
	server_name varchar(125) null,
	[user_name] varchar(125) not null,
	[password_hash] varbinary(500) not null,
	salt varbinary(125) null,
	is_sql_user bit not null default 0,
	is_rdp_user bit not null default 0,
	created_date datetime2 not null default getdate(),
	created_by varchar(125) not null default suser_name(),
	updated_date datetime2 not null default getdate(),
	updated_by varchar(125) not null default suser_name(),
	delegate_login_01 varchar(125) null,
	delegate_login_02 varchar(125) null,
	remarks nvarchar(2000)
	,constraint pk_credential_manager primary key clustered (server_ip, [user_name])

	,valid_from datetime2 generated always as row start hidden NOT NULL
    ,valid_to datetime2 generated always as row end hidden NOT NULL
    ,period for system_time (valid_from,valid_to)
)
with (system_versioning = on (HISTORY_TABLE = dbo.credential_manager_history))
go
create nonclustered index uq__server_name__user_name on dbo.credential_manager (server_name, [user_name])
go

-- drop table dbo.credential_manager_backup
--select * into dbo.credential_manager_backup from dbo.credential_manager
--insert dbo.credential_manager
--select * from dbo.credential_manager_backup

-- drop table dbo.credential_manager_audit
create table dbo.credential_manager_audit
(
	collection_time_utc datetime2 not null default getutcdate(),
	access_type varchar(50) not null,
	access_grant_status varchar(50) not null,
	server_ip char(15) not null,
	server_name varchar(125) null,
	original_login_name varchar(125) not null default original_login(),
	effective_login_name varchar(125) not null default suser_name(),
	client_host_name varchar(255) not null default host_name(),
	client_app_name varchar(255) null default app_name(),
	access_parameters nvarchar(2000) null,
	remarks varchar(500) null

	,index ci_credential_manager_audit clustered (collection_time_utc)
);
go

--insert dbo.credential_manager_audit
--(access_type, access_grant_status, server_ip, server_name, access_parameters, remarks)
--select	access_type = '',
--		access_grant_status = '', 
--		server_ip = '*', 
--		server_name = '*', 
--		access_parameters = null, 
--		remarks = null;

--select SUSER_NAME(), APP_NAME(), HOST_NAME(), ORIGINAL_LOGIN()

--select dec.net_transport, dec.auth_scheme, dec.client_net_address, 
--		des.host_name, des.program_name, des.client_interface_name,
--		des.login_name, des.original_login_name
--from sys.dm_exec_connections dec
--join sys.dm_exec_sessions des 
--	on des.session_id = dec.session_id