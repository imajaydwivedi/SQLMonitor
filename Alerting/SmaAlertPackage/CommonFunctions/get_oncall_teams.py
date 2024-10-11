import pyodbc

def get_oncall_teams(sql_connection, team_name = ''):
    cursor = sql_connection.cursor()

    sql_get_oncall_teams = f"""
declare @sql nvarchar(max);
declare @params nvarchar(max);

declare @team_name varchar(125);
set @team_name = ?;

set @params = N'@team_name varchar(125)';
set @sql = '
select  team_name, team_lead_email, team_email, team_lead_slack_account, team_slack_channel, 
        pagerduty_service_key, alert_method
from dbo.sma_oncall_teams t
where 1=1
{'--' if team_name=='' else ''}and t.team_name = @team_name;
';

exec sp_executesql @sql, @params, @team_name;
"""
    cursor.execute(sql_get_oncall_teams, team_name)
    query_resultset = cursor.fetchall()

    return query_resultset

