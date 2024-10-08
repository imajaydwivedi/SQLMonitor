import pyodbc
#from get_pandas_dataframe import get_pandas_dataframe
from get_oncall_teams import get_oncall_teams

class SmaAlert():
    ''' SYNOPSIS: Class to represent dbo.sma_alert table
        INPUT:
    '''

    def __init__(self, alert_key:str=None, alert_owner_team:str='', state:str='', severity:str='', logger:str='', header:str='', description:str='', frequency_minutes:int=0, slack_ts_value:str = None, id:int = None, affected_servers:tuple=None, alert_method:str=None):
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

    def fetch_data_from_db(self,sql_connection):
        #print(f"get alert details by '{self.alert_key}")

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
        #print(f"get alert details by '{self.alert_key} & initialize alert attributes..")

        alert_data_from_db = self.fetch_data_from_db(sql_connection)

        if self.exists:
            self.id = alert_data_from_db[0].id
            self.alert_owner_team = alert_data_from_db[0].alert_owner_team
            self.state = alert_data_from_db[0].state
            self.severity = alert_data_from_db[0].severity
            self.slack_ts_value = alert_data_from_db[0].slack_ts_value
            self.frequency_minutes = alert_data_from_db[0].frequency_minutes
            self.alert_method = alert_data_from_db[0].alert_method

        return self.exists

    def fetch_owner_team_details(self,sql_connection):
        #print(f"fetch alert owner team details")

        query_resultset = get_oncall_teams(sql_connection=cnxn, team_name=self.alert_owner_team)

        return query_resultset

class SmaDiskSpaceAlert(SmaAlert):
    '''
    SYNOPSIS: Class to represent disk space alert
    '''

    def __init__(self, alert_key:str=None, alert_owner_team:str='', state:str='', severity:str='', logger:str='', header:str='', description:str='', frequency_minutes:int=30, slack_ts_value:str = None, id:int = None, affected_servers:tuple=None, alert_method:str=None, disk_warning_pct:float=65, disk_critical_pct:float=85, disk_threshold_gb:int=250, large_disk_threshold_pct:float=95):
        ''' SYNOPSIS: Constructor
        '''
        super().__init__(alert_key, alert_owner_team, state, severity, logger, header, description, frequency_minutes, slack_ts_value, id, affected_servers, alert_method)
        self.disk_warning_pct = disk_warning_pct
        self.disk_critical_pct = disk_critical_pct
        self.disk_threshold_gb = disk_threshold_gb
        self.large_disk_threshold_pct = large_disk_threshold_pct

