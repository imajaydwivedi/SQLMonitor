import pyodbc
import os

# Pyodbc Cursor - https://github.com/mkleehammer/pyodbc/wiki/Cursor

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
                APP={app_name};
                TrustServerCertificate=yes;
                """
    else:
        # connection using integrated authentication
        connection_string = f"""
                DRIVER={{{sql_driver}}};
                SERVER={sql_instance};
                DATABASE={database};
                APP={app_name};
                Trusted_Connection=Yes;
                TrustServerCertificate=yes;
                """

    if verbose:
        logger.info(f"connection_string => ")
        print(connection_string)
    cnxn = pyodbc.connect(connection_string, autocommit=True)
    return cnxn