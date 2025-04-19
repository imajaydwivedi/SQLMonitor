import pyodbc
import os

# Pyodbc Cursor - https://github.com/mkleehammer/pyodbc/wiki/Cursor

# Enable pyodbc connection pooling explicitly
pyodbc.pooling = True

def connect_dba_instance(sql_instance='localhost', database='DBA', login_name='', login_password='', app_name='connect_dba_instance.py', logger=None, verbose:bool=False):
    if os.name == 'nt':
        # driver on windows
        sql_driver = 'SQL Server Native Client 11.0'
    else:
        # driver on linux
        sql_driver = 'ODBC Driver 18 for SQL Server'

    if login_name != '' and login_password != '':
        # connection using sql authentication
        connection_string = f"""
                DRIVER={{{sql_driver}}};
                SERVER={sql_instance};
                DATABASE={database};
                UID={login_name};
                PWD={login_password};
                Encrypt=yes;
                APP={app_name};
                TrustServerCertificate=yes;
                """
    else:
        # connection using integrated authentication
        connection_string = f"""
                DRIVER={{{sql_driver}}};
                SERVER={sql_instance};
                DATABASE={database};
                Encrypt=yes;
                APP={app_name};
                Trusted_Connection=Yes;
                TrustServerCertificate=yes;
                """

    if verbose:
        logger.info(f"connection_string => ")
        print(connection_string)
    cnxn = pyodbc.connect(connection_string, autocommit=True)
    return cnxn

'''
Blog: Encrypting SQL Server connections with Lets Encrypt certificates
https://sqlsunday.com/2017/11/22/encrypting-tds-with-letsencrypt/

Instructions for Self-Signed Certificates
-----------------------------------------
# Create self signed certificate for 10 years
New-SelfSignedCertificate `
    -DnsName "sqlmonitor.lab.com" `
    -CertStoreLocation "cert:\LocalMachine\My" `
    -FriendlyName "SQLMonitor SSL Cert" `
    -KeySpec KeyExchange `
    -KeyUsage DigitalSignature, KeyEncipherment `
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.1") `
    -NotAfter (Get-Date).AddYears(10)


# Export cert to c:\ with password encryption
$password = Read-Host "Enter Pass Key for Certificate" -AsSecureString
Export-PfxCertificate -Cert 'Cert:\LocalMachine\My\<Thumbprint>' `
    -FilePath 'C:\sqlmonitor_cert_selfsigned.pfx' `
    -Password $password

# Import Certificate
Import-PfxCertificate `
    -FilePath "C:\sqlmonitor_cert_selfsigned.pfx" `
    -CertStoreLocation "Cert:\LocalMachine\My" `
    -Password $password

# Add certificate on windows store
Add the certificate to Trusted Root Certification Authorities via mmc.exe > Certificates > Local Machine.


-- ***************************************************************************************
NOTE:
    TrustServerCertificate=yes
    should not be used in Production.
-- ***************************************************************************************


Part 01: Enable SSL/TLS Encryption on SQLMonitor (SQLServer)
------------------------------------------------------------
1. Enable Encryption
    Set Force Encryption = Yes on SQL Server configuration Manager
2. Install the Certificates
    -> Use a trusted SSL/TLS certificate (from a public CA or self-signed for testing).
    -> Import the certificate to the Windows Certificate Store > Local Machine > Personal > Certificates.
3. Bind the Certificate to SQL Server
    -> Go to SQL Server Configuration Manager > SQL Server Network Configuration > Protocols for MSSQLSERVER.
    -> Select the installed certificate from Certificate Tab.
    -> Restart the SQL Server Service.
4 .Verify Encryption
    SELECT encrypt_option FROM sys.dm_exec_connections WHERE session_id = @@SPID;


Part 02: Trust the Certificate on AlertManager (Flask App Server)
-----------------------------------------------------------------
1. On AlertManager (Linux/Container)
    -> Copy the SSL/TLS certificate (e.g., sqlmonitor-cert.pem) from SQLMonitor to AlertManager.
    -> Place it in a secure location, e.g., /etc/ssl/certs/sqlmonitor-cert.pem.
    -> Update the systems CA certificates
    
    sudo cp /path/to/sqlmonitor-cert.pem /etc/ssl/certs/
    sudo update-ca-certificates

Part 03: Configure pyodbc on AlertManager (Flask App)
------------------------------------------------------
import pyodbc

# Database connection settings
    certificate_path = '/etc/ssl/certs/sqlmonitor-cert.pem'  # Adjust path for your OS

# In pyodbc Connection String with SSL/TLS, add following parameters
    TrustServerCertificate=no;
    CertificateFile={certificate_path};

'''