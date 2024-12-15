import pyodbc
from SmaAlertPackage.CommonFunctions.get_pandas_dataframe import get_pandas_dataframe
from SmaAlertPackage.CommonFunctions.get_oncall_teams import get_oncall_teams
from SmaAlertPackage.CommonFunctions.get_pretty_table import get_pretty_table
from SmaAlertPackage.CommonFunctions.get_pretty_dictionary import get_pretty_dictionary
from SmaAlertPackage.CommonFunctions.call_usp_insert_sma_alert import call_usp_insert_sma_alert
from SmaAlertPackage.CommonFunctions.get_sma_params import get_sma_params
from SmaAlertPackage.CommonFunctions.get_sm_credential import get_sm_credential
from SmaAlertPackage.CommonFunctions.send_slack_alert_notification import send_slack_alert_notification
from SmaAlertPackage.CommonFunctions.call_usp_update_alert_slack_ts_value import call_usp_update_alert_slack_ts_value
from SmaAlertPackage.CommonFunctions.send_email_alert_notification import send_email_alert_notification
from datetime import datetime, timezone

class SmaAlert():
    ''' SYNOPSIS: Class to represent dbo.sma_alert table
        INPUT:
    '''

    def __init__(self, alert_key:str=None, alert_owner_team:str='', frequency_minutes:int=0):
        ''' SYNOPSIS: Constructor
        '''
        self.id = None
        self.alert_key = alert_key
        self.alert_owner_team = alert_owner_team

        self.state = None # 'Active', 'Acknowledged', 'Suppressed', 'Cleared', 'Resolved'
        self.severity = None # 'Critical', 'High', 'Warning', 'Medium', 'Low'
        self.action_to_take = 'No Action' # 'No Action', 'Create', 'Acknowledge', 'Update', 'Upgrade', 'Suppress', 'SkipNotification', 'Clear', 'UnClear', 'UnSuppress', 'Resolve'

        self.header = None # goes in table dbo.sma_alert_history
        self.header_slack_markdown = None
        self.description = None
        self.slack_ts_value = None
        self.frequency_minutes = frequency_minutes
        self.affected_servers = None
        self.alert_method = None
        self.suppress_start_date_utc = None
        self.suppress_end_date_utc = None
        self.alert_job_name = None
        self.logger = None # logging tool
        self.logged_by = self.alert_job_name # alert logging job or person using portal
        self.exists = None
        self.generate_alert = None
        self.verbose = None
        self.sql_connection = None
        self.credential_manager_database = None
        self.alert_dashboard_url = None
        self.smtp_server = None
        self.smtp_server_port = None
        self.smtp_account_name = None
        self.alert_sender_email = None
        #self.alert_receiver_email = None
        self.alert_mail_subject = None
        self.alert_mail_body = None

        self.__alert_data_from_db = None
        self.__owner_team_details_from_db = None
        self.__slack_token = None
        self.__slack_bot = None
        self.__smtp_account_password = None
        self.__alert_owner_team_email = None
        self.__alert_owner_team_pagerduty_service_key = None
        self.__alert_owner_team_slack_channel = None
        self.__sqlmonitor_dashboard_url = None
        #self.__affected_servers_json = None
        self.action_dictionary = dict(Acknowledge = 'Acknowledged', Clear = 'Cleared', Suppress = 'Suppressed', Resolve = 'Resolved')
        # use this for comparision b/w alert severity for Upgrade scenario
        self.severity_dictionary = dict(Critical = 5, High = 4, Warning = 3, Medium = 2, Low = 1)

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
        if self.id is not None and self.verbose:
            self.logger.info(f"get alert for id '{self.id}' from database..")
        if self.id is None and self.verbose:
            self.logger.info(f"get alert for key '{self.alert_key}' from database..")

        cursor = self.sql_connection.cursor()

        if self.id is not None:
            sql_query = f"""
declare @_rows_affected int;
exec @_rows_affected = dbo.usp_get_alert_by_id @alert_id = ?;
select [rows_affected] = isnull(@_rows_affected,0);
    """
            cursor.execute(sql_query, self.id)
        else:
            sql_query = f"""
declare @_rows_affected int;
exec @_rows_affected = dbo.usp_get_active_alert_by_key @alert_key = ?;
select [rows_affected] = isnull(@_rows_affected,0);
    """
            cursor.execute(sql_query, self.alert_key)
        query_resultset = cursor.fetchall()
        cursor.nextset()
        row_count = (cursor.fetchall())[0][0]

        # set existence
        self.exists = bool(row_count)

        return query_resultset

    def initialize_data_from_db(self):
        # set self.exists if alert found
        self.__alert_data_from_db = self.fetch_data_from_db()
        if len(self.__alert_data_from_db) > 0 and len(self.alert_owner_team) == 0:
            self.alert_owner_team = self.__alert_data_from_db[0].alert_owner_team
        self.__owner_team_details_from_db = self.fetch_owner_team_details()

        if self.verbose and (self.exists or self.generate_alert):
            pt_owner_team_deatails_from_db = get_pretty_table(self.__owner_team_details_from_db)
            self.logger.info(f"Alert owner team '{self.alert_owner_team}' details..")
            print(pt_owner_team_deatails_from_db)

        if self.exists:
            if self.verbose:
                self.logger.info(f"initialize alert attributes from fetched data..")
                pt_alert_data_from_db = get_pretty_table(self.__alert_data_from_db)
                if self.id is not None:
                    self.logger.info(f"Alert data fetched from db for alert id '{self.id}'..")
                else:
                    self.logger.info(f"Alert data fetched from db for alert key '{self.alert_key}'..")
                print(pt_alert_data_from_db)

            if self.id is None:
                self.id = self.__alert_data_from_db[0].id
            if self.alert_key is None:
                self.alert_key = self.__alert_data_from_db[0].alert_key
            self.state = self.__alert_data_from_db[0].state
            self.severity = self.__alert_data_from_db[0].severity
            if self.slack_ts_value is None:
                self.slack_ts_value = self.__alert_data_from_db[0].slack_ts_value
            self.frequency_minutes = self.__alert_data_from_db[0].frequency_minutes

            self.alert_owner_team = self.__alert_data_from_db[0].alert_owner_team
            self.alert_method = self.__owner_team_details_from_db[0].alert_method

            self.suppress_start_date_utc = self.__alert_data_from_db[0].suppress_start_date_utc
            self.suppress_end_date_utc = self.__alert_data_from_db[0].suppress_end_date_utc
        else:
            self.alert_method = self.__owner_team_details_from_db[0].alert_method

        # set alert_owner_team related attributes
        self.__alert_owner_team_email = self.__owner_team_details_from_db[0].team_email
        self.__alert_owner_team_slack_channel = self.__owner_team_details_from_db[0].team_slack_channel
        self.__alert_owner_team_pagerduty_service_key = self.__owner_team_details_from_db[0].team_slack_channel

        # set attributes from dbo.sma_params
        self.credential_manager_database = get_sma_params(self.sql_connection, param_key='credential_manager_database')[0].param_value
        if self.alert_method == 'slack':
            self.__slack_bot = get_sma_params(self.sql_connection, param_key='dba_slack_bot')[0].param_value

        if self.alert_method == 'email':
            self.smtp_server = get_sma_params(self.sql_connection, param_key='smtp_server')[0].param_value
            self.smtp_server_port = get_sma_params(self.sql_connection, param_key='smtp_server_port')[0].param_value
            self.smtp_account_name = get_sma_params(self.sql_connection, param_key='smtp_account_name')[0].param_value
            self.alert_sender_email = get_sma_params(self.sql_connection, param_key='alert_sender_email')[0].param_value
            #self.alert_receiver_email = self.__alert_owner_team_email
            self.__smtp_account_password = get_sm_credential(self.sql_connection, self.credential_manager_database, 'smtp_account_password')

        self.alert_dashboard_url = get_sma_params(self.sql_connection, param_key='url_for_alerts_grafana_dashboard')[0].param_value
        if self.verbose:
            self.logger.info(f"self.alert_dashboard_url = '{self.alert_dashboard_url}'")

        # set attributes from credential manager
        if self.alert_method == 'slack':
            self.__slack_token = get_sm_credential(self.sql_connection, self.credential_manager_database, 'dba_slack_bot_token')
        if self.alert_method == 'pagerduty':
            self.__alert_owner_team_pagerduty_service_key = get_sm_credential(self.sql_connection, self.credential_manager_database, 'dba_pagerduty_service_key')

        # set action_to_take # 'No Action', 'Create', 'Acknowledge', 'Update', 'Upgrade', 'Suppress', 'SkipNotification', 'Clear', 'UnClear', 'UnSuppress', 'Resolve'
        if self.generate_alert is None:
            if self.verbose:
                self.logger.info(f"self.generate_alert is None. So no compute for self.action_to_take.")
                self.logger.info(f"Current self.action_to_take = {self.action_to_take}")
        elif self.exists is False and self.generate_alert is False:
            self.action_to_take = 'No Action'
        else:
            # set action_to_take only when its default
            if self.exists is False and self.generate_alert is True:
                self.action_to_take = 'Create'

            if self.exists and self.generate_alert is False:
                self.action_to_take = 'Clear'

            if self.exists and self.generate_alert:
                self.action_to_take = 'Update'

            if self.exists and self.suppress_start_date_utc is not None and self.suppress_end_date_utc is not None:
                now_utc = datetime.utcnow()
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

        logged_by = (self.logged_by if self.logged_by is not None else self.alert_job_name)
        if self.generate_alert is None and self.alert_job_name is not None:
            logged_by = self.alert_job_name

        query_params = dict(alert_key=self.alert_key, frequency_minutes=self.frequency_minutes, alert_owner_team=self.alert_owner_team,
                            state=self.state, action_to_take=self.action_to_take, severity=self.severity, logged_by=logged_by,
                            header=self.header, description=self.description, affected_servers=self.affected_servers
                            )
        query_resultset = call_usp_insert_sma_alert(self.sql_connection, self.logger, self.verbose, **query_params)

        if self.verbose:
            self.logger.info(f"result of call_usp_insert_sma_alert() is alert_id {query_resultset[0]} ")

        if len(query_resultset) > 0 and self.action_to_take == 'Create':
            self.logger.info(f"set self.id with '{query_resultset[0]}'")
            self.id = query_resultset[0]

            self.header = self.header.replace("Id#X", f"Id#{self.id}")
            if self.alert_method == 'slack':
                self.header_slack_markdown = self.header_slack_markdown.replace("Id#X", f"Id#{self.id}")
            if self.alert_method == 'email':
                self.alert_mail_subject = self.alert_mail_subject.replace("Id#X", f"Id#{self.id}")
                self.alert_mail_body = self.alert_mail_body.replace("Id#X", f"Id#{self.id}")

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

        alert_params = dict(
                        slack_token = self.__slack_token, 
                        slack_bot = self.__slack_bot,
                        slack_channel = self.__alert_owner_team_slack_channel,
                        slack_ts_value = self.slack_ts_value,
                        action_to_take = self.action_to_take,
                        logger = self.logger,
                        verbose = self.verbose,
                        alert_id = self.id,
                        alert_key = self.alert_key,
                        state = self.state,
                        severity = self.severity,
                        header = self.header,
                        header_slack_markdown = self.header_slack_markdown,
                        description = self.description
                    )
        if self.verbose:
            pt_alert_params = get_pretty_dictionary(alert_params)
            self.logger.info(f"self.__slack_token = '{self.__slack_token}'")
            self.logger.info(f"Parameters for call_usp_update_alert_slack_ts_value() function call =>")
            print(pt_alert_params.get_string(fields=["slack_token", "slack_bot", "slack_channel", "slack_ts_value", "action_to_take"]))
            print(pt_alert_params.get_string(fields=["header", "header_slack_markdown"]))

        self.slack_ts_value = send_slack_alert_notification(**alert_params)
        if self.verbose:
            self.logger.info(f"post send_slack_alert_notification() call, self.slack_ts_value = '{self.slack_ts_value}'")

        if self.action_to_take == 'Create':
            slack_ts_value_update = call_usp_update_alert_slack_ts_value(self.sql_connection, self.id, self.slack_ts_value, self.logger, self.verbose)
            if self.verbose:
                self.logger.info(f"slack_ts_value_update = {('Success' if slack_ts_value_update else 'Failure')}")

    def __send_email_alert_notification(self):
        if self.verbose:
            self.logger.info(f"executing SmaAlert.__send_email_alert_notification()..")

        alert_params = dict(
                        smtp_server = self.smtp_server,
                        smtp_server_port = self.smtp_server_port,
                        smtp_account_name = self.smtp_account_name,
                        smtp_account_password = self.__smtp_account_password,
                        logger = self.logger,
                        verbose = self.verbose,
                        alert_key = self.alert_key,
                        state = self.state,
                        severity = self.severity,
                        action_to_take = self.action_to_take,
                        alert_sender_email = self.alert_sender_email,
                        alert_receiver_email = self.__alert_owner_team_email,
                        alert_mail_subject = self.alert_mail_subject,
                        alert_mail_body = self.alert_mail_body
                    )
        if self.verbose:
            pt_alert_params = get_pretty_dictionary(alert_params)
            self.logger.info(f"Parameters for send_email_alert_notification() function call =>")
            print(pt_alert_params.get_string(fields=["smtp_server", "smtp_server_port", "smtp_account_name", "smtp_account_password", "action_to_take"]))
            print(pt_alert_params.get_string(fields=["alert_sender_email", "alert_receiver_email", "alert_mail_subject"]))
            self.logger.info(f"self.alert_mail_body => ")
            print(self.alert_mail_body)

        send_email_alert_notification(**alert_params)

    def __send_pagerduty_alert_notification(self):
        if self.verbose:
            self.logger.info(f"executing SmaAlert.__send_pagerduty_alert_notification()..")

    def __compute_action_to_take(self):
        if self.state == 'Cleared' and self.generate_alert is True and self.action_to_take != 'UnClear':
            self.action_to_take = 'UnClear'
        #if self.state == 'Suppressed' and self.generate_alert is True and self.action_to_take != 'UnClear':
            #self.action_to_take = 'UnClear'

    def take_required_action(self): # Reimplement this in child class if to override
        if self.verbose:
            self.logger.info(f"Recompute self.action_to_take using self.__compute_action_to_take()..")
        self.__compute_action_to_take()

        if self.verbose:
            self.logger.info(f"Perform '{self.action_to_take}' action under function take_required_action()..")
            self.__get_pretty_alert()

        if self.action_to_take != 'No Action':
            self.logger.info(f"self.state = {self.state}, self.action_to_take = {self.action_to_take} ")
            if self.action_to_take in ['Clear','Suppress','Resolve'] and self.state == self.action_dictionary[self.action_to_take]:
                self.logger.info(f"Alert already set to {self.action_dictionary[self.action_to_take]} state.")
            elif self.state == 'Resolved' and self.action_to_take not in ['update']:
                self.logger.info(f"Alert already set to {self.state} state. So cannot be alerted.")
            else:
                self.__call_usp_insert_sma_alert()
                self.__send_alert_notification()

    def state_colorizer(self, state:str):
        if state=='Critical':
            color = 'OrangeRed'
        elif state=='High':
            color = 'Tomato'
        elif state=='Warning':
            color = 'SandyBrown'
        elif state=='Medium':
            color = 'SandyBrown'
        elif state=='Low':
            color = 'PapayaWhip'
        else:
            color = 'PeachPuff'

        result = f'<span style="background-color:{color}">{state}</span>'
        return result

    def initialize_derived_attributes(self):
        ''' SYNOPSIS: Computes derived attributes like State, Severity, header, logger, description, affected_servers etc
        '''
        if self.verbose:
            self.logger.info(f"Inside SmaAlert.initialize_derived_attributes() method.")

        # Set alert state
        state = self.state
        if self.action_to_take in self.action_dictionary:
            state = self.action_dictionary[self.action_to_take]

        self.header = f"[{self.alert_key}] {state} by {self.logged_by}"

        #if self.alert_method == 'slack':
        self.header_slack_markdown = f"`{self.alert_key}` {state} by @{self.logged_by}"
        self.description = f"{self.header} from Slack"

    def get_pretty_data_size(self, size:float, unit:str='mb', precision:int=2):
        """_summary_

        Args:
            size (float): _description_
            unit (str, optional): _description_. Defaults to 'mb'.
            precision (int, optional): _description_. Defaults to 2.

        Returns:
            _type_: _description_

        Examples:
            pt.custom_format = { "free_memory_kb": lambda field, value: self.get_pretty_data_size(int(value),'kb') }
            pt.custom_format["threshold_kb"] = lambda field, value: self.get_pretty_data_size(int(value),'kb')
        """

        if size is None:
            return f"None"

        unit = unit.lower()
        suffixes=['b', 'kb','mb','gb','tb']
        suffixIndex = suffixes.index(unit)
        while size > 1024 and suffixIndex < (len(suffixes)-1):
            suffixIndex += 1 #increment the index of the suffix
            size = size/1024.0 #apply the division

        return "%.*f %s"%(precision,size,suffixes[suffixIndex])

    def get_pretty_time(self, time_value:int, time_unit:str='seconds'):
        """
        Converts the given time value to a more human-readable format (minutes, hours, days, or weeks).

        Args:
            time_value (float): The time value to convert.
            time_unit (str): The unit of the input time ('seconds', 'minutes', 'hours', 'days', or 'weeks').

        Returns:
            str: The time in a more readable format.

        Examples:
            pt.custom_format = { "ColumnName": lambda field, value: self.get_pretty_time(int(value),'minutes') }
            pt.custom_format["ColumnName"] = lambda field, value: self.get_pretty_time(int(value),'minutes')
        """

        if time_value is None:
            return f"None"

        # Conversion factors from the base unit (seconds)
        time_units_in_seconds = {
            'seconds': 1,
            'minutes': 60,
            'hours': 3600,
            'days': 86400,
            'weeks': 604800
        }

        # Validate time_unit
        if time_unit not in time_units_in_seconds:
            raise ValueError("Invalid time unit. Please use 'seconds', 'minutes', 'hours', 'days', or 'weeks'.")

        # Convert the input time value to seconds
        time_in_seconds = time_value * time_units_in_seconds[time_unit]

        # Define thresholds for different time units
        if time_in_seconds < 60:
            return f"{time_in_seconds:.2f} seconds"
        elif time_in_seconds < 3600:
            minutes = time_in_seconds / 60
            return f"{minutes:.2f} minutes"
        elif time_in_seconds < 86400:
            hours = time_in_seconds / 3600
            return f"{hours:.2f} hours"
        elif time_in_seconds < 604800:
            days = time_in_seconds / 86400
            return f"{days:.2f} days"
        else:
            weeks = time_in_seconds / 604800
            return f"{weeks:.2f} weeks"

    def get_pretty_date(self, my_datetime):
        return my_datetime.strftime("%Y-%m-%d %H:%M")
