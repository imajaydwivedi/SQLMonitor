from dotenv import load_dotenv
import os
from langchain_ollama import ChatOllama
from langchain_experimental.agents.agent_toolkits import (
    create_csv_agent,
    create_pandas_dataframe_agent,
)
import streamlit as st
import pandas as pd

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

# Let's add some pre and suffix prompt
CSV_PROMPT_PREFIX = """
First set the pandas display options to show all the columns,
get the column names, then answer the question.
"""

CSV_PROMPT_SUFFIX = """
- **ALWAYS** before giving the Final Answer, try another method.
Then reflect on the answers of the two methods you did and ask yourself
if it answers correctly the original question.
If you are not sure, try another method.
FORMAT 4 FIGURES OR MORE WITH COMMAS.
- If the methods tried do not give the same result,reflect and
try again until you have two methods that have the same result.
- If you still cannot arrive to a consistent result, say that
you are not sure of the answer.
- If you are sure of the correct answer, create a beautiful
and thorough response using Markdown.
- **DO NOT MAKE UP AN ANSWER OR USE PRIOR KNOWLEDGE,
ONLY USE THE RESULTS OF THE CALCULATIONS YOU HAVE DONE**.
- **ALWAYS**, as part of your "Final Answer", explain how you got
to the answer on a section that starts with: "\n\nExplanation:\n".
In the explanation, mention the column names that you used to get
to the final answer.
"""

# question = "What is the average salary?"
# question = "Which grade has the highest average base salary, and compare the average female pay vs male pay?"

# print(f"\n🧾 Query: {question}\n")

# response = agent.invoke(question)
# response = agent.invoke(CSV_PROMPT_PREFIX + question + CSV_PROMPT_SUFFIX)

# print("💡 Response:")
# print(response["output"])

st.title("Database AI Agent with LangChain")

# read csv file
df = pd.read_csv(csv_file).fillna(value=0)

st.write("### Dataset Preview")
st.write(df.head())

# User input for the question
st.write("### Ask a Question")
question = st.text_input(
    "Enter your question about the dataset:",
    "Which grade has the highest average base salary, and compare the average female pay vs male pay?",
)

# Run the agent and display the result
if st.button("Run Query"):
    # QUERY = CSV_PROMPT_PREFIX + question + CSV_PROMPT_SUFFIX
    QUERY = question
    response = agent.invoke(QUERY)
    st.write("### Final Answer")
    st.markdown(response["output"])


# which department makes the most on average and give the actual amount?

# streamlit run csv_agent_using_ollama.py

