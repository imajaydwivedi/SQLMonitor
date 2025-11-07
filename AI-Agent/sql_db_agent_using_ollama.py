from dotenv import load_dotenv
import os
from langchain_ollama import ChatOllama
import streamlit as st
import pandas as pd
from sqlalchemy import create_engine


# Load env vars
load_dotenv()

llm_model_name = os.getenv("OLLAMA_MODEL", "qwen2:latest")
llm = ChatOllama(model=llm_model_name)

csv_file = "data/salaries_2023.csv"

# read csv file


from langchain.agents import create_sql_agent
from langchain_community.agent_toolkits.sql.toolkit import SQLDatabaseToolkit
from langchain_community.utilities import SQLDatabase

# create a db from csv file
database_file_path = "./db/salary.db"
engine = create_engine(f"sqlite:///{database_file_path}")
file_url = csv_file
os.makedirs(os.path.dirname(database_file_path), exist_ok=True)
df = pd.read_csv(csv_file).fillna(value=0)
df.to_sql("salaries_2023", con=engine, if_exists="replace", index=False)

print(f"Database created successfully. {df}")
