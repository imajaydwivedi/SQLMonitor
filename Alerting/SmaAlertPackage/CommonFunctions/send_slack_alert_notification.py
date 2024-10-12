# How to send message to a Slack channel
  # https://www.datacamp.com/tutorial/how-to-send-slack-messages-with-python
	# https://stackoverflow.com/a/71973904/4449743

# Python Slack SDK - Web Client
  # https://tools.slack.dev/python-slack-sdk/web

# Formatting with rich text
  # https://api.slack.com/tutorials/tracks/rich-text-tutorial

# Block Kit Builder
  # https://app.slack.com/block-kit-builder

from datetime import datetime
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError

def send_slack_alert_notification(slack_token:str, slack_bot:str, slack_channel:str, action_to_take:str, logger:None, slack_ts_value:str=None, verbose:bool=False, **kwargs):
    if verbose:
        logger.info(f"Extracting **kwargs inside send_slack_alert_notification()..")

    alert_key = kwargs['alert_key']
    alert_state = kwargs['state']
    alert_severity = kwargs['severity']
    alert_header = kwargs['header']
    alert_description = kwargs['description']
    
    # Set up a WebClient with the Slack OAuth token
    client = WebClient(token=slack_token)
    
    # Send one liner alert message
    if slack_ts_value is None or len(slack_ts_value) == 0:
        if verbose:
            logger.info(f"slack_ts_value is None, so send one liner alert message first..")
        response = client.chat_postMessage(
            channel = slack_channel,
            text = alert_header,
            username = slack_bot
        )
        slack_ts_value = response['ts']

        if verbose:
            logger.info(f"slack_ts_value '{slack_ts_value}' is generated.")

    # Add to alert message thread with alert description as text snippet
    if slack_ts_value is not None and action_to_take in ['Create','Update', 'Upgrade']:
        response = client.files_upload_v2(
            channel = slack_channel,
            thread_ts = slack_ts_value,
            filename = alert_header,
            content = alert_description,
        )

    # Add alert thread one liner reply
    if slack_ts_value is not None and action_to_take in ['SkipNotification','Clear']:
        response = client.chat_postMessage(
            channel = slack_channel,
            thread_ts = slack_ts_value,
            text = alert_header
        )
    
    return slack_ts_value

    