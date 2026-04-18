# AI Agent

The `AI-Agent/` folder ships a set of **LangChain + LLM** agents that sit on top of the inventory `DBA` database. You ask natural-language questions (&ldquo;which instances are blocking right now?&rdquo;, &ldquo;top waits on AgHost-1B last 24h&rdquo;) and the agent translates them into T-SQL, runs them against the inventory, and summarises the result.

!!! warning "Experimental"

    The AI Agent is not part of the core monitoring path. It is a thin Streamlit app that depends on an LLM you host yourself (Ollama / OpenAI). Treat it like a lab utility &mdash; do not point it at production credentials without reviewing the queries it generates.

## What's in the folder

| File | Purpose |
|---|---|
| `sql_db_agent_4_sqlmonitor_using_ollama.py` | Main agent &mdash; talks to the SQLMonitor inventory DB via a [LangChain `SQLDatabase`](https://python.langchain.com/docs/integrations/toolkits/sql_database) toolkit, backed by a local **Ollama** model (default `qwen2:latest`). Streamlit UI. |
| `sql_db_agent_using_ollama.py` | Generic variant you can point at any database. |
| `first_agent_using_ollama.py` / `first_agent_using_openai.py` | Hello-world agents demonstrating the provider swap. |
| `csv_agent_using_ollama.py` | CSV-first example &mdash; useful for trying the agent without a SQL instance. |
| `questions_sql_agent.md` | Curated list of questions that work well against the inventory schema &mdash; good starting set. |
| `requirements.txt` | Python deps: `langchain`, `langchain-community`, `langchain-ollama`, `streamlit`, `sqlalchemy`, `pyodbc`, `python-dotenv`. |

## Setup

```bash
cd ~/GitHub/SQLMonitor/AI-Agent
python -m venv venv
source venv/bin/activate   # .\venv\Scripts\activate on Windows
pip install -r requirements.txt
```

Install the SQL Server ODBC driver:

```bash
# Ubuntu / Debian
curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
curl https://packages.microsoft.com/config/ubuntu/22.04/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list
sudo apt-get update
sudo ACCEPT_EULA=Y apt-get install -y msodbcsql18
```

## Environment variables

Create a `.env` in `AI-Agent/` (do **not** commit it):

```bash
# LLM provider
OLLAMA_MODEL=qwen2:latest          # any model pulled into your local Ollama
# OPENAI_API_KEY_SECRET=sk-...     # if using the OpenAI variant

# SQL Server (inventory)
SQLMONITOR_INVENTORY_SERVER=sqlmonitor.corp.example.com
SQLMONITOR_LOGIN_NAME=grafana       # read-only login is enough
SQLMONITOR_LOGIN_PASSWORD=grafana
SQLMONITOR_DATABASE=DBA

# Optional: Slack webhook for notifications
SLACK_WEBHOOK_URL_AIAGENT=https://hooks.slack.com/...
```

The agent picks these up automatically via `python-dotenv` on startup.

## Run it

```bash
streamlit run sql_db_agent_4_sqlmonitor_using_ollama.py
```

Then open `http://localhost:8501`.

Sample prompts (see `questions_sql_agent.md` for more):

- *"Which instances have less than 10% free disk space?"*
- *"Show me the top 5 waits fleet-wide in the last hour."*
- *"Which AG databases are behind on their redo queue?"*
- *"List SQL Agent jobs that failed in the last 24 hours."*
- *"Which server has had the most blocking incidents this week?"*

## How it works

```mermaid
flowchart LR
  U[User question] --> LLM[LLM<br/>(Ollama / OpenAI)]
  LLM -->|tool call| Tk[LangChain SQLDatabase<br/>Toolkit]
  Tk -->|reads schema| Inv[(DBA inventory DB<br/>read-only login)]
  Tk -->|generates T-SQL| Inv
  Inv -->|rows| Tk
  Tk --> LLM
  LLM --> Ans[Natural-language<br/>answer + SQL shown]
```

1. The agent introspects the `DBA` schema once and feeds the table/column list to the LLM as context.
2. For each question the LLM plans one or more `SELECT` queries.
3. LangChain's SQL toolkit runs them under the **read-only** login you configured &mdash; it refuses `INSERT`/`UPDATE`/`DELETE`/`DROP` by default (see `create_sql_agent(..., agent_type="openai-tools")`).
4. Results are formatted as Markdown and streamed into the Streamlit UI.

## Safety notes

- **Always use a least-privilege SQL login.** The shipped example uses the same `grafana` read-only login the dashboards use. Do not give the agent a `sysadmin` account.
- **LLMs hallucinate schema.** If a question returns "no rows" but you expect data, look at the SQL the agent generated (visible in the Streamlit output) &mdash; it may have guessed a column name that doesn't exist.
- **Rate-limit on large tables.** The agent will happily run `SELECT TOP 1000 * FROM dbo.xevent_metrics` and page the whole thing into the LLM context. Configure `SQLDatabase(..., sample_rows_in_table_info=3)` or point it at a filtered view.
- **Keep prompts out of logs.** The provided Streamlit app echoes the SQL in the UI only &mdash; it does not log prompts/responses by default. If you add PagerDuty/Slack notifications, strip PII first.

## Extending

The agent is deliberately thin &mdash; add your own tools to it:

```python
from langchain.tools import Tool

custom = Tool(
    name="get_blitz_findings",
    func=lambda sql_instance: run_stored_proc("usp_get_blitz", sql_instance),
    description="Return sp_Blitz findings for a given sql_instance"
)
agent = create_sql_agent(llm=llm, db=db, extra_tools=[custom], verbose=True)
```

## Further reading

- Recipe book of working prompts: [`questions_sql_agent.md`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/AI-Agent/questions_sql_agent.md)
- Setup cheatsheet (Slack, Ollama reset, ODBC driver install): [`setup-ai-agent.md`](https://github.com/imajaydwivedi/SQLMonitor/blob/dev/AI-Agent/setup-ai-agent.md)
- LangChain SQL agent docs: <https://python.langchain.com/docs/integrations/toolkits/sql_database>
