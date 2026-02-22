from langgraph.graph import END, StateGraph, MessagesState

from agents.llm import get_llm


def build_graph():
    llm = get_llm()

    def agent_node(state: MessagesState):
        return {"messages": [llm.invoke(state["messages"])]}

    graph = StateGraph(MessagesState)
    graph.add_node("agent", agent_node)
    graph.set_entry_point("agent")
    graph.add_edge("agent", END)
    return graph.compile()
