import pyodbc
from SmaAlertPackage.CommonFunctions.get_pandas_dataframe import get_pandas_dataframe
from SmaAlertPackage.CommonFunctions.get_oncall_teams import get_oncall_teams
from SmaAlertPackage.CommonFunctions.get_pretty_table import get_pretty_table
from SmaAlertPackage.CommonFunctions.get_pretty_dictionary import get_pretty_dictionary
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
        self.logger = logger
        self.header = header
        self.description = description
        self.slack_ts_value = slack_ts_value
        self.frequency_minutes = frequency_minutes
        self.affected_servers = affected_servers
        self.alert_method = alert_method
        self.suppress_start_time_utc = None
        self.suppress_end_time_utc = None
        self.alert_job_name = None
        self.exists = None
        self.generate_alert = None
        self.action_to_take = 'No Action' # 'No Action', 'Create', 'Update', 'Upgrade', 'SkipNotification', 'Clear'
        self.verbose = verbose

        self.__alert_data_from_db = None
        self.__owner_team_details_from_db = None
        #self.__affected_servers_json = None

    def __get_obj_dict(self):
        obj_dict = dict(alert_id = self.id,
                        alert_key = self.alert_key,
                        alert_owner_team = self.alert_owner_team,
                        state = self.state,
                        severity = self.severity,
                        #logger = self.logger,
                        header = self.header,
                        description = self.description,
                        slack_ts_value = self.slack_ts_value,
                        frequency_minutes = self.frequency_minutes,
                        #affected_servers = self.affected_servers,
                        alert_method = self.alert_method,
                        suppress_start_time_utc = self.suppress_end_time_utc,
                        suppress_end_time_utc = self.suppress_end_time_utc,
                        alert_job_name = self.alert_job_name,
                        exists = self.exists,
                        generate_alert = self.generate_alert,
                        action_to_take = self.action_to_take,
                        verbose = self.verbose
                    )
        return obj_dict

    def __get_pretty_object(self):
        pt = get_pretty_dictionary(self.__get_obj_dict())
        print(pt.get_string(fields=["alert_id", "alert_key", "alert_owner_team", "state", "severity", "frequency_minutes", "slack_ts_value", "alert_method", "alert_job_name"]))
        print(pt.get_string(fields=["action_to_take", "exists", "generate_alert", "verbose", "suppress_start_time_utc", "suppress_end_time_utc", "header", "description"]))

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
        self.__alert_data_from_db = self.fetch_data_from_db(sql_connection)
        self.__owner_team_details_from_db = self.fetch_owner_team_details(sql_connection)

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

            self.suppress_start_time_utc = self.__alert_data_from_db[0].suppress_start_time_utc
            self.suppress_end_time_utc = self.__alert_data_from_db[0].suppress_end_time_utc
        else:
            self.alert_method = self.__owner_team_details_from_db[0].alert_method

        # set action_to_take -- 'No Action', 'Create', 'Clear', 'SkipNotification', 'Update', 'Upgrade'
        if self.exists is False and self.generate_alert is False:
            self.action_to_take = 'No Action'
        else:
            if self.exists is False and self.generate_alert is True:
                self.action_to_take = 'Create'

            if self.exists and self.generate_alert is False:
                self.action_to_take = 'Clear'

            if self.exists and len(self.suppress_start_time_utc) > 0 and len(self.suppress_end_time_utc) > 0:
                now_utc = datetime.now(timezone.utc)
                if self.suppress_start_time_utc < now_utc < self.suppress_end_time_utc:
                    self.action_to_take = 'SkipNotification'

            if self.exists and self.action_to_take not in ['No Action', 'Create', 'Upgrade', 'SkipNotification', 'Clear']:
                self.action_to_take = 'Update'

        return self.exists

    def fetch_owner_team_details(self,sql_connection):
        if self.verbose:
            self.logger.info(f"fetch alert owner team [{self.alert_owner_team}] details from database..")

        query_resultset = get_oncall_teams(sql_connection, self.alert_owner_team)

        return query_resultset

    def take_required_action(self):
        if self.verbose:
            self.logger.info(f"Perform '{self.action_to_take}' action under function take_required_action()..")
            self.__get_pretty_object()
        pass


