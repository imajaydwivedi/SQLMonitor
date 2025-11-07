from dotenv import load_dotenv
import os
from langchain_ollama import ChatOllama
import streamlit as st
import pandas as pd
from sqlalchemy import create_engine, types
from sqlalchemy.dialects import mssql
from langchain_community.agent_toolkits.sql.toolkit import SQLDatabaseToolkit

# Register sysname as NVARCHAR
mssql.base.ischema_names['sysname'] = types.NVARCHAR

from langchain_community.utilities import SQLDatabase
from langchain_community.agent_toolkits.sql.base import create_sql_agent
import streamlit as st

# Load env vars
load_dotenv()

llm_model_name = os.getenv("OLLAMA_MODEL", "qwen2:latest")
sqlmonitor_inventory_server = os.getenv("SQLMONITOR_INVENTORY_SERVER", "localhost")
sqlmonitor_login_name = os.getenv("SQLMONITOR_LOGIN_NAME", "sa")
sqlmonitor_login_password = os.getenv("SQLMONITOR_LOGIN_PASSWORD")
sqlmonitor_database = os.getenv("SQLMONITOR_DATABASE", "DBA")

print(f"Create llm object using ChatOllama")
# llm = ChatOllama(model=llm_model_name)
llm = ChatOllama(model=llm_model_name, stop=["\nObservation:"])

csv_file = "data/salaries_2023.csv"
database_file_path = "./db/salary.db"

# create a db from csv file
# engine = create_engine(f"sqlite:///{database_file_path}")
# os.makedirs(os.path.dirname(database_file_path), exist_ok=True)
# df = pd.read_csv(csv_file).fillna(value=0)
# df.to_sql("salaries_2023", con=engine, if_exists="replace", index=False)

# print(f"Database created successfully. {df}")

driver = "ODBC Driver 18 for SQL Server"
connection_string = (
    f"mssql+pyodbc://{sqlmonitor_login_name}:{sqlmonitor_login_password}@{sqlmonitor_inventory_server}/{sqlmonitor_database}"
    f"?driver={driver.replace(' ', '+')}"
    f"&TrustServerCertificate=yes"
)

# Create database connection
print(f"Create db object using SQLDatabase.from_uri")
db = SQLDatabase.from_uri(
    connection_string,
    include_tables=["vw_all_server_info"],
    # sample_rows_in_table_info=2,  # Reduce sample rows
    view_support=True  # Don't include views
)

print(f"Create toolkit object using SQLDatabaseToolkit")
toolkit = SQLDatabaseToolkit(db=db, llm=llm)

# Part 2: Prepare the sql prompt
MSSQL_AGENT_PREFIX = """

You are an agent designed to interact with a SQL database.
## Instructions:
- Given an input question, create a syntactically correct {dialect} query
to run, then look at the results of the query and return the answer.
- Unless the user specifies a specific number of examples they wish to
obtain, **ALWAYS** limit your query to at most {top_k} results.
- You can order the results by a relevant column to return the most
interesting examples in the database.
- Never query for all the columns from a specific table, only ask for
the relevant columns given the question.
- You have access to tools for interacting with the database.
- You MUST double check your query before executing it.If you get an error
while executing a query,rewrite the query and try again.
- DO NOT make any DML statements (INSERT, UPDATE, DELETE, DROP etc.)
to the database.
- DO NOT MAKE UP AN ANSWER OR USE PRIOR KNOWLEDGE, ONLY USE THE RESULTS
OF THE CALCULATIONS YOU HAVE DONE.
- Your response should be in Markdown. However, **when running  a SQL Query
in "Action Input", do not include the markdown backticks**.
Those are only for formatting the response, not for executing the command.
- ALWAYS, as part of your final answer, explain how you got to the answer
on a section that starts with: "Explanation:". Include the SQL query as
part of the explanation section.
- If the question does not seem related to the database, just return
"I don\'t know" as the answer.
- Only use the below tools. Only use the information returned by the
below tools to construct your query and final answer.
- Do not make up table names, only use the tables returned by any of the
tools below.
- as part of your final answer, please include the SQL query you used in json format or code format

## Tools:

## Metadata/Column description for view dbo.vw_all_server_info.
This table/view represents basic health & properties of sql server instances.
Each line in this table/view represent one sql server instance.
And columns represent some attributes and health metrics of sql instance.

- [srv_name] - This column is the server name or ip that is used by entire database, and can be used to connect data across tables in database.
- [at_server_name] - This column value comes from @@servername attribute within sql server.
- [os_cpu] - Percentage CPU utilization at operating system level for server [srv_name].
- [sql_os] - Percentage CPU utilization of SQLServer process for server [srv_name].
- [blocked_counts] - This is number of sql sessions or queries blocked at the moment of data collection on the server. So a server can be called of having blocking issue only when value in this column is greater than 0.
- [avg_disk_latency_ms] - This is numerical value of time in milliseconds that represents average disk latency on sql server instance. So a server can be called of having disk latency issue only when value in this column is greator or equal to than 20 milliseconds.

"""

MSSQL_AGENT_FORMAT_INSTRUCTIONS = """

## Use the following format:

Question: the input question you must answer.
Thought: you should always think about what to do.
Action: the action to take, should be one of [{tool_names}].
Action Input: the input to the action.
Observation: the result of the action.
... (this Thought/Action/Action Input/Observation can repeat N times)
Thought: I now know the final answer.
Final Answer: the final answer to the original input question.

Example of Final Answer:
<=== Beginning of example

Action: query_sql_db
Action Input: 
SELECT TOP (10) [base_salary], [grade] 
FROM salaries_2023

WHERE state = 'Division'

Observation:
[(27437.0,), (27088.0,), (26762.0,), (26521.0,), (26472.0,), (26421.0,), (26408.0,)]
Thought:I now know the final answer
Final Answer: There were 27437 workers making 100,000.

Explanation:
I queried the `xyz` table for the `salary` column where the department
is 'IGM' and the date starts with '2020'. The query returned a list of tuples
with the bazse salary for each day in 2020. To answer the question,
I took the sum of all the salaries in the list, which is 27437.
I used the following query

```sql
SELECT [salary] FROM xyztable WHERE department = 'IGM' AND date LIKE '2020%'"
```
===> End of Example

"""


question = "what is the highest average salary by department, and give me the number?"
# question = """How many employees are in the ABS 85 Administrative Services,
# and their avg salaries, and also how many of them are female?
# """

print(f"Create sql_agent object using create_sql_agent")
sql_agent = create_sql_agent(
    prefix=MSSQL_AGENT_PREFIX,
    format_instructions=MSSQL_AGENT_FORMAT_INSTRUCTIONS,
    llm=llm,
    toolkit=toolkit,
    top_k=30,
    verbose=True,
    handle_parsing_errors=True,
    agent_kwargs={
        "stop": ["\nObservation:", "\nAction:", "\nFinal Answer:"]
    }
)

# response = sql_agent.invoke(question)
# print(response["output"])



st.title("SQL Query AI Agent")

question = st.text_input("Enter your query:")

if st.button("Run Query"):
    print(f"Getting answer from llm..")
    if question:
        res = sql_agent.invoke(question)

        st.markdown(res["output"])
else:
    st.error("Please enter a query.")


# streamlit run sql_db_agent_using_ollama.py
