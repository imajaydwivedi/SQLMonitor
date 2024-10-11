import pyodbc
#from get_pandas_dataframe import get_pandas_dataframe
from get_oncall_teams import get_oncall_teams
from get_pretty_table import get_pretty_table

class SmaAlert():
    ''' SYNOPSIS: Class to represent dbo.sma_alert table
        INPUT:
    '''

    def __init__(self, alert_key:str=None, alert_owner_team:str='', state:str='', severity:str='', logger=None, header:str='', description:str='', frequency_minutes:int=0, slack_ts_value:str = None, id:int = None, affected_servers:tuple=None, alert_method:str=None, verbose:bool=False):
        ''' SYNOPSIS: Constructor
        '''
        self.id = id
        self.alert_key = alert_key
        self.alert_owner_team = alert_owner_team
        self.state = state
        self.severity = severity
        self.logger = logger
        self.header = header
        self.description = description
        self.slack_ts_value = slack_ts_value
        self.frequency_minutes = frequency_minutes
        self.affected_servers = affected_servers
        self.alert_method = alert_method
        self.exists = None
        self.verbose = verbose

    def fetch_data_from_db(self,sql_connection):
        if self.verbose:
            self.logger.info(f"get alert for key '{self.alert_key}' from database..")

        cursor = sql_connection.cursor()
        sql_query = f"""
declare @_rows_affected int;
exec @_rows_affected = dbo.usp_get_active_alert_by_key @alert_key = ?;
select [rows_affected] = isnull(@_rows_affected,0);
    """
        cursor.execute(sql_query, self.alert_key)
        #cursor.execute(sql_query, 'Alert-DiskSpace - [21L-LTPABL-1187]')
        query_resultset = cursor.fetchall()
        cursor.nextset()
        row_count = (cursor.fetchall())[0][0]

        # set existence
        self.exists = bool(row_count)

        #return (row_count,query_resultset)
        return query_resultset

    def initialize_data_from_db(self,sql_connection):
        alert_data_from_db = self.fetch_data_from_db(sql_connection)
        owner_team_deatails_from_db = self.fetch_owner_team_details(sql_connection)

        if self.verbose:
            pt_owner_team_deatails_from_db = get_pretty_table(owner_team_deatails_from_db)
            self.logger.info(f"Alert owner team '{self.alert_owner_team}' details..")
            print(pt_owner_team_deatails_from_db)

        if self.exists:
            if self.verbose:
                self.logger.info(f"initialize alert attributes from fetched data..")
                pt_alert_data_from_db = get_pretty_table(alert_data_from_db)
                self.logger.info(f"Alert data fetched from db for alert key '{self.alert_key}'..")
                print(pt_alert_data_from_db)
                
            self.id = alert_data_from_db[0].id
            self.state = alert_data_from_db[0].state
            self.severity = alert_data_from_db[0].severity
            self.slack_ts_value = alert_data_from_db[0].slack_ts_value
            self.frequency_minutes = alert_data_from_db[0].frequency_minutes

            self.alert_owner_team = alert_data_from_db[0].alert_owner_team
            self.alert_method = alert_data_from_db[0].alert_method
        else:
            self.alert_method = owner_team_deatails_from_db[0].alert_method

        return self.exists

    def fetch_owner_team_details(self,sql_connection):
        if self.verbose:
            self.logger.info(f"fetch alert owner team [{self.alert_owner_team}] details from database..")

        query_resultset = get_oncall_teams(sql_connection, self.alert_owner_team)
        #self.alert_method = query_resultset[0].alert_method

        return query_resultset

class SmaDiskSpaceAlert(SmaAlert):
    '''
    SYNOPSIS: Class to represent disk space alert
    '''

    def __init__(self, alert_key:str=None, alert_owner_team:str='', state:str='', severity:str='', logger=None, header:str='', description:str='', frequency_minutes:int=30, slack_ts_value:str = None, id:int = None, affected_servers:tuple=None, alert_method:str=None, verbose:bool=False, disk_warning_pct:float=65, disk_critical_pct:float=85, disk_threshold_gb:int=250, large_disk_threshold_pct:float=95):
        ''' SYNOPSIS: Constructor
        '''
        super().__init__(alert_key, alert_owner_team, state, severity, logger, header, description, frequency_minutes, slack_ts_value, id, affected_servers, alert_method, verbose)
        self.disk_warning_pct = disk_warning_pct
        self.disk_critical_pct = disk_critical_pct
        self.disk_threshold_gb = disk_threshold_gb
        self.large_disk_threshold_pct = large_disk_threshold_pct

