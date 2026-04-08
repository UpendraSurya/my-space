"""
LLM client with Ollama (primary) and Groq (fallback) support.
"""
import asyncio
import json
import logging
import re
from typing import Optional

import httpx

logger = logging.getLogger(__name__)


class LLMClient:
    def __init__(self, ollama_base_url: str, ollama_model: str,
                 groq_api_key: str = "", groq_model: str = "llama-3.1-8b-instant"):
        self.ollama_base_url = ollama_base_url
        self.ollama_model = ollama_model
        self.groq_api_key = groq_api_key
        self.groq_model = groq_model
        self._ollama_available: Optional[bool] = None

    async def _check_ollama(self) -> bool:
        if self._ollama_available is not None:
            return self._ollama_available
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(f"{self.ollama_base_url}/api/tags")
                self._ollama_available = resp.status_code == 200
        except Exception:
            self._ollama_available = False
        return self._ollama_available

    async def _ollama_generate(self, prompt: str, system_prompt: str = "") -> str:
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})

        payload = {
            "model": self.ollama_model,
            "messages": messages,
            "stream": False,
            "options": {"temperature": 0.3, "num_ctx": 4096},
        }
        async with httpx.AsyncClient(timeout=120.0) as client:
            resp = await client.post(
                f"{self.ollama_base_url}/api/chat", json=payload
            )
            resp.raise_for_status()
            data = resp.json()
            return data["message"]["content"]

    async def _groq_generate(self, prompt: str, system_prompt: str = "") -> str:
        if not self.groq_api_key:
            raise RuntimeError("No Groq API key configured and Ollama unavailable.")

        try:
            from groq import AsyncGroq
        except ImportError:
            raise RuntimeError("groq package not installed. Run: pip install groq")

        client = AsyncGroq(api_key=self.groq_api_key)
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})

        response = await client.chat.completions.create(
            model=self.groq_model,
            messages=messages,
            temperature=0.3,
            max_tokens=2048,
        )
        return response.choices[0].message.content

    async def generate(self, prompt: str, system_prompt: str = "") -> str:
        """Generate text using Ollama first, fall back to Groq."""
        if await self._check_ollama():
            try:
                return await self._ollama_generate(prompt, system_prompt)
            except Exception as e:
                logger.warning(f"Ollama failed: {e}. Falling back to Groq.")

        return await self._groq_generate(prompt, system_prompt)

    async def generate_json(self, prompt: str, system_prompt: str = "",
                            retries: int = 2) -> dict:
        """Generate and parse JSON response, with retry on parse failure."""
        json_system = (system_prompt or "") + (
            "\nALWAYS respond with valid JSON only. No prose, no markdown code blocks, "
            "just raw JSON starting with { or [."
        )
        for attempt in range(retries + 1):
            raw = await self.generate(prompt, json_system)
            raw = raw.strip()
            # Strip markdown code blocks if present
            raw = re.sub(r'^```(?:json)?\s*', '', raw)
            raw = re.sub(r'\s*```$', '', raw)
            try:
                return json.loads(raw)
            except json.JSONDecodeError:
                # Try extracting first JSON object
                match = re.search(r'\{.*\}', raw, re.DOTALL)
                if match:
                    try:
                        return json.loads(match.group())
                    except json.JSONDecodeError:
                        pass
                if attempt < retries:
                    prompt = (
                        f"Fix this invalid JSON and return only the corrected JSON:\n{raw}"
                    )
                    logger.warning(f"JSON parse failed (attempt {attempt+1}), retrying.")

        logger.error("Failed to get valid JSON after retries.")
        return {}


# Singleton factory
_client: Optional[LLMClient] = None


def get_llm_client() -> LLMClient:
    global _client
    if _client is None:
        from config import settings
        _client = LLMClient(
            ollama_base_url=settings.ollama_base_url,
            ollama_model=settings.ollama_model,
            groq_api_key=settings.groq_api_key,
            groq_model=settings.groq_model,
        )
    return _client
