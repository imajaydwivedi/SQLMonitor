from langchain_core.messages import HumanMessage, SystemMessage
from langchain_ollama import ChatOllama
import os
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# --- Ollama Configuration ---
# Note: You do NOT need the OPENAI_API_KEY or python-dotenv for Ollama locally.

# 2. Define the model name used in Ollama
llm_model_name = os.getenv("OLLAMA_MODEL")

# 3. Initialize the ChatOllama model
# If Ollama is running on the default port (11434), you only need the model name.
# If it's on a different port/host, you can specify the base_url:
# model = ChatOllama(model=llm_model_name, base_url="http://your_host:your_port")
model = ChatOllama(model=llm_model_name)

messages = [
    SystemMessage(
        content="You are a helpful assistant who is extremely competent as a Computer Scientist! Your name is Rob."
    ),
    HumanMessage(content="who was the very first computer scientist?"),
]

# res = model.invoke(messages)
# print(res)

def first_agent(messages):
    res = model.invoke(messages)
    return res


def run_agent():
    print("Simple AI Agent: Type 'exit' to quit")
    while True:
        user_input = input("You: ")
        if user_input.lower() == "exit":
            print("Goodbye!")
            break
        print("AI Agent is thinking...")
        messages = [HumanMessage(content=user_input)]
        response = first_agent(messages)
        print("AI Agent: getting the response...")
        print(f"AI Agent: {response.content}")


if __name__ == "__main__":
    run_agent()