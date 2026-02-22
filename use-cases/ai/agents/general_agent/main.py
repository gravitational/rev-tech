import json
import os
from pathlib import Path

from a2a.types import (
    AgentCapabilities,
    AgentCard,
    AgentSkill,
)

from agents.base_agent import BaseA2AAgent
from agents.general_agent.graph import build_graph


def load_card() -> AgentCard:
    raw = json.loads((Path(__file__).parent / "card.json").read_text())
    return AgentCard(
        name=raw["name"],
        description=raw["description"],
        url=raw["url"],
        version=raw["version"],
        defaultInputModes=raw["defaultInputModes"],
        defaultOutputModes=raw["defaultOutputModes"],
        capabilities=AgentCapabilities(**raw["capabilities"]),
        skills=[AgentSkill(**s) for s in raw["skills"]],
    )


if __name__ == "__main__":
    port = int(os.environ.get("AGENT_PORT", 9003))
    agent = BaseA2AAgent(graph=build_graph(), card=load_card())
    agent.run(port=port)
