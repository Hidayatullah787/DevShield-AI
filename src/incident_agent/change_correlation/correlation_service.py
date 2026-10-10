"""High-level service coordinating Change Impact Correlation."""

from __future__ import annotations

import logging
from typing import Any

from incident_agent.change_correlation.diff_parser import parse_git_diff
from incident_agent.change_correlation.evidence_ranker import (
    IncidentSignalContext,
    compute_confidence,
    rank_file_changes,
)
from incident_agent.change_correlation.models import (
    ChangeCorrelationResult,
    CorrelationMatch,
)
from incident_agent.llm.base import BaseLLMProvider
from incident_agent.schemas.anomaly import AnomalyCandidate
from incident_agent.schemas.events import LogEvent, MetricPoint
from incident_agent.schemas.llm import LLMCompletionRequest
from incident_agent.utils.observability import get_logger

logger = get_logger(__name__)


class ChangeCorrelationService:
    """Service to parse git diffs, compare with incident telemetry, and produce evidence-backed fixes."""

    def __init__(
        self,
        provider: BaseLLMProvider | None = None,
        model_name: str | None = None,
    ) -> None:
        self.provider = provider
        self.model_name = model_name

    def correlate(
        self,
        *,
        raw_diff: str,
        logs: list[LogEvent] | None = None,
        metrics: list[MetricPoint] | None = None,
        anomalies: list[AnomalyCandidate] | None = None,
        summary: str = "",
    ) -> ChangeCorrelationResult:
        """Execute deterministic change correlation, and enrich via AI if provider is available."""
        if not raw_diff or not raw_diff.strip():
            return ChangeCorrelationResult(
                total_files_analyzed=0,
                total_hunks_analyzed=0,
                matches=[],
                top_correlated_change=None,
                overall_confidence=0.0,
                is_hypothesis=True,
                warning="No code diff provided. Change Impact Correlation skipped.",
            )

        changed_files = parse_git_diff(raw_diff)
        if not changed_files:
            return ChangeCorrelationResult(
                total_files_analyzed=0,
                total_hunks_analyzed=0,
                matches=[],
                top_correlated_change=None,
                overall_confidence=0.0,
                is_hypothesis=True,
                warning="Unable to extract changed files or hunks from provided diff text.",
            )

        total_hunks = sum(len(f.hunks) for f in changed_files)
        context = IncidentSignalContext.from_incident_data(
            logs=logs,
            metrics=metrics,
            anomalies=anomalies,
            summary=summary,
        )

        matches = rank_file_changes(changed_files, context)
        top_match = matches[0] if matches else None
        top_score = top_match.raw_score if top_match else 0.0
        confidence = compute_confidence(top_score)

        degraded_mode = False
        ai_enriched = False
        warning = None

        # Attempt AI enrichment if provider is configured and not mock
        if self.provider is not None and self.model_name and top_match:
            try:
                # Check if provider is available
                ai_prompt = (
                    f"Incident Summary: {summary or 'Service disruption'}\n"
                    f"Top Matched Code Change: {top_match.file_path}\n"
                    f"Matched Signals: {', '.join(top_match.matched_signals)}\n"
                    f"Telemetry Evidence: {top_match.evidence_context}\n"
                    "Explain concisely why this code change may be the root cause and provide a recommended fix."
                )
                response = self.provider.complete(
                    LLMCompletionRequest(prompt=ai_prompt, model=self.model_name)
                )
                if response and response.content:
                    top_match.explanation += f" [AI Insight: {response.content.strip()}]"
                    ai_enriched = True
            except Exception as exc:
                logger.warning("LLM enrichment failed for change correlation: %s", exc)
                degraded_mode = True
                warning = f"AI enrichment failed ({exc}). Analysis completed using deterministic evidence ranking."
        else:
            # Deterministic mode
            degraded_mode = False

        return ChangeCorrelationResult(
            total_files_analyzed=len(changed_files),
            total_hunks_analyzed=total_hunks,
            matches=matches,
            top_correlated_change=top_match,
            overall_confidence=confidence,
            is_hypothesis=True,
            degraded_mode=degraded_mode,
            ai_enriched=ai_enriched,
            warning=warning,
        )


def correlate_code_changes(
    raw_diff: str,
    logs: list[LogEvent] | None = None,
    metrics: list[MetricPoint] | None = None,
    anomalies: list[AnomalyCandidate] | None = None,
    summary: str = "",
    provider: BaseLLMProvider | None = None,
    model_name: str | None = None,
) -> ChangeCorrelationResult:
    """Convenience functional helper for Change Impact Correlation."""
    service = ChangeCorrelationService(provider=provider, model_name=model_name)
    return service.correlate(
        raw_diff=raw_diff,
        logs=logs,
        metrics=metrics,
        anomalies=anomalies,
        summary=summary,
    )

