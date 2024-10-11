'''
# Get DBA Params
if 'Get DBA Params' == 'Get DBA Params':
    logger.info(f"Query table dbo.sma_params..")
    sma_params_records = get_sma_params(sql_connection=cnxn, param_key='dba_slack_channel_id')

    #logger.info(f"get PrettyTable..")
    #pt = get_pretty_table(sma_params_records)
    #logger.info(f"get pandas dataframe..")
    #df = get_pandas_dataframe(sma_params_records, index_col='param_key')

    # Extract dynamic parameters from inventory
    #logger.info(f"Get parameters from dbo.sma_params..")
    #dba_slack_channel_id = df[df.param_key=='dba_slack_channel_id'].iloc[0]['param_value']
    #dba_slack_channel_id = df.loc['dba_slack_channel_id','param_value']
    #dba_slack_channel_id = df.at['dba_slack_channel_id','param_value']

    #logger.info(f"dba_slack_channel_id = '{dba_slack_channel_id}'")

    #print(pt)
    #print(df)
    #print(f'dba_slack_channel_id => {dba_slack_channel_id}')
'''

'''
# Get Alert Owner Team Details
if 'Get Alert Owner Team Details' == 'Get Alert Owner Team Details':
    logger.info(f"Query table dbo.sma_oncall_teams..")
    oncall_teams_records = get_oncall_teams(sql_connection=cnxn, team_name='DBA')

    #logger.info(f"get PrettyTable..")
    pt_oncall_teams_records = get_pretty_table(oncall_teams_records)
    #logger.info(f"get pandas dataframe..")
    df_oncall_teams_records = get_pandas_dataframe(oncall_teams_records, index_col='team_name')

    # Extract dynamic parameters from inventory
    #logger.info(f"Get parameters from dbo.sma_params..")
    #dba_slack_channel_id = df[df.param_key=='dba_slack_channel_id'].iloc[0]['param_value']
    #dba_slack_channel_id = df.loc['dba_slack_channel_id','param_value']
    #oncall_team_slack_channel_id = df_oncall_teams_records.at[alert_owner_team,'team_slack_channel']

    #logger.info(f"oncall_team_slack_channel_id = '{oncall_team_slack_channel_id}'")

    if verbose:
        print(pt_oncall_teams_records)
    #print(df_oncall_teams_records)
'''