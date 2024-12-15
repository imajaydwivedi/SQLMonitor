# Deploy First Flask App on IIS
  # https://www.youtube.com/watch?v=Q4AaFNX6LBY
# Slack Bot Tutorial
  # https://www.youtube.com/watch?v=uP2T22AXAuA

  # Virtual Env in windows
# Create Virtual Env
cd "E:\Github\SQLMonitor\Alerting"

E:\Github\SQLMonitor\Alerting>
python -m venv AlertEngineVenv

E:\Github\SQLMonitor\Alerting>
AlertEngineVenv\Scripts\activate.bat

(AlertEngineVenv) E:\Github\SQLMonitor\Alerting>
python E:\GitHub\SQLMonitor\Alerting\SQLMonitorAlertEngineApp.py

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

personal website -> https://alertengine.ajaydwivedi.com

# sql agent
ngrok http --url=skilled-externally-redfish.ngrok-free.app 5000

# Slack evnets via Personal Account
https://api.slack.com/apps/A04LG3JUY4W/event-subscriptions?
  https://gratefully-easy-ewe.ngrok-free.app/slack/events
  https://alertengine.ajaydwivedi.com/slack/events

https://api.slack.com/apps/A04LG3JUY4W/interactive-messages?
  https://gratefully-easy-ewe.ngrok-free.app/slack/interactive-endpoint
  https://alertengine.ajaydwivedi.com/slack/interactive-endpoint

https://api.slack.com/apps/A04LG3JUY4W/slash-commands?
  https://gratefully-easy-ewe.ngrok-free.app/alerts
  https://alertengine.ajaydwivedi.com/alerts


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
curl -X POST https://alertengine.ajaydwivedi.com:5000/slack/events -d '{"type": "url_verification", "challenge": "test"}' -H "Content-Type: application/json"

curl -X POST https://alertengine.ajaydwivedi.com:5000/slack/events \
    -H "Content-Type: application/json" \
    -d '{"token": "Jhj5dZrVaK7ZwHHjRyZWjbDl", "type": "url_verification", "challenge": "3eZbrw1aBm2rZgRNFdxV2595E9CY3gmdALWMmHkvFXO7tYXAYM8P"}'


# For Slack Bot (slackbot)
https://medium.com/developer-student-clubs-tiet/how-to-build-your-first-slack-bot-in-2020-with-python-flask-using-the-slack-events-api-4b20ae7b4f86

SQLMonitor Bot -> https://api.slack.com/apps/A04LG3JUY4W/event-subscriptions?

set SLACK_BOT_TOKEN=YOUR-BOT-TOKEN-HERE
set SLACK_SIGNING_SECRET=your-slack-signing-secret-here
set SLACK_VERFIFICATION_TOKEN=your-slack-verification-token


Error Message =>
-------------
ImportError: libodbc.so.2: cannot open shared object file: No such file or directory

Resolution =>
# Install packages
sudo apt update
sudo apt install unixodbc unixodbc-dev

# verify
ls -l /usr/lib/x86_64-linux-gnu/libodbc.so*

----------------

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


# Deploy a Python Flask Application in IIS Server and run on machine IP address
  # https://medium.com/@dpralay07/deploy-a-python-flask-application-in-iis-server-and-run-on-machine-ip-address-ddb81df8edf3


# Deploy in Windows Services
ChatGpt.com search =>
create a service on windows server that runs following command "python E:\GitHub\SQLMonitor\Alerting\SQLMonitorAlertEngineApp.py --inventory_server localhost". Since its a service, it should appear in services.msc. And should autostart with server.

# install module
pip install flask pywin32

# Install the service using Service Script "SQLMonitor\Alerting\SQLMonitorAlertEngineService.py"

cd E:\Github\SQLMonitor\Alerting
python SQLMonitorAlertEngineService.py install

  Installing service SQLMonitorAlertEngineService
  moving host exe 'C:\Program Files\Python312\Lib\site-packages\win32\pythonservice.exe' -> 'C:\Program Files\Python312\pythonservice.exe'
  copying helper dll 'C:\Program Files\Python312\Lib\site-packages\pywin32_system32\pywintypes312.dll' -> 'C:\Program Files\Python312\pywintypes312.dll'
  Service installed

# Set the Service to Auto-Start
sc config SQLMonitorAlertEngine start=auto

# Start the service
Get-Service SQLMonitorAlertEngine
Get-Service SQLMonitorAlertEngine | Restart-Service

# Cleanup
sc stop SQLMonitorAlertEngine
sc delete SQLMonitorAlertEngine

How to Run Python Script as a Service Windows & Linux
https://www.youtube.com/watch?v=pLqtenLVKsg


