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
        self.__compute_df_alert_pyodbc_resultset()
        self.__compute_severity()
        self.__compute_state()

    def __compute_severity(self):
        if self.verbose:
            self.logger.info(f"Before self.severity = '{self.severity}'")            

    def __compute_state(self):
        if self.verbose:
            self.logger.info(f"Before self.state = '{self.state}'")

    def __compute_df_alert_pyodbc_resultset(self):
        self.__df_alert_pyodbc_resultset = get_pandas_dataframe(self.alert_pyodbc_resultset, index_col='sql_instance')
        if self.verbose:
            self.logger.info(f"self.__df_alert_pyodbc_resultset..")
            print(self.__df_alert_pyodbc_resultset)
