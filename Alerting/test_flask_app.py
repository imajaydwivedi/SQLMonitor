from flask import Flask, jsonify, request
import time
import json
import hmac
import hashlib
import requests
import os

app = Flask(__name__)

# Use Set for windows & export for linux or mac
slack_bot_token = os.getenv("SLACK_BOT_TOKEN")
slack_signing_secret = os.getenv("SLACK_SIGNING_SECRET")

print(f"slack_bot_token = {slack_bot_token}")
print(f"slack_signing_secret = {slack_signing_secret}")

send_message_url = "https://slack.com/api/chat.postMessage"
open_channel_url = "https://slack.com/api/conversations.open"

@app.route("/")
def welcome():
    return "Welcome to flask app", 200

@app.route("/health-check")
def health_check():
    return (jsonify({"health": "server is up and running"}))


@app.route("/slack/events", methods=["POST"])
def consume_event():
    if message_secure(request):
        print("log: message is secure")
        payload = request.get_json()

        # Auth Check
        if "url_verification" == payload.get("type"):
            return jsonify({"challenge": request.get_json().get("challenge")})

        # Not talking to self
        event = payload.get("event")
        if ("bot_id") in event:
            print("log: we dont want to talk to self")
            return jsonify({"challenge": request.get_json().get("challenge")})

        # Respond to user
        type = event.get("type")
        text = event.get("text")
        print("log: type: " + str(type))
        print("log: text: " + str(text))

        headers = {}
        headers["Authorization"] = "Bearer " + slack_bot_token
        headers["Content-type"] = "application/json"

        if type == "app_mention":
            if "secret" in text:
                print("log: should respond in dm for secret")
                # Get channel for dm
                user_id = event.get("user")
                channel_payload = {}
                channel_payload["users"] = user_id
                channel_response = requests.post(open_channel_url, headers=headers, data=json.dumps(channel_payload))
                print("log: open channel call response code: " + str(channel_response.status_code))
                print("log: open channel call payload: " + str(channel_response.json()))
                channel_data = channel_response.json().get("channel")
                dm_channel_id = channel_data.get("id")

                message_payload = {}
                message_payload["channel"] = dm_channel_id
                message_payload["text"] = "I would love to hear a secret, but we should talk in the dms"
                message_response = requests.post(send_message_url, headers=headers, data=json.dumps(message_payload))
                print("log: message call response code: " + str(message_response.status_code))
                print("log: message call payload: " + str(message_response.json()))

            else:
                print("log: should respond in public channel")
                channel_id = event.get("channel")
                message_payload = {}
                message_payload["channel"] = channel_id
                message_payload["text"] = "I heard my name"
                message_response = requests.post(send_message_url, headers=headers, data=json.dumps(message_payload))
                print("log: message call response code: " + str(message_response.status_code))
                print("log: message call payload: " + str(message_response.json()))

        elif type == "message":
            print("log: should respond in same dm message thread")
            channel_id = event.get("channel")
            message_payload = {}
            message_payload["channel"] = channel_id
            message_payload["text"] = "I love to send messages"
            message_response = requests.post(send_message_url, headers=headers, data=json.dumps(message_payload))
            print("log: message call response code: " + str(message_response.status_code))
            print("log: message call payload: " + str(message_response.json()))

        return jsonify({"challenge": request.get_json().get("challenge")})

    else:
        print("log: message is not secure")
        return jsonify({"challenge": None})


def message_secure(request):
    request_body = request.get_json()
    timestamp = request.headers.get("X-Slack-Request-Timestamp")

    print("log: request body: " + str(request_body))
    print("log: timestamp: " + str(timestamp))

    if abs(time.time() - float(timestamp)) > 60 * 5:
        print("log: timestamp outside of range, likely an attack")
        return False

    sig_basestring = 'v0:' + timestamp + ':' + request.get_data().decode("utf-8")
    print("log: sig_basestring: " + sig_basestring)

    key_bytes = bytearray()
    key_bytes.extend(map(ord, slack_signing_secret))

    message_bytes = bytearray()
    message_bytes.extend(map(ord, sig_basestring))

    h = hmac.new(key_bytes, message_bytes, hashlib.sha256)
    my_signature = "v0=" + h.hexdigest()
    slack_signature = request.headers.get("X-Slack-Signature")

    print("log: my_signature: " + my_signature)
    print("log: slack_signature: " + slack_signature)

    if hmac.compare_digest(my_signature, slack_signature):
        print("log: signatures match")
        return True

    print("log: signatures do not match")
    return False


if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000, use_reloader=False, threaded=True)