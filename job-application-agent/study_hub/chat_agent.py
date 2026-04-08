"""
RAG chat agent for Study Hub.
Finds relevant notes via FAISS, injects them as context, calls LLM.
"""
import sys
import logging
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """You are a personal study assistant for a software developer.
You have access to their personal dev notes and learning materials.

Rules:
- Answer based on the notes provided in context when relevant.
- Reference the specific note title when you use information from it.
- If the notes don't cover the topic, answer from general knowledge and say so.
- Be concise and clear. Use bullet points for steps. Use code blocks for code.
- Explain things simply — the developer is learning and may need concepts broken down.
- If asked "what did I learn about X", search the notes and summarize.
- If asked to explain a concept, use the notes as a starting point."""


async def chat(query: str, history: list[dict], notes_index) -> dict:
    """
    RAG chat. Returns {"answer": str, "sources": list[str]}.
    history: list of {"role": "user"|"assistant", "content": str}
    """
    context, sources = notes_index.get_rag_context(query, k=5)

    history_text = ""
    for msg in history[-8:]:  # last 4 turns
        role = msg.get("role", "user").upper()
        content = msg.get("content", "")
        history_text += f"\n{role}: {content}"

    if context:
        prompt = f"""Here are relevant notes from your personal knowledge base:

{context}

---
Previous conversation:{history_text}

USER: {query}

Answer the question using the notes above as your primary source. Be specific and helpful."""
    else:
        prompt = f"""No relevant notes found for this query.
Previous conversation:{history_text}

USER: {query}

Answer from general knowledge. Suggest the developer might want to add a note about this topic."""

    try:
        from utils.llm_client import get_llm_client
        client = get_llm_client()
        answer = await client.generate(prompt, system_prompt=SYSTEM_PROMPT)
    except Exception as e:
        logger.error(f"LLM chat error: {e}")
        answer = f"Error generating response: {e}. Make sure Ollama is running or a Groq API key is configured."

    return {"answer": answer, "sources": sources}
