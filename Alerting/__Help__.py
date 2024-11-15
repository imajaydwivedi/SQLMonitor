# Create Virtual Env
cd "E:\Github\SQLMonitor\Alerting"

E:\Github\SQLMonitor\Alerting>
python -m venv AlertEngineVenv

E:\Github\SQLMonitor\Alerting>
SQLMonitorVenv\Scripts\activate.bat

(SQLMonitorVenv) E:\Github\SQLMonitor\Alerting>
python E:\GitHub\SQLMonitor\Alerting\Run-SQLMonitorAlertEngineWebServer.py

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

# Scheduler
https://stackoverflow.com/a/38501429/4449743
pip install apscheduler

# ngrok for testing web server
https://ngrok.com/download

ngrok http --url=gratefully-easy-ewe.ngrok-free.app 5000

https://api.slack.com/apps/A04LG3JUY4W/event-subscriptions?
  https://gratefully-easy-ewe.ngrok-free.app/slack/events

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


# Deploy First Flask App on IIS
  # https://www.youtube.com/watch?v=Q4AaFNX6LBY
  # Virtual Env in windows
cd "E:\Github\Flask\FirstFlaskWebApp"

E:\Github\Flask\FirstFlaskWebApp>
python -m venv FlaskWebVenv

FlaskWebVenv\Scripts\activate.bat

(FlaskWebVenv) E:\Github\Flask\FirstFlaskWebApp>
python flaskIIS.py

pip install flask

pip install wfastcgi

# By default, [FastCGIModule] is not enabled in IIS. To enable, following instructions from chat GPT
  # Search for text "how to enable FastCgiModule in IIS"
  Server Manager > Add Roles and Features > Server Roles > Web Server (IIS) > Web Server > Application Development > CGI

# Go get FastCGI executable path, go to app directory. Activate VEnv. Enable wfastcgi. As output, we get path
cd "E:\Github\Flask\FirstFlaskWebApp"
wfastcgi-enable

  (FlaskWebVenv) E:\Github\Flask\FirstFlaskWebApp>wfastcgi-enable
  Applied configuration changes to section "system.webServer/fastCgi" for "MACHINE/WEBROOT/APPHOST" at configuration commit path "MACHINE/WEBROOT/APPHOST"
  "E:\Github\Flask\FirstFlaskWebApp\FlaskWebVenv\Scripts\python.exe|E:\Github\Flask\FirstFlaskWebApp\FlaskWebVenv\Lib\site-packages\wfastcgi.py" can now be used as a FastCGI script processor

  (FlaskWebVenv) E:\Github\Flask\FirstFlaskWebApp>










