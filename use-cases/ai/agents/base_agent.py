import uvicorn
from langchain_core.messages import HumanMessage

from a2a.server.apps import A2AStarletteApplication
from a2a.server.agent_execution import AgentExecutor, RequestContext
from a2a.server.events import EventQueue
from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.tasks import InMemoryTaskStore, TaskUpdater
from a2a.types import AgentCard, Part, TextPart, UnsupportedOperationError
from a2a.utils.parts import get_text_parts


class LangGraphAgentExecutor(AgentExecutor):
    """Adapts a compiled LangGraph graph to the A2A AgentExecutor interface."""

    def __init__(self, graph):
        self.graph = graph

    async def execute(self, context: RequestContext, event_queue: EventQueue) -> None:
        updater = TaskUpdater(event_queue, context.task_id, context.context_id)

        user_text = " ".join(get_text_parts(context.message.parts))

        result = await self.graph.ainvoke(
            {"messages": [HumanMessage(content=user_text)]}
        )

        last_msg = result["messages"][-1]
        response_text = (
            last_msg.content if hasattr(last_msg, "content") else str(last_msg)
        )

        await updater.add_artifact(parts=[Part(root=TextPart(text=response_text))])
        await updater.complete()

    async def cancel(self, context: RequestContext, event_queue: EventQueue) -> None:
        raise UnsupportedOperationError()


class BaseA2AAgent:
    """
    Wraps a compiled LangGraph graph + AgentCard into an A2AStarletteApplication.
    All specialist agents inherit from this.
    """

    def __init__(self, graph, card: AgentCard):
        self.graph = graph
        self.card = card
        handler = DefaultRequestHandler(
            agent_executor=LangGraphAgentExecutor(graph),
            task_store=InMemoryTaskStore(),
        )
        self._a2a = A2AStarletteApplication(
            agent_card=card,
            http_handler=handler,
        )

    def run(self, host: str = "0.0.0.0", port: int = 9001):
        app = self._a2a.build()
        uvicorn.run(app, host=host, port=port)
