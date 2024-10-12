import pyodbc
from SmaAlertPackage.CommonFunctions.get_pandas_dataframe import get_pandas_dataframe
from SmaAlertPackage.CommonFunctions.get_oncall_teams import get_oncall_teams
from SmaAlertPackage.CommonFunctions.get_pretty_table import get_pretty_table
from SmaAlertPackage.CommonFunctions.get_pretty_dictionary import get_pretty_dictionary
from SmaAlertPackage.CommonFunctions.call_usp_insert_sma_alert import call_usp_insert_sma_alert
from SmaAlertPackage.CommonFunctions.get_sma_params import get_sma_params
from SmaAlertPackage.CommonFunctions.get_sm_credential import get_sm_credential
from datetime import datetime, timezone

class SmaAlert():
    ''' SYNOPSIS: Class to represent dbo.sma_alert table
        INPUT:
    '''

    def __init__(self, alert_key:str=None, alert_owner_team:str='', state:str='', severity:str='', logger=None, header:str='', description:str='', frequency_minutes:int=0, slack_ts_value:str = None, id:int = None, affected_servers:tuple=None, alert_method:str=None, alert_job_name:str=None,  verbose:bool=False):
        ''' SYNOPSIS: Constructor
        '''
        self.id = id
        self.alert_key = alert_key
        self.alert_owner_team = alert_owner_team
        self.state = state
        self.severity = severity
        self.header = header
        self.description = description
        self.slack_ts_value = slack_ts_value
        self.frequency_minutes = frequency_minutes
        self.affected_servers = affected_servers
        self.alert_method = alert_method
        self.suppress_start_date_utc = None
        self.suppress_end_date_utc = None
        self.alert_job_name = None
        self.logger = logger # logging tool
        self.logged_by = self.alert_job_name # alert logging job or person using portal
        self.exists = None
        self.generate_alert = None
        self.action_to_take = 'No Action' # 'No Action', 'Create', 'Update', 'Upgrade', 'SkipNotification', 'Clear'
        self.verbose = verbose
        self.sql_connection = None
        self.credential_manager_database = None

        self.__alert_data_from_db = None
        self.__owner_team_details_from_db = None
        self.__slack_token = None
        self.__slack_bot = None
        self.__alert_owner_team_email = None
        self.__alert_owner_team_pagerduty_service_key = None
        self.__alert_owner_team_slack_channel = None
        self.__alert_dashboard_url = None
        self.__sqlmonitor_dashboard_url = None
        #self.__affected_servers_json = None

    def __get_alert_dict(self):
        obj_dict = dict(alert_id = self.id,
                        alert_key = self.alert_key,
                        alert_owner_team = self.alert_owner_team,
                        state = self.state,
                        severity = self.severity,
                        logged_by = self.alert_job_name,
                        header = self.header,
                        #description = self.description,
                        slack_ts_value = self.slack_ts_value,
                        frequency_minutes = self.frequency_minutes,
                        #affected_servers = self.affected_servers,
                        alert_method = self.alert_method,
                        suppress_start_date_utc = self.suppress_start_date_utc,
                        suppress_end_date_utc = self.suppress_end_date_utc,
                        alert_job_name = self.alert_job_name,
                        exists = self.exists,
                        generate_alert = self.generate_alert,
                        action_to_take = self.action_to_take,
                        verbose = self.verbose
                    )
        return obj_dict

    def __get_pretty_alert(self):
        pt = get_pretty_dictionary(self.__get_alert_dict())
        print(pt.get_string(fields=["alert_id", "alert_key", "alert_owner_team", "state", "severity", "frequency_minutes", "slack_ts_value", "alert_method", "logged_by"]))
        print(pt.get_string(fields=["action_to_take", "exists", "generate_alert", "verbose", "suppress_start_date_utc", "suppress_end_date_utc", "header"]))
        
        self.logger.info(f"Text snippet inside self.description => ")
        print(self.description)

    def fetch_data_from_db(self):
        if self.verbose:
            self.logger.info(f"get alert for key '{self.alert_key}' from database..")

        cursor = self.sql_connection.cursor()
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

    def initialize_data_from_db(self):
        self.__alert_data_from_db = self.fetch_data_from_db()
        self.__owner_team_details_from_db = self.fetch_owner_team_details()

        if self.verbose:
            pt_owner_team_deatails_from_db = get_pretty_table(self.__owner_team_details_from_db)
            self.logger.info(f"Alert owner team '{self.alert_owner_team}' details..")
            print(pt_owner_team_deatails_from_db)

        if self.exists:
            if self.verbose:
                self.logger.info(f"initialize alert attributes from fetched data..")
                pt_alert_data_from_db = get_pretty_table(self.__alert_data_from_db)
                self.logger.info(f"Alert data fetched from db for alert key '{self.alert_key}'..")
                print(pt_alert_data_from_db)

            self.id = self.__alert_data_from_db[0].id
            self.state = self.__alert_data_from_db[0].state
            self.severity = self.__alert_data_from_db[0].severity
            self.slack_ts_value = self.__alert_data_from_db[0].slack_ts_value
            self.frequency_minutes = self.__alert_data_from_db[0].frequency_minutes

            self.alert_owner_team = self.__alert_data_from_db[0].alert_owner_team
            self.alert_method = self.__alert_data_from_db[0].alert_method

            self.suppress_start_date_utc = self.__alert_data_from_db[0].suppress_start_date_utc
            self.suppress_end_date_utc = self.__alert_data_from_db[0].suppress_end_date_utc
        else:
            self.alert_method = self.__owner_team_details_from_db[0].alert_method

        # set alert_owner_team related attributes
        self.__alert_owner_team_email = self.__owner_team_details_from_db[0].team_email
        self.__alert_owner_team_slack_channel = self.__owner_team_details_from_db[0].team_slack_channel
        self.__alert_owner_team_pagerduty_service_key = self.__owner_team_details_from_db[0].team_slack_channel

        # set attributes from dbo.sma_params
        self.__slack_bot = get_sma_params(self.sql_connection, param_key='dba_slack_bot')[0].param_value
        self.credential_manager_database = get_sma_params(self.sql_connection, param_key='credential_manager_database')[0].param_value
        self.__alert_dashboard_url = get_sma_params(self.sql_connection, param_key='url_for_alerts_grafana_dashboard')[0].param_value

        # set attributes from credential manager
        if self.alert_method == 'slack':
            self.__slack_token = get_sm_credential(self.sql_connection, self.credential_manager_database, 'dba_slack_bot_token')
        if self.alert_method == 'pagerduty':
            self.__alert_owner_team_pagerduty_service_key = get_sm_credential(self.sql_connection, self.credential_manager_database, 'dba_pagerduty_service_key')

        # set action_to_take -- 'No Action', 'Create', 'Clear', 'SkipNotification', 'Update', 'Upgrade'
        if self.exists is False and self.generate_alert is False:
            self.action_to_take = 'No Action'
        else:
            if self.exists is False and self.generate_alert is True:
                self.action_to_take = 'Create'

            if self.exists and self.generate_alert is False:
                self.action_to_take = 'Clear'

            if self.exists and self.generate_alert:
                self.action_to_take = 'Update'

            if self.exists and self.suppress_start_date_utc is not None and self.suppress_end_date_utc is not None:
                now_utc = datetime.now(timezone.utc)
                if self.suppress_start_date_utc < now_utc < self.suppress_end_date_utc:
                    self.action_to_take = 'SkipNotification'

            if self.exists and self.action_to_take not in ['No Action', 'Create', 'Upgrade', 'SkipNotification', 'Clear']:
                self.action_to_take = 'Update'

        return self.exists

    def fetch_owner_team_details(self):
        if self.verbose:
            self.logger.info(f"fetch alert owner team [{self.alert_owner_team}] details from database..")

        query_resultset = get_oncall_teams(self.sql_connection, self.alert_owner_team)

        return query_resultset

    def __call_usp_insert_sma_alert(self):
        if self.verbose:
            self.logger.info(f"executing SmaAlert.__call_usp_insert_sma_alert()..")

        query_params = dict(alert_key=self.alert_key, frequency_minutes=self.frequency_minutes, alert_owner_team=self.alert_owner_team,
                            state=self.state, action_to_take=self.action_to_take, severity=self.severity, logged_by=self.logged_by,
                            header=self.header, description=self.description, affected_servers=self.affected_servers
                            )
        query_resultset = call_usp_insert_sma_alert(self.sql_connection, self.logger, self.verbose, **query_params)

        if self.verbose:
            self.logger.info(f"result of call_usp_insert_sma_alert() is alert_id {query_resultset[0]} ")
        
        if len(query_resultset) > 0 and self.action_to_take == 'Create':
            self.logger.info(f"set self.id with '{query_resultset[0]}'")
            self.id = query_resultset[0]

    def __send_alert_notification(self):
        if self.verbose:
            self.logger.info(f"executing SmaAlert.__send_alert_notification()..")

        if self.alert_method == 'slack':
            self.__send_slack_alert_notification()
        elif self.alert_method == 'email':
            self.__send_email_alert_notification()
        elif self.alert_method == 'pagerduty':
            self.__send_pagerduty_alert_notification()
        else:
            if self.verbose:
                self.logger.warning(f"alert_method '{self.alert_method}' is still not implemented.")

    def __send_slack_alert_notification(self):
        if self.verbose:
            self.logger.info(f"executing SmaAlert.__send_slack_alert_notification()..")
    
    def __send_email_alert_notification(self):
        if self.verbose:
            self.logger.info(f"executing SmaAlert.__send_email_alert_notification()..")

    def __send_pagerduty_alert_notification(self):
        if self.verbose:
            self.logger.info(f"executing SmaAlert.__send_pagerduty_alert_notification()..")

    def take_required_action(self): # Reimplement this in child class if to override
        if self.verbose:
            self.logger.info(f"Perform '{self.action_to_take}' action under function take_required_action()..")
            self.__get_pretty_alert()
        
        if self.action_to_take != 'No Action':
            self.__call_usp_insert_sma_alert()
            self.__send_alert_notification()


