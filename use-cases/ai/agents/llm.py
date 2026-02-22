import os

from langchain_anthropic import ChatAnthropic
from langchain_ollama import ChatOllama
from langchain_openai import ChatOpenAI


def get_llm():
    provider = os.environ.get("LLM_PROVIDER", "anthropic")
    if provider == "ollama":
        return ChatOllama(
            model=os.environ.get("OLLAMA_MODEL", "llama3.2"),
            base_url=os.environ.get("OLLAMA_BASE_URL", "http://host.docker.internal:11434"),
        )
    if provider == "lmstudio":
        return ChatOpenAI(
            model=os.environ.get("LM_STUDIO_MODEL", "local-model"),
            base_url=os.environ.get("LM_STUDIO_BASE_URL", "http://host.docker.internal:1234/v1"),
            api_key=os.environ.get("LM_STUDIO_API_KEY", "lm-studio"),
        )
    return ChatAnthropic(
        model=os.environ.get("ANTHROPIC_MODEL", "claude-sonnet-4-6"),
        api_key=os.environ["ANTHROPIC_API_KEY"],
    )
