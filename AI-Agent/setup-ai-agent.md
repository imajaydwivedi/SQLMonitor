# Setup AI Agent for Databases

Reference: [Mastering AI Agents](https://learning.oreilly.com/videos/mastering-ai-agents)

Small set of LangChain agents that answer natural-language questions about data. They use either a local Ollama model or OpenAI, and run against a local SQLite file (salary CSV) or the SQLMonitor inventory database (`DBA`, view `vw_all_server_info`).

All commands assume you are in the `AI-Agent` folder. The scripts load `data/salaries_2023.csv` and `./db/salary.db` with relative paths, so running from another folder will fail.

---

## 1. Project contents

| File | What it does | Model | Data source | Run as |
|---|---|---|---|---|
| `first_agent_using_openai.py` | Terminal chat agent ("Rob", a computer-scientist persona), no tools | OpenAI (`OPENAI_MODEL`) | none | `python first_agent_using_openai.py` |
| `first_agent_using_ollama.py` | Same chat agent | Ollama (`OLLAMA_MODEL`) | none | `python first_agent_using_ollama.py` |
| `csv_agent_using_ollama.py` | Streamlit page: LangChain pandas CSV agent, writes and runs Python against the CSV | Ollama | `data/salaries_2023.csv` | `streamlit run csv_agent_using_ollama.py` |
| `sql_db_agent_using_ollama.py` | Streamlit page: SQL agent over a SQLite copy of the CSV | Ollama | `db/salary.db` (rebuilt from CSV each run) | `streamlit run sql_db_agent_using_ollama.py` |
| `sql_db_agent_4_sqlmonitor_using_ollama.py` | Streamlit page: SQL agent over SQLMonitor's `DBA` database, restricted to `vw_all_server_info` | Ollama | SQL Server (`SQLMONITOR_*` variables) | `streamlit run sql_db_agent_4_sqlmonitor_using_ollama.py` |
| `questions_sql_agent.md` | 15 sample questions for the salary dataset | — | — | — |

Data:

- `data/salaries_2023.csv`: 10,291 rows. Columns: `Department`, `Department_Name`, `Division`, `Gender`, `Base_Salary`, `Overtime_Pay`, `Longevity_Pay`, `Grade`.
- `db/salary.db`: SQLite table `salaries_2023`, same columns (the copy the SQL agent reads).

Dependencies are pinned in `requirements.txt`. Key versions: `langchain==0.2.14`, `langchain-community==0.2.12`, `langchain-experimental==0.0.63`, `langchain-ollama==0.1.3`, `langchain-openai==0.1.23`. Other packages (`streamlit`, `openai`, `pandas`, `SQLAlchemy`, `pyodbc`, `python-dotenv`, `tabulate`) are not pinned.

---

## 2. Set up the virtual environment

```bash
cd ~/GitHub/SQLMonitor/AI-Agent

# create the venv (Python 3.12 is what the existing venv uses)
python3.12 -m venv venv

# activate it
source venv/bin/activate

# install pinned requirements
pip install -r requirements.txt

# if you installed anything by hand, record the full set so it can be reproduced
pip freeze > requirements_temp.txt
# then copy the new packages into requirements.txt and delete requirements_temp.txt

deactivate
```

`venv/` is in the repository `.gitignore`, so keep it out of commits.

---

## 3. Configure environment variables

Put these in `AI-Agent/.env`. The `.env` file is git-ignored. Do not commit it, and do not copy it to backup names that git tracks (see §6).

| Variable | Used by | Purpose |
|---|---|---|
| `OPENAI_API_KEY` | `first_agent_using_openai.py` (and read implicitly by `langchain-openai`) | OpenAI API key |
| `OPENAI_MODEL` | `first_agent_using_openai.py` | OpenAI model name |
| `OLLAMA_MODEL` | all Ollama scripts (default `qwen2:latest` in code) | Local Ollama model name |
| `OLLAMA_MODEL_EMBEDDING` | not read by any script | reserved for embeddings |
| `OLLAMA_API_KEY`, `OLLAMA_JWT_TOKEN` | not read by any script | only needed if you point Ollama at a hosted or authenticated endpoint |
| `SQLMONITOR_INVENTORY_SERVER` | `sql_db_agent_4_sqlmonitor_using_ollama.py` | SQL Server host that holds the `DBA` database |
| `SQLMONITOR_DATABASE` | same | Database name (default `DBA`) |
| `SQLMONITOR_LOGIN_NAME` | same | SQL login (default `sa`; use a read-only login, see §6) |
| `SQLMONITOR_LOGIN_PASSWORD` | same | Password for that login |

The first OpenAI script reads `OPENAI_API_KEY_SECRET`, which is not defined in `.env`. It works only because `langchain-openai` falls back to `OPENAI_API_KEY`. See §6.

To check that a variable is set without printing its value:

```bash
[ -n "$OPENAI_API_KEY" ] && echo "OPENAI_API_KEY is set" || echo "OPENAI_API_KEY is missing"
```

---

## 4. Install the SQL Server ODBC driver (for the SQLMonitor agent)

Only needed for `sql_db_agent_4_sqlmonitor_using_ollama.py`. The script connects with `ODBC Driver 18 for SQL Server`.

Install the driver from Microsoft's current instructions for your Linux distribution: <https://learn.microsoft.com/sql/connect/odbc/linux-mac/installing-the-microsoft-odbc-driver-for-sql-server>.

The old instructions in this file used `apt-key` (deprecated) and `msodbcsql17` on Ubuntu 20.04 (the script needs Driver 18). If you use Docker instead, see `Alerting/Dockerfile` in this repository, which installs `msodbcsql18`.

Check that the driver is registered:

```bash
odbcinst -q -d
```

---

## 5. Run the agents

### Terminal chat agents

```bash
source venv/bin/activate
python first_agent_using_ollama.py     # or first_agent_using_openai.py
# type a question; "exit" quits
```

### Streamlit pages

```bash
source venv/bin/activate
streamlit run csv_agent_using_ollama.py
streamlit run sql_db_agent_using_ollama.py
streamlit run sql_db_agent_4_sqlmonitor_using_ollama.py
```

Ollama must be running and the model must be pulled first (`ollama pull <OLLAMA_MODEL>`).

Example questions are in `questions_sql_agent.md`. For example: "What is the average base salary for female employees in the Alcohol Beverage Services department?"

### Optional: Slack

The scripts in this folder do not post to Slack. The old setup note used a Slack incoming webhook. If you want to test a webhook, use an environment variable that you set yourself and never print it:

```bash
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Hello, World!"}' "$SLACK_WEBHOOK_URL"
```

### Optional: restart Open WebUI

If Ollama or Open WebUI is stuck on an old error:

```bash
sudo systemctl restart open-webui.service
```

---

## 6. Known issues

Ordered by risk.

1. **Secrets are tracked by git.** `AI-Agent/.env__bak` is committed. It contains `KEY=value` entries for OpenAI and Ollama and a SQL login and password. Treat every value in it as exposed. Rotate the keys and password, remove the file from git (`git rm --cached`), and rewrite history if the repository is shared. Keep backups outside the repository.
2. **Read-only enforcement is only in the prompt.** The SQL agents tell the model not to run DML, but nothing enforces it. Point `SQLMONITOR_LOGIN_NAME` at a login that only has `SELECT` on `vw_all_server_info`.
3. **Passwords in the connection string.** `sql_db_agent_4_sqlmonitor_using_ollama.py` builds the `mssql+pyodbc://` URL with raw string formatting. A password with `@`, `:`, `/`, or `#` breaks the URL. Build it with `sqlalchemy.engine.URL.create(...)` instead.
4. **Dangerous code execution.** `csv_agent_using_ollama.py` sets `allow_dangerous_code=True`, so the model can run Python generated by the LLM on your machine. Only use it with trusted data and models.
5. **Rebuilds on every interaction.** `sql_db_agent_using_ollama.py` rebuilds `db/salary.db` on each Streamlit rerun (Streamlit reruns the whole script on every widget change). It works, but it is slow and overwrites the file each time.
6. **Hard-coded values.** The sample question is set in code in each SQL script. The SQLMonitor script limits `include_tables` to one view. `SQLMONITOR_LOGIN_PASSWORD` defaults to `None`, which becomes the string `"None"` in the connection string.
7. **Variable mismatch.** `first_agent_using_openai.py` reads `OPENAI_API_KEY_SECRET`, which doesn't exist in `.env`. It works only because `langchain-openai` falls back to `OPENAI_API_KEY`.
8. **Unused variables.** `OLLAMA_MODEL_EMBEDDING`, `OLLAMA_API_KEY`, and `OLLAMA_JWT_TOKEN` are not read by any script.
9. **Old pins.** LangChain 0.2.x is out of date, and `streamlit`, `openai`, and `pandas` are unpinned. Installs are not reproducible without a fresh `pip freeze`.
10. **No tests.** The scripts run only interactively. There is no test suite.
11. **Stale setup notes.** The previous version of this file referenced `OPENAI_API_KEY_NAME`, `OPENAI_API_KEY_SECRET`, and `SLACK_WEBHOOK_URL_AIAGENT`. None of them are used by the current scripts.

---

## 7. History

From `git log -- AI-Agent` (13 commits):

- **2025-11-06**: project added. First chat agents (Ollama and OpenAI) and a CSV-reading agent.
- **2025-11-07**: built the SQLite copy of the salary CSV, the SQL agent, and the SQLMonitor agent.
- **2025-11-16**: solution file added.
