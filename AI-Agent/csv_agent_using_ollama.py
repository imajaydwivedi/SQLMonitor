from langchain_core.messages import SystemMessage, HumanMessage
from langchain_ollama import ChatOllama

import os
from dotenv import load_dotenv
import pandas as pd

llm_model_name = "gemma3:4b"
model = ChatOllama(model=llm_model_name)

# read csv file
df = pd.read_csv('data/salaries_2023.csv').fillna(value=0)

print(df.head())
