from SmaAlertPackage.SmaAlert import SmaAlert
from SmaAlertPackage.CommonFunctions.get_pandas_dataframe import get_pandas_dataframe

class SmaDiskSpaceAlert(SmaAlert):
    '''
    SYNOPSIS: Class to represent disk space alert
    '''

    def __init__(self, alert_key:str=None, alert_owner_team:str='', state:str='', severity:str='', logger=None, header:str='', description:str='', frequency_minutes:int=30, slack_ts_value:str = None, id:int = None, affected_servers:tuple=None, alert_method:str=None, alert_job_name:str=None, verbose:bool=False, disk_warning_pct:float=65, disk_critical_pct:float=85, disk_threshold_gb:int=250, large_disk_threshold_pct:float=95):
        ''' SYNOPSIS: Constructor
        '''
        super().__init__(alert_key, alert_owner_team, state, severity, logger, header, description, frequency_minutes, slack_ts_value, id, affected_servers, alert_method, alert_job_name, verbose)
        self.disk_warning_pct = disk_warning_pct
        self.disk_critical_pct = disk_critical_pct
        self.disk_threshold_gb = disk_threshold_gb
        self.large_disk_threshold_pct = large_disk_threshold_pct
        self.alert_pyodbc_resultset = None

        self.__df_alert_pyodbc_resultset = None        

    def initialize_derived_attributes(self):
        ''' SYNOPSIS: Computes derived attributes like State, Severity, header, logger, description, affected_servers etc
        '''
        self.__generate_alert = (True if len(self.alert_pyodbc_resultset)>0 else False)
        self.__compute_df_alert_pyodbc_resultset()
        self.__compute_severity()
        self.__compute_state()

    def __compute_severity(self):
        # 'Critical', 'High', 'Medium', 'Low'
        df = self.__df_alert_pyodbc_resultset
        
        if len(df[df.state=='Critical']) > 0:
            self.severity = 'Critical'
        elif len(df[df.state=='High']) > 0:
            self.severity = 'High'
        elif len(df[df.state=='Medium']) > 0:
            self.severity = 'Medium'
        else:
            self.severity = 'Low'

    def __compute_df_alert_pyodbc_resultset(self):
        self.__df_alert_pyodbc_resultset = get_pandas_dataframe(self.alert_pyodbc_resultset, index_col='sql_instance')

    def __compute_state(self):
        # 'Active','Suppressed','Cleared', 'Resolved'
        if len(self.state) == 0:
            self.state = 'Active'
