from dotenv import load_dotenv
import os
from langchain_ollama import ChatOllama
import streamlit as st
import pandas as pd
from sqlalchemy import create_engine
# from langchain.agents import create_sql_agent
from langchain_community.agent_toolkits.sql.toolkit import SQLDatabaseToolkit
from langchain_community.utilities import SQLDatabase
from langchain_community.agent_toolkits.sql.base import create_sql_agent


# Load env vars
load_dotenv()

llm_model_name = os.getenv("OLLAMA_MODEL", "qwen2:latest")
# llm_model_name = "gpt-oss"
llm = ChatOllama(model=llm_model_name)

csv_file = "data/salaries_2023.csv"
database_file_path = "./db/salary.db"

# create a db from csv file
engine = create_engine(f"sqlite:///{database_file_path}")
os.makedirs(os.path.dirname(database_file_path), exist_ok=True)
df = pd.read_csv(csv_file).fillna(value=0)
df.to_sql("salaries_2023", con=engine, if_exists="replace", index=False)

# print(f"Database created successfully. {df}")

db = SQLDatabase.from_uri(f"sqlite:///{database_file_path}")
toolkit = SQLDatabaseToolkit(db=db, llm=llm)

question = "what is the highest average salary by department, and give me the number?"
# question = """How many employees are in the ABS 85 Administrative Services,
# and their avg salaries, and also how many of them are female?
# """

sql_agent = create_sql_agent(
    # prefix=MSSQL_AGENT_PREFIX,
    # format_instructions=MSSQL_AGENT_FORMAT_INSTRUCTIONS,
    llm=llm,
    toolkit=toolkit,
    top_k=30,
    verbose=True,
    handle_parsing_errors=True,  # Added this line
)

response = sql_agent.invoke(question)
print(response["output"])



