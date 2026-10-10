"""Open-weight model provider for Hackathon compliance (<8B parameters).

Supports local inference engines (Ollama, llama.cpp, vLLM, LocalAI) running
genuine open-weight models such as:
- Qwen2.5-Coder-7B-Instruct (7.6B parameters, Apache 2.0)
- Llama-3.1-8B-Instruct (8.0B parameters, Meta Llama 3.1 Community License)
- Mistral-7B-Instruct-v0.3 (7.2B parameters, Apache 2.0)
"""

from __future__ import annotations

import json
import logging
import os
from typing import Any

import httpx

from incident_agent.llm.base import (
    BaseLLMProvider,
    LLMProviderError,
    LLMResponseFormatError,
    LLMTimeoutError,
)
from incident_agent.schemas.llm import (
    LLMCompletionRequest,
    LLMCompletionResponse,
    LLMStructuredReportRequest,
    LLMStructuredReportResponse,
    LLMUsage,
)
from incident_agent.schemas.report import EvidenceItem, IncidentReport
from incident_agent.utils.observability import get_logger

logger = get_logger(__name__)

DEFAULT_OPEN_WEIGHT_MODEL = "qwen2.5-coder:7b"
DEFAULT_OPEN_WEIGHT_BASE_URL = os.getenv(
    "DEVSHIELD_AI_BASE_URL",
    os.getenv("OLLAMA_HOST", "http://localhost:11434/v1"),
)


class OpenWeightModelProvider(BaseLLMProvider):
    """Adapter for open-weight models (<=8B parameters) via OpenAI-compatible HTTP endpoints."""

    def __init__(
        self,
        base_url: str = DEFAULT_OPEN_WEIGHT_BASE_URL,
        model_name: str = DEFAULT_OPEN_WEIGHT_MODEL,
        model: str | None = None,
        api_key: str | None = None,
        timeout_seconds: float = 20.0,
        max_retries: int = 2,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.model_name = model or model_name
        self.api_key = api_key or os.getenv("DEVSHIELD_AI_API_KEY", "local-no-key-required")
        self.timeout_seconds = timeout_seconds
        self.max_retries = max_retries

    def _get_headers(self) -> dict[str, str]:
        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        return headers

    def complete(self, request: LLMCompletionRequest) -> LLMCompletionResponse:
        """Call chat completions on the open-weight model."""
        endpoint = f"{self.base_url}/chat/completions"
        payload = {
            "model": request.model or self.model_name,
            "messages": [
                {
                    "role": "system",
                    "content": "You are DevShield AI, an expert site reliability and root-cause analysis assistant.",
                },
                {"role": "user", "content": request.prompt},
            ],
            "temperature": 0.2,
        }

        try:
            with httpx.Client(timeout=self.timeout_seconds) as client:
                response = client.post(endpoint, json=payload, headers=self._get_headers())
                if response.status_code != 200:
                    raise LLMProviderError(
                        f"Open-weight model runner returned HTTP {response.status_code}: {response.text[:200]}"
                    )
                data = response.json()
                content = data["choices"][0]["message"]["content"]
                usage = data.get("usage", {})
                return LLMCompletionResponse(
                    model=request.model or self.model_name,
                    content=content,
                    raw_response=data,
                    usage=LLMUsage(
                        prompt_tokens=usage.get("prompt_tokens", len(request.prompt) // 4),
                        completion_tokens=usage.get("completion_tokens", len(content) // 4),
                        total_tokens=usage.get("total_tokens", (len(request.prompt) + len(content)) // 4),
                        latency_ms=10.0,
                        estimated_cost_usd=0.0,  # Local open-weight models have $0 API cost
                    ),
                )
        except httpx.TimeoutException as exc:
            raise LLMTimeoutError(f"Connection to open-weight runtime timed out: {exc}") from exc
        except httpx.ConnectError as exc:
            raise LLMProviderError(f"Unable to connect to open-weight runtime at {self.base_url}: {exc}") from exc
        except Exception as exc:
            raise LLMProviderError(f"Open-weight model execution failed: {exc}") from exc

    def generate_structured_report(
        self,
        request: LLMStructuredReportRequest,
    ) -> LLMStructuredReportResponse:
        """Generate structured IncidentReport from the open-weight model."""
        format_instruction = (
            "\n\nRespond ONLY with a valid JSON object matching this schema:\n"
            "{\n"
            '  "title": "Incident Title",\n'
            '  "severity": "CRITICAL" | "HIGH" | "MEDIUM" | "LOW",\n'
            '  "impacted_service": "service-name",\n'
            '  "incident_summary": "concise description",\n'
            '  "likely_root_causes": ["hypothesis 1", "hypothesis 2"],\n'
            '  "recommended_actions": ["action 1", "action 2"],\n'
            '  "evidence": [{"kind": "log|metric|diff", "timestamp": "...", "content": "..."}]\n'
            "}"
        )
        complete_req = LLMCompletionRequest(
            prompt=request.prompt + format_instruction,
            model=request.model or self.model_name,
        )
        res = self.complete(complete_req)
        content = res.content.strip()

        # Extract JSON block if wrapped in markdown code fence
        if "```json" in content:
            content = content.split("```json", 1)[1].split("```", 1)[0].strip()
        elif "```" in content:
            content = content.split("```", 1)[1].split("```", 1)[0].strip()

        # Validate that it matches IncidentReport schema
        try:
            parsed = IncidentReport.model_validate_json(content)
        except Exception as exc:
            raise LLMResponseFormatError(
                f"Model response was not valid IncidentReport JSON: {exc}. Raw content: {content[:150]}"
            ) from exc

        return LLMStructuredReportResponse(
            model=res.model,
            content=json.dumps(parsed.model_dump(mode="json")),
            raw_response=res.raw_response,
            usage=res.usage,
        )


OpenWeightProvider = OpenWeightModelProvider

