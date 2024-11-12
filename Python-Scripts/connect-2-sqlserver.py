import pyodbc

# https://code.google.com/archive/p/pyodbc/wikis/Cursor.wiki

SERVER = 'localhost'
DATABASE = 'master'
USERNAME = 'grafana'
PASSWORD = 'grafana'
APPNAME = 'connect-2sqlserver-ajay-dwivedi.py'

connectionString = f"""
DRIVER={{ODBC Driver 18 for SQL Server}};
SERVER={SERVER};
DATABASE={DATABASE};
UID={USERNAME};
PWD={PASSWORD};
APP={APPNAME};
Trusted_Connection=Yes;
TrustServerCertificate=yes;
"""

print (connectionString)

#TrustServerCertificate=True'
conn = pyodbc.connect(connectionString)

sql_get_server_info = """
DECLARE @Domain NVARCHAR(255);
begin try
	EXEC master.dbo.xp_regread 'HKEY_LOCAL_MACHINE', 'SYSTEM\CurrentControlSet\services\Tcpip\Parameters', N'Domain',@Domain OUTPUT;
end try
begin catch
	print 'some erorr accessing registry'
end catch

select	[domain] = DEFAULT_DOMAIN(),
		[domain_reg] = @Domain,
		[ip] = convert(varchar,CONNECTIONPROPERTY('local_net_address')),
		[@@SERVERNAME] = @@SERVERNAME,
		[MachineName] = convert(varchar,serverproperty('MachineName')),
		[ServerName] = convert(varchar,serverproperty('ServerName')),
		[host_name] = convert(varchar,SERVERPROPERTY('ComputerNamePhysicalNetBIOS')),
		[sql_version] = @@VERSION,
		[service_name_str] = servicename,
		[service_name] = case	when @@servicename = 'MSSQLSERVER' and servicename like 'SQL Server (%)' then 'MSSQLSERVER'
								when @@servicename = 'MSSQLSERVER' and servicename like 'SQL Server Agent (%)' then 'SQLSERVERAGENT'
								when @@servicename <> 'MSSQLSERVER' and servicename like 'SQL Server (%)' then 'MSSQL$'+@@servicename
								when @@servicename <> 'MSSQLSERVER' and servicename like 'SQL Server Agent (%)' then 'SQLAgent'+@@servicename
								else 'MSSQL$'+@@servicename end,
		[instance_name] = @@servicename,
		service_account,
		convert(varchar,SERVERPROPERTY('Edition')) AS Edition,
		convert(varchar,SERVERPROPERTY('ProductVersion')) AS ProductVersion,
		convert(varchar,SERVERPROPERTY('ProductLevel')) AS ProductLevel
		--,instant_file_initialization_enabled
		--,*
from sys.dm_server_services 
where servicename like 'SQL Server (%)'
or servicename like 'SQL Server Agent (%)'
"""

cursor = conn.cursor()
cursor.execute(sql_get_server_info)

field_names = [i[0] for i in cursor.description]
#field_names = ', '.join(field_names)

print(field_names)

fetched_data = cursor.fetchall()
data = [list(rows) for rows in fetched_data] # this one
print(f"No of records => {len(fetched_data)}")

#help(fetched_data[0])

#print(type(records[0]))
#for r in records:
    #print(f"{r.CustomerID}\t{r.OrderCount}\t{r.CompanyName}")
    #None

conn.close()
