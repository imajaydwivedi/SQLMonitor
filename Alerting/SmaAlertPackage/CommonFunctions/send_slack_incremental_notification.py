# slack_sdk WebClient functionalities
  # https://tools.slack.dev/python-slack-sdk/web/

# How to send message to a Slack channel
  # https://www.datacamp.com/tutorial/how-to-send-slack-messages-with-python
	# https://stackoverflow.com/a/71973904/4449743

# Python Slack SDK - Web Client
  # https://tools.slack.dev/python-slack-sdk/web

# Formatting with rich text
  # https://api.slack.com/tutorials/tracks/rich-text-tutorial

# Block Kit Builder
  # https://app.slack.com/block-kit-builder

# Creating interactive messages
  # https://api.slack.com/messaging/interactivity

# Youtube Playlist -> Python Slack Bot - https://www.youtube.com/playlist?list=PLzMcBGfZo4-kqyzTzJWCV6lyK-ZMYECDc

import requests
import os
import time
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError

def send_slack_incremental_notification(slack_token:str, slack_channel:str, thread_header:str=None, thread_messages=None, slack_ts_value:str=None, logger=None, verbose:bool=False):

    is_initial_slack_message = True
    if thread_header is None or thread_header == "":
        is_initial_slack_message = False

        if isinstance(thread_messages, str):
            thread_messages = [thread_messages]
        elif isinstance(thread_messages, dict):
            thread_messages = [thread_messages]
        elif not isinstance(thread_messages, list):
            raise TypeError("thread_messages must be a string or a list of strings")

        if slack_ts_value is None or slack_ts_value == "":
            raise TypeError("slack_ts_value parameter is must for slack thread_messages")

    if not slack_token or not slack_channel:
        print("⚠️ slack_token and slack_channel are mandatory parameters for Slack messages.")
        return

    headers = {
        "Authorization": f"Bearer {slack_token}",
        "Content-Type": "application/json"
    }

    # Set up a WebClient with the Slack OAuth token
    client = WebClient(token=slack_token)

    # Send initial Slack Message, and return slack_ts_value
    if is_initial_slack_message:
        # Post initial header message via chat.postMessage
        header_payload = {
            "channel": slack_channel,
            "text": thread_header,
            "mrkdwn": True
        }

        response = requests.post("https://slack.com/api/chat.postMessage", headers=headers, json=header_payload)
        if response.status_code != 200 or not response.json().get("ok"):
            raise Exception(f"❌ Failed to send header: {response.status_code} - {response.text}")
            return -1

        slack_ts = response.json().get("ts")
        return slack_ts
    else:
        # Post each message in thread
        for msg in thread_messages:
            send_snippet:bool = False

            if isinstance(msg, dict):
                if 'type' in msg:
                    if msg['type'] == 'snippet':
                        send_snippet = True

            if send_snippet:
                # if verbose:
                #     logger.info(f"msg.content => {msg['content']}")
                #     logger.info(f"msg.content type => {type(msg['content'])}")

                thread_response = client.files_upload_v2(
                        channel=slack_channel,
                        thread_ts=slack_ts_value,
                        filename=msg['filename'],
                        # title=msg['title'],
                        content=msg['content'],
                        initial_comment=msg['initial_comment'],
                    )
            else:
                thread_payload = {
                    "channel": slack_channel,
                    "text": msg,
                    "thread_ts": slack_ts_value,
                    "mrkdwn": True
                }

                thread_response = requests.post("https://slack.com/api/chat.postMessage", headers=headers, json=thread_payload)

            # print(thread_response)

            # For requests.Response
            if hasattr(thread_response, "status_code"):
                if thread_response.status_code != 200:
                    print(f"⚠️ Failed to send thread message: {thread_response.text}")
                else:
                    pass
                    # print("✅ Sent thread message.")

            # For slack_sdk.WebClient response
            elif isinstance(thread_response, dict) or hasattr(thread_response, "get"):
                if not thread_response.get("ok", False):
                    print(f"⚠️ Failed to send thread message: {thread_response}")
                else:
                    pass
                    # print("✅ Sent thread message.")

            else:
                print(f"⚠️ Unknown response type: {thread_response}")

            time.sleep(1)

        return 0