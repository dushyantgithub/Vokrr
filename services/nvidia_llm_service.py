from __future__ import annotations

import json
import logging
import os
from collections.abc import AsyncIterator
from dataclasses import dataclass
from typing import Any

import httpx

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """You are Vokrr, a smart realtime home automation voice assistant.

You must classify whether the user wants:
1. normal conversation
2. home automation action

You MUST return ONLY valid JSON.

Never return markdown.
Never explain.
Never add extra text.

Schema:

{
  "ha_command": true,
  "reply": "short response to speak",
  "intent": "conversation | control_device | query_device_state | unknown",
  "room": "string or null",
  "device_name": "string or null",
  "domain": "light | switch | fan | climate | media_player | cover | unknown | null",
  "action": "turn_on | turn_off | toggle | set_brightness | set_speed | set_temperature | get_state | unknown | null",
  "value": null,
  "confidence": 0.95,
  "needs_confirmation": false,
  "needs_clarification": false,
  "clarification_question": null
}

Rules:
- If user is casually talking, set ha_command=false
- If user asks to control a smart device, set ha_command=true
- If user says a room plus plural device type, like "bedroom lights", treat it as all matching devices in that room
- Keep spoken replies short
- Never guess unknown devices
- Ask clarification if uncertain
- Dangerous actions require confirmation
- Output ONLY JSON"""


class LLMError(RuntimeError):
    pass


@dataclass(frozen=True)
class LLMDecision:
    raw_text: str
    data: dict[str, Any]


class NvidiaLLMService:
    def __init__(
        self,
        api_key: str | None = None,
        model: str | None = None,
        url: str | None = None,
        timeout_seconds: float | None = None,
    ) -> None:
        self.api_key = api_key or os.getenv("NVIDIA_API_KEY") or os.getenv("NVIDIA_BUILD_API_KEY", "")
        self.model = model or os.getenv(
            "NVIDIA_LLM_MODEL",
            "meta/llama-4-maverick-17b-128e-instruct",
        )
        self.url = url or os.getenv(
            "NVIDIA_LLM_URL",
            "https://integrate.api.nvidia.com/v1/chat/completions",
        )
        self.timeout_seconds = timeout_seconds or float(os.getenv("NVIDIA_LLM_TIMEOUT_SECONDS", "20"))

    @property
    def configured(self) -> bool:
        return bool(self.api_key)

    async def decide(self, user_text: str, entity_context: dict[str, Any]) -> LLMDecision:
        if not self.api_key:
            raise LLMError("NVIDIA_API_KEY or NVIDIA_BUILD_API_KEY is required")

        context_json = json.dumps(entity_context, ensure_ascii=False, separators=(",", ":"))
        messages = [
            {"role": "system", "content": SYSTEM_PROMPT},
            {
                "role": "user",
                "content": (
                    "Home Assistant context:\n"
                    f"{context_json}\n\n"
                    f"User said: {user_text}"
                ),
            },
        ]
        payload = {
            "model": self.model,
            "messages": messages,
            "max_tokens": 256,
            "temperature": 0.2,
            "top_p": 1.0,
            "stream": True,
        }
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Accept": "text/event-stream",
            "Content-Type": "application/json",
        }

        chunks: list[str] = []
        timeout = httpx.Timeout(self.timeout_seconds, connect=5.0)
        async with httpx.AsyncClient(timeout=timeout) as client:
            async with client.stream("POST", self.url, headers=headers, json=payload) as response:
                if response.status_code >= 400:
                    body = await response.aread()
                    raise LLMError(f"NVIDIA LLM request failed: {response.status_code} {body[:300]!r}")
                async for token in self._iter_sse_tokens(response):
                    chunks.append(token)

        raw_text = "".join(chunks).strip()
        if not raw_text:
            raise LLMError("NVIDIA LLM returned an empty response")
        return LLMDecision(raw_text=raw_text, data=parse_strict_json(raw_text))

    async def _iter_sse_tokens(self, response: httpx.Response) -> AsyncIterator[str]:
        async for line in response.aiter_lines():
            line = line.strip()
            if not line or not line.startswith("data:"):
                continue
            data = line.removeprefix("data:").strip()
            if data == "[DONE]":
                break
            try:
                payload = json.loads(data)
            except json.JSONDecodeError:
                logger.debug("Skipping malformed NVIDIA SSE line: %s", data)
                continue
            for choice in payload.get("choices", []):
                delta = choice.get("delta") or {}
                content = delta.get("content")
                if content:
                    yield content


def parse_strict_json(raw_text: str) -> dict[str, Any]:
    try:
        parsed = json.loads(raw_text)
    except json.JSONDecodeError:
        start = raw_text.find("{")
        end = raw_text.rfind("}")
        if start < 0 or end <= start:
            raise LLMError(f"LLM did not return JSON: {raw_text[:160]!r}") from None
        parsed = json.loads(raw_text[start : end + 1])

    if not isinstance(parsed, dict):
        raise LLMError("LLM JSON response must be an object")
    return parsed
