# [Setup AI Agent for Databases](https://learning.oreilly.com/videos/mastering-ai-agents)

## Setup virtual env
```
cd ~/GitHub/SQLMonitor/AI-Agent

# create virtual env named "venv"
python -m venv venv

# activate venv
source venv/bin/activate

# install requirements
pip install -r requirements.txt

# if installed something manually, then generate a temp requirements_temp.txt file, and copy the modules in original requirements.txt
pip freeze > requirements_temp.txt

# deactivate venv
deactivate


```

## Test Slack Message using Webhook URL

```
curl -X POST -H 'Content-type: application/json' --data '{"text":"Hello, World!"}' $SLACK_WEBHOOK_URL_AIAGENT

```

## Print OPENAI Key
```
echo $OPENAI_API_KEY_NAME
echo $OPENAI_API_KEY_SECRET
echo $OLLAMA_API_KEY
```