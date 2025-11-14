import requests
import os
import time
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError

def send_slack_allinone_notification(thread_header, thread_messages):
    if isinstance(thread_messages, str):
        thread_messages = [thread_messages]
    elif isinstance(thread_messages, dict):
        thread_messages = [thread_messages]
    elif not isinstance(thread_messages, list):
        raise TypeError("thread_messages must be a string or a list of strings")

    # Retrieve environmental variables
    slack_target = os.getenv("SLACK_TARGET")
    slack_token = os.getenv("SLACK_BOT_TOKEN")  # Must start with xoxb-

    if slack_target == 'PGDBA':
        slack_channel = os.getenv("SLACK_PGDBA_CHANNEL_ID")
    elif slack_target == 'DBA':
        slack_channel = os.getenv("SLACK_DBA_CHANNEL_ID")
    else:
        slack_channel = os.getenv("SLACK_CHANNEL_ID")


    if not slack_token or not slack_channel:
        print("⚠️ SLACK_TARGET, SLACK_BOT_TOKEN, SLACK_PGDBA_CHANNEL_ID and SLACK_DBA_CHANNEL_ID must be set for threaded Slack messages.")
        return

    headers = {
        "Authorization": f"Bearer {slack_token}",
        "Content-Type": "application/json"
    }

    # Set up a WebClient with the Slack OAuth token
    client = WebClient(token=slack_token)

    # 1. Post initial header message via chat.postMessage
    header_payload = {
        "channel": slack_channel,
        "text": thread_header,
        "mrkdwn": True
    }

    response = requests.post("https://slack.com/api/chat.postMessage", headers=headers, json=header_payload)
    if response.status_code != 200 or not response.json().get("ok"):
        print(f"❌ Failed to send header: {response.status_code} - {response.text}")
        return

    slack_ts = response.json().get("ts")

    # 2. Post each message in thread
    for msg in thread_messages:
        send_snippet:bool = False

        if isinstance(msg, dict):
            if 'type' in msg:
                if msg['type'] == 'snippet':
                    send_snippet = True

        if send_snippet:
            # print(msg)
            thread_response = client.files_upload_v2(
                    channel=slack_channel,
                    thread_ts=slack_ts,
                    filename=msg['filename'],
                    # title=msg['title'],
                    content=msg['content'],
                    initial_comment=msg['initial_comment'],
                )
        else:
            thread_payload = {
                "channel": slack_channel,
                "text": msg,
                "thread_ts": slack_ts,
                "mrkdwn": True
            }

            thread_response = requests.post("https://slack.com/api/chat.postMessage", headers=headers, json=thread_payload)

        # print(thread_response)

        # For requests.Response
        if hasattr(thread_response, "status_code"):
            if thread_response.status_code != 200:
                print(f"⚠️ Failed to send thread message: {thread_response.text}")
            else:
                print("✅ Sent thread message.")

        # For slack_sdk.WebClient response
        elif isinstance(thread_response, dict) or hasattr(thread_response, "get"):
            if not thread_response.get("ok", False):
                print(f"⚠️ Failed to send thread message: {thread_response}")
            else:
                print("✅ Sent thread message.")

        else:
            print(f"⚠️ Unknown response type: {thread_response}")

        time.sleep(1)