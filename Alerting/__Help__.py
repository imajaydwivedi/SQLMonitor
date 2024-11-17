# Deploy First Flask App on IIS
  # https://www.youtube.com/watch?v=Q4AaFNX6LBY
  # Virtual Env in windows
# Create Virtual Env
cd "E:\Github\SQLMonitor\Alerting"

E:\Github\SQLMonitor\Alerting>
python -m venv AlertEngineVenv

E:\Github\SQLMonitor\Alerting>
AlertEngineVenv\Scripts\activate.bat

(AlertEngineVenv) E:\Github\SQLMonitor\Alerting>
python E:\GitHub\SQLMonitor\Alerting\Run-SQLMonitorAlertEngineWebServer.py

# To install module for all users
pip install slackeventsapi --upgrade --target "C:\Program Files\Python312\Lib\site-packages"

# pyodbc module for SQL Connection
pip install pyodbc

# module to print pretty tables
pip install prettytable

# module to work with DataFrame
pip install pandas

# Install module to send slack messages
pip install slack_sdk

# Install Flask required for Web Server
pip install flask

# module to work with slack events
pip install slackeventsapi

# Scheduler - https://stackoverflow.com/a/38501429/4449743
pip install apscheduler

# Webserver deployment
pip install wfastcgi

# psutil for identifying caller
pip install psutil

# pure python web server
pip install waitress

# Handling Packages => requirements.txt
  # Generate
pip freeze > requirements.txt

  # Use
pip install -r requirements.txt



# for SSL Certificate, use NGinx Proxy
  # https://github.com/imajaydwivedi/SqlServerLab/blob/dev/Other-Scripts/etc_nginx_nginx.conf

# ngrok for testing web server
https://ngrok.com/download

# personal
ngrok http --url=gratefully-easy-ewe.ngrok-free.app 5000
Website -> https://gratefully-easy-ewe.ngrok-free.app/

# sql agent
ngrok http --url=skilled-externally-redfish.ngrok-free.app 5000

# Slack evnets via Personal Account
https://api.slack.com/apps/A04LG3JUY4W/event-subscriptions?
  https://gratefully-easy-ewe.ngrok-free.app/slack/events
  https://sqlmonitor.ajaydwivedi.com:5000/slack/events

https://api.slack.com/apps/A04LG3JUY4W/interactive-messages?
  https://gratefully-easy-ewe.ngrok-free.app/slack/interactive-endpoint

https://api.slack.com/apps/A04LG3JUY4W/slash-commands?
  https://gratefully-easy-ewe.ngrok-free.app/alerts


# Waitress Web Server
https://github.com/Pylons/waitress

# Virtual Env for Web Server Deployment
  # https://stackoverflow.com/a/47816344/4449743
c:\Python312\Scripts>virtualenv.exe flask-app-env
c:\Python312\Scripts>
c:\Python312\Scripts>flask-app-env\Scripts\activate.bat
(flask-app-env) c:\Python312\Scripts>

# Flask App Deployment in Windows (Apache-Server, mod_wsgi)
  # https://thilinamad.medium.com/flask-app-deployment-in-windows-apache-server-mod-wsgi-82e1cfeeb2ed


# JSON Formatter
https://jsonformatter.curiousconcept.com/#

# How to Deploy a Flask App to a Linux Server
https://www.youtube.com/watch?v=YFBRVJPhDGY


# By default, [FastCGIModule] is not enabled in IIS. To enable, following instructions from chat GPT
  # Search for text "how to enable FastCgiModule in IIS"
  Server Manager > Add Roles and Features > Server Roles > Web Server (IIS) > Web Server > Application Development > CGI

# Go get FastCGI executable path, go to app directory. Activate VEnv. Enable wfastcgi. As output, we get path
(AlertEngineVenv) E:\Github\SQLMonitor\Alerting>
wfastcgi-enable

Applied configuration changes to section "system.webServer/fastCgi" for "MACHINE/WEBROOT/APPHOST" at configuration commit path "MACHINE/WEBROOT/APPHOST"
"E:\Github\SQLMonitor\Alerting\AlertEngineVenv\Scripts\python.exe|E:\Github\SQLMonitor\Alerting\AlertEngineVenv\Lib\site-packages\wfastcgi.py" can now be used as a FastCGI script processor

# Run IIS Server with custom Service Account
  # Search in chatgpt.com for text "run IIS website with different service account"

# For SSL Certificate, merge OpenSSL Certificate & Key (Optional)
openssl pkcs12 -export -out certificate.pfx -inkey privkey.pem -in fullchain.pem


# Run ngrok as Part of the IIS Website Startup
#To run ngrok throught windows Task Scheduler
Account -> Lab\SQLService

Open cmd.exe as different user. Use above user.

#Then add auto token. Statement should be similar to below
ngrok config add-authtoken somegarbagevalueforreplacementofauthtoken

#In task manager, create a task -
Program -> "C:\Program Files\Ngrok\ngrok.exe"
Argument -> http --url=gratefully-easy-ewe.ngrok-free.app 5000

Triggers -> At startup, Daily every 1 hour


# For slack verification
curl -X POST https://sqlmonitor.ajaydwivedi.com:5000/slack/events -d '{"type": "url_verification", "challenge": "test"}' -H "Content-Type: application/json"

curl -X POST https://sqlmonitor.ajaydwivedi.com:5000/slack/events \
    -H "Content-Type: application/json" \
    -d '{"token": "Jhj5dZrVaK7ZwHHjRyZWjbDl", "type": "url_verification", "challenge": "3eZbrw1aBm2rZgRNFdxV2595E9CY3gmdALWMmHkvFXO7tYXAYM8P"}'


# For Slack Bot (slackbot)
https://medium.com/developer-student-clubs-tiet/how-to-build-your-first-slack-bot-in-2020-with-python-flask-using-the-slack-events-api-4b20ae7b4f86

SQLMonitor Bot -> https://api.slack.com/apps/A04LG3JUY4W/event-subscriptions?

set SLACK_BOT_TOKEN=YOUR-BOT-TOKEN-HERE
set SLACK_SIGNING_SECRET=your-slack-signing-secret-here
set SLACK_VERFIFICATION_TOKEN=your-slack-verification-token


# Common Error in CommonFunctions\send_slack_alert_notification()
Error Message =>
-------------
slack_sdk.errors.SlackApiError: The request to the Slack API failed. (url: https://www.slack.com/api/files.completeUploadExternal)
The server responded with: {'ok': False, 'error': 'not_in_channel'}
  
Resolution =>  
----------------
Add the slack bot @SQLMonitor into slack channel #sqlmonitor-alert.
Just tag @SQLMonitor in #sqlmontor-alert channel. It would pop up asking whether you want to add SQLMonitor to this channel. Say Yes.

/home/ajaydwivedi/mysite/flask_app.py

ajaydwivedi.pythonanywhere.com





