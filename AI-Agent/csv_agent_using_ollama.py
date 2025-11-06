from dotenv import load_dotenv
import os
from langchain_ollama import ChatOllama
from langchain_experimental.agents.agent_toolkits import (
    create_csv_agent,
    create_pandas_dataframe_agent,
)

# Load env vars
load_dotenv()

llm_model_name = os.getenv("OLLAMA_MODEL", "qwen2:latest")
llm = ChatOllama(model=llm_model_name)

csv_file = "data/salaries_2023.csv"

agent = create_csv_agent(
    llm=llm,
    path=csv_file,
    verbose=True,
    allow_dangerous_code=True
)

query = "What is the average salary?"
print(f"\n🧾 Query: {query}\n")

response = agent.invoke(query)

print("💡 Response:")
print(response["output"])
