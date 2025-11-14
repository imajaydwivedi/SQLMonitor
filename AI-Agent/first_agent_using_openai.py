from langchain_core.messages import HumanMessage, SystemMessage
import os
from dotenv import load_dotenv
from langchain_openai import ChatOpenAI

# Load environment variables from .env file
load_dotenv()

openai_key = os.getenv("OPENAI_API_KEY_SECRET")

llm_name = os.getenv("OPENAI_MODEL")
model = ChatOpenAI(api_key=openai_key, model=llm_name)

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

