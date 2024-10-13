from SmaAlertPackage.SmaAlert import SmaAlert
from SmaAlertPackage.CommonFunctions.get_pandas_dataframe import get_pandas_dataframe
from SmaAlertPackage.CommonFunctions.get_pretty_table import get_pretty_table
from SmaAlertPackage.CommonFunctions.get_sma_params import get_sma_params

class SmaDiskSpaceAlert(SmaAlert):
    '''
    SYNOPSIS: Class to represent disk space alert
    '''

    #def __init__(self, alert_key:str=None, alert_owner_team:str='', frequency_minutes:int=30, disk_warning_pct:float=90, disk_critical_pct:float=95, disk_threshold_gb:int=250, large_disk_threshold_pct:float=92):
    def __init__(self, alert_key:str=None, alert_owner_team:str='', frequency_minutes:int=30, disk_warning_pct:float=70, disk_critical_pct:float=85, disk_threshold_gb:int=250, large_disk_threshold_pct:float=92):
        ''' SYNOPSIS: Constructor
        '''
        super().__init__(alert_key, alert_owner_team, frequency_minutes)
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
        self.__compute_sqlmonitor_dashboard_url()
        self.__compute_header()
        self.__compute_description()
        self.__compute_affected_servers()


    def __compute_severity(self):
        # 'Critical', 'High', 'Medium', 'Low'

        if self.generate_alert:
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
        if self.generate_alert:
            self.__df_alert_pyodbc_resultset = get_pandas_dataframe(self.alert_pyodbc_resultset, index_col='sql_instance')

    def __compute_state(self):
        # 'Active','Suppressed','Cleared', 'Resolved'
        if self.state is None or len(self.state) == 0:
            self.state = 'Active'

    def __compute_header(self):
        if self.verbose:
            self.logger.info(f"compute alert header for alert..")

        warning_count = 0
        critical_count = 0
        if self.generate_alert:
            df = self.__df_alert_pyodbc_resultset
            warning_count = len(df[df.state=='Warning'])
            warning_count = (warning_count if warning_count else 0)
            critical_count = len(df[df.state=='Critical'])
            critical_count = (critical_count if critical_count else 0)

        emoji = (':red_circle:' if critical_count>0 else ':warning:')
        if self.action_to_take == 'No Action':
            self.header = f"No Action"
            self.header_slack_markdown = f"No Action"
        
        if self.action_to_take == 'Create':
            self.header = f"[Active] - [Id#X] - [{self.alert_key}] - {warning_count} Warnings - {critical_count} Criticals"
            self.header_slack_markdown = f"<{self.alert_dashboard_url}|:fire: [Active] - [Id#X]> - <{self.__sqlmonitor_dashboard_url}|[*{self.alert_key}*] - *{warning_count}* Warnings - *{critical_count}* Criticals>"

        if self.action_to_take in ['Update','Upgrade']:
            self.header = f"[Triggered] - [{self.alert_key}] - {warning_count} Warnings - {critical_count} Criticals"
            self.header_slack_markdown = f"<{self.alert_dashboard_url}|{emoji} [Triggered]> - <{self.__sqlmonitor_dashboard_url}|[*{self.alert_key}*] - *{warning_count}* Warnings - *{critical_count}* Criticals>"

        if self.action_to_take == 'SkipNotification':
            self.header = f"[Suppressed] - [{self.alert_key}] - {warning_count} Warnings - {critical_count} Criticals"
            self.header_slack_markdown = f"<{self.alert_dashboard_url}|{emoji} [Suppressed]> - <{self.__sqlmonitor_dashboard_url}|[*{self.alert_key}*] - *{warning_count}* Warnings - *{critical_count}* Criticals>"

        if self.action_to_take == 'Clear':
            self.header = f"[Cleared] - [{self.alert_key}] - {warning_count} Warnings - {critical_count} Criticals"
            self.header_slack_markdown = f"<{self.alert_dashboard_url}|{emoji} [Cleared]> - <{self.__sqlmonitor_dashboard_url}|[*{self.alert_key}*] - *{warning_count}* Warnings - *{critical_count}* Criticals>"

    def __compute_description(self):
        if self.verbose:
            self.logger.info(f"compute alert description for alert..")

        if self.generate_alert:
            pt = get_pretty_table(self.alert_pyodbc_resultset)
            self.description = pt.get_string(fields=["sql_instance", "host_name", "disk_volume", "capacity_mb", "used_pct", "free_mb", "state"])
        else:
            self.description = f"Alert cleared."

    def __compute_affected_servers(self):
        if self.verbose:
            self.logger.info(f"compute affected servers for alert..")

        df = self.__df_alert_pyodbc_resultset
        if self.verbose:
            print(df)

    def __compute_sqlmonitor_dashboard_url(self):
        url_grafana_dash = get_sma_params(self.sql_connection, param_key='GrafanaDashboardPortal')[0].param_value
        url_panel = get_sma_params(self.sql_connection, param_key='url_all_servers_disk_utilization_dashboard_panel')[0].param_value

        self.__sqlmonitor_dashboard_url = f"{url_grafana_dash}{url_panel}"
        if self.verbose:
            self.logger.info(f"self.__sqlmonitor_dashboard_url = '{self.__sqlmonitor_dashboard_url}'")


