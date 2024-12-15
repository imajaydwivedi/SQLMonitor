from SmaAlertPackage.AlertClasses.SmaAlert import SmaAlert
from SmaAlertPackage.CommonFunctions.get_pandas_dataframe import get_pandas_dataframe
from SmaAlertPackage.CommonFunctions.get_pretty_table import get_pretty_table
from SmaAlertPackage.CommonFunctions.get_sma_params import get_sma_params

class SmaDiskSpaceAlert(SmaAlert):
    '''
    SYNOPSIS: Class to represent disk space alert
    '''

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
        self.__fields_for_display = ["sql_instance", "host_name", "disk_volume", "capacity_mb", "used_pct", "free_mb", "state"]

        # severity counts
        self.__critical_count = 0
        self.__high_count = 0
        self.__warning_count = 0
        self.__medium_count = 0
        self.__low_count = 0

    def initialize_derived_attributes(self):
        ''' SYNOPSIS: Computes derived attributes like State, Severity, header, logger, description, affected_servers etc
        '''
        self.__compute_df_alert_pyodbc_resultset()
        self.__compute_severity()
        self.__compute_state()
        self.__compute_sqlmonitor_dashboard_url()
        self.__compute_header()

        if self.alert_method == 'slack':
            self.__compute_header_slack_markdown()
            self.__compute_description()

        if self.alert_method == 'email':
            self.__compute_alert_mail_subject()
            self.__compute_alert_mail_body()

        self.__compute_affected_servers()

    def __compute_df_alert_pyodbc_resultset(self):
        if self.generate_alert:
            self.__df_alert_pyodbc_resultset = get_pandas_dataframe(self.alert_pyodbc_resultset, index_col='sql_instance')

    def __compute_severity(self):
        # 'Critical', 'High', 'Warning', 'Medium', 'Low'

        existing_severity = self.severity
        if self.generate_alert:
            df = self.__df_alert_pyodbc_resultset

            self.__critical_count = len(df[df.state=='Critical'])
            self.__high_count = len(df[df.state=='High'])
            self.__warning_count = len(df[df.state=='Warning'])
            self.__medium_count = len(df[df.state=='Medium'])
            self.__low_count = len(df[df.state=='Low'])

        if self.__critical_count > 0:
            self.severity = 'Critical'
        elif self.__high_count > 0:
            self.severity = 'High'
        elif self.__warning_count > 0:
            self.severity = 'High'
        elif self.__medium_count > 0:
            self.severity = 'Medium'
        else:
            self.severity = 'Low'

        # upgrade severity if required
        if existing_severity is not None and (self.severity_dictionary[existing_severity] < self.severity_dictionary[self.severity]):
            self.action_to_take = 'Upgrade'

    def __compute_state(self):
        # 'Active','Suppressed','Cleared', 'Resolved'
        if self.state is None or len(self.state) == 0:
            self.state = 'Active'

    def __compute_header(self):
        if self.verbose:
            self.logger.info(f"compute alert header for alert..")

        if self.action_to_take == 'No Action':
            self.header = f"No Action"

        if self.action_to_take == 'Create':
            self.header = f"[Active] - [Id#X] - [{self.alert_key}] - {self.__warning_count} Warnings - {self.__critical_count} Criticals"

        if self.action_to_take in ['Update','Upgrade']:
            self.header = f"[Triggered] - [{self.alert_key}] - {self.__warning_count} Warnings - {self.__critical_count} Criticals"

        if self.action_to_take == 'SkipNotification':
            self.header = f"[Suppressed] - [{self.alert_key}] - {self.__warning_count} Warnings - {self.__critical_count} Criticals"

        if self.action_to_take == 'Clear':
            self.header = f"[Cleared] - [{self.alert_key}] - {self.__warning_count} Warnings - {self.__critical_count} Criticals"

    def __compute_header_slack_markdown(self):
        if self.verbose:
            self.logger.info(f"compute alert header_slack_markdown for alert..")

        emoji = (':red_circle:' if self.__critical_count>0 else ':warning:')
        if self.action_to_take == 'No Action':
            self.header_slack_markdown = f"No Action"

        if self.action_to_take == 'Create':
            self.header_slack_markdown = f"<{self.alert_dashboard_url}|:fire: [Active] - [Id#X]> - <{self.__sqlmonitor_dashboard_url}|[*{self.alert_key}*] - *{self.__warning_count}* Warnings - *{self.__critical_count}* Criticals>"

        if self.action_to_take in ['Update','Upgrade']:
            self.header_slack_markdown = f"<{self.alert_dashboard_url}|{emoji} [Triggered]> - <{self.__sqlmonitor_dashboard_url}|[*{self.alert_key}*] - *{self.__warning_count}* Warnings - *{self.__critical_count}* Criticals>"

        if self.action_to_take == 'SkipNotification':
            self.header_slack_markdown = f"<{self.alert_dashboard_url}|{emoji} [Suppressed]> - <{self.__sqlmonitor_dashboard_url}|[*{self.alert_key}*] - *{self.__warning_count}* Warnings - *{self.__critical_count}* Criticals>"

        if self.action_to_take == 'Clear':
            self.header_slack_markdown = f"<{self.alert_dashboard_url}|{emoji} [Cleared]> - <{self.__sqlmonitor_dashboard_url}|[*{self.alert_key}*] - *{self.__warning_count}* Warnings - *{self.__critical_count}* Criticals>"

    def __compute_description(self):
        if self.verbose:
            self.logger.info(f"compute alert description for alert..")

        if self.generate_alert:
            pt = get_pretty_table(self.alert_pyodbc_resultset)
            self.description = pt.get_string(fields=self.__fields_for_display)
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

        self.__sqlmonitor_dashboard_url = f"{url_grafana_dash}d/{url_panel}"
        if self.verbose:
            self.logger.info(f"self.__sqlmonitor_dashboard_url = '{self.__sqlmonitor_dashboard_url}'")

    def __compute_alert_mail_subject(self):
        if self.verbose:
            self.logger.info(f"compute self.alert_mail_subject..")

        if self.action_to_take in ['Update','Upgrade','SkipNotification','Clear']:
            self.alert_mail_subject = f"[Id#{self.id}] - [{self.alert_key}]"
        else:
            self.alert_mail_subject = f"[Id#X] - [{self.alert_key}]"

    def __compute_alert_mail_body(self):
        if self.verbose:
            self.logger.info(f"compute self.alert_mail_body..")
            self.logger.info(f"len(self.__df_alert_pyodbc_resultset) = {len(self.__df_alert_pyodbc_resultset)}")

        # local variables
        alert_mail_header = None
        alert_mail_table = ''

        if self.generate_alert:
            df = self.__df_alert_pyodbc_resultset

            alert_mail_table = df.to_html(columns=self.__fields_for_display,
                                    justify='center', index=False, escape=False, decimal=',',
                                    formatters={
                                        'sql_instance': lambda x: f'<b>{x}</b>',
                                        'state': self.state_colorizer
                                    }
                                )

        if self.action_to_take == 'No Action':
            alert_mail_header = f"No Action"
            alert_mail_table = f"No Action"

        if self.action_to_take == 'Create':
            alert_mail_header = f'<h3><a href="{self.alert_dashboard_url}" target="_blank">[Active] - [Id#X]</a> - <a href="{self.__sqlmonitor_dashboard_url}" target="_blank">[{self.alert_key}] - {self.__warning_count} Warnings - {self.__critical_count} Criticals</a></h3>'

        if self.action_to_take in ['Update','Upgrade']:
            alert_mail_header = f'<h3><a href="{self.alert_dashboard_url}" target="_blank">[Triggered] - [Id#{self.id}]</a> - <a href="{self.__sqlmonitor_dashboard_url}" target="_blank">[{self.alert_key}] - {self.__warning_count} Warnings - {self.__critical_count} Criticals</a></h3>'

        if self.action_to_take == 'SkipNotification':
            alert_mail_header = f'<h3><a href="{self.alert_dashboard_url}" target="_blank">[Suppressed] - [Id#{self.id}]</a> - <a href="{self.__sqlmonitor_dashboard_url}" target="_blank">[{self.alert_key}] - {self.__warning_count} Warnings - {self.__critical_count} Criticals</a></h3>'

        if self.action_to_take == 'Clear':
            alert_mail_header = f'<h3><a href="{self.alert_dashboard_url}" target="_blank">[Cleared] - [Id#{self.id}]</a> - <a href="{self.__sqlmonitor_dashboard_url}" target="_blank">[{self.alert_key}] - {self.__warning_count} Warnings - {self.__critical_count} Criticals</a></h3>'

        if self.generate_alert:
            self.alert_mail_body = f"{alert_mail_header}<br><br>{alert_mail_table}<br><br><br>Regards,<br>{self.alert_job_name}"
        else:
            self.alert_mail_body = f"<h3>{self.alert_key} cleared.</h4><br><br><br><br>Regards,<br>{self.alert_job_name}"

