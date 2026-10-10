"""Deterministic rule-based evidence ranker for correlating code changes with incident signals."""

from __future__ import annotations

import re
from typing import Any

from incident_agent.change_correlation.models import (
    ChangedFile,
    CorrelationMatch,
)
from incident_agent.schemas.anomaly import AnomalyCandidate
from incident_agent.schemas.events import LogEvent, MetricPoint

ERROR_KEYWORD_PATTERNS = [
    re.compile(r"(?i)\b(timeout|timed out|latency|slow|lag)\b"),
    re.compile(r"(?i)\b(connection|connect|handshake|disconnect|pool|socket)\b"),
    re.compile(r"(?i)\b(refused|rejected|dropped|exhausted|overflow)\b"),
    re.compile(r"(?i)\b(500|502|503|504|429|401|403|5xx)\b"),
    re.compile(r"(?i)\b(deadlock|lock|blocked|wait|contention)\b"),
    re.compile(r"(?i)\b(null|undefined|none|nil|segfault|panic|exception|error|fail)\b"),
    re.compile(r"(?i)\b(memory|oom|heap|leak|cpu|disk|saturation)\b"),
    re.compile(r"(?i)\b(replica|primary|database|postgres|mysql|redis|mongo)\b"),
]


class IncidentSignalContext:
    """Consolidated signals gathered from logs, metrics, anomalies, and reports."""

    def __init__(
        self,
        services: set[str],
        error_terms: set[str],
        raw_error_messages: list[str],
        anomalies: list[str],
    ) -> None:
        self.services = {s.lower() for s in services if s and s.lower() != "global"}
        self.error_terms = {t.lower() for t in error_terms if len(t) >= 3}
        self.raw_error_messages = raw_error_messages
        self.anomalies = anomalies

    @classmethod
    def from_incident_data(
        cls,
        logs: list[LogEvent] | None = None,
        metrics: list[MetricPoint] | None = None,
        anomalies: list[AnomalyCandidate] | None = None,
        summary: str = "",
    ) -> IncidentSignalContext:
        services: set[str] = set()
        error_terms: set[str] = set()
        raw_messages: list[str] = []
        anomaly_summaries: list[str] = []

        if logs:
            for log in logs:
                services.add(log.service)
                if log.severity in {"ERROR", "CRITICAL", "WARN"}:
                    raw_messages.append(f"[{log.severity}] {log.service}: {log.message}")
                    for pat in ERROR_KEYWORD_PATTERNS:
                        for match in pat.findall(log.message):
                            error_terms.add(match)
                    words = re.findall(r"\b[a-zA-Z0-9_\-\.]{3,30}\b", log.message)
                    for w in words:
                        if not w.isnumeric():
                            error_terms.add(w)

        if metrics:
            for m in metrics:
                services.add(m.service)
                error_terms.add(m.metric_name)

        if anomalies:
            for a in anomalies:
                services.add(a.affected_service)
                anomaly_summaries.append(f"{a.anomaly_type} on {a.affected_service}")
                error_terms.add(a.anomaly_type)

        if summary:
            for pat in ERROR_KEYWORD_PATTERNS:
                for match in pat.findall(summary):
                    error_terms.add(match)

        return cls(
            services=services,
            error_terms=error_terms,
            raw_error_messages=raw_messages[:10],
            anomalies=anomaly_summaries[:5],
        )


def rank_file_changes(
    changed_files: list[ChangedFile],
    context: IncidentSignalContext,
) -> list[CorrelationMatch]:
    """Score each changed file against incident signals and return sorted matches."""
    matches: list[CorrelationMatch] = []

    for file in changed_files:
        score = 0.0
        matched_signals: list[str] = []
        explanation_points: list[str] = []
        primary_match_category = "component_path"
        matched_context = ""

        file_path_lower = file.file_path.lower()

        # 1. Service identity check (+0.35)
        for svc in context.services:
            clean_svc = svc.replace("_", "").replace("-", "")
            clean_path = file_path_lower.replace("_", "").replace("-", "")
            if svc in file_path_lower or clean_svc in clean_path:
                score += 0.35
                matched_signals.append(f"service:{svc}")
                explanation_points.append(
                    f"File path or module directly matches impacted service '{svc}' (+0.35)."
                )
                primary_match_category = "service_identity"
                break
            # Check if service was in added/removed lines
            added_text = " ".join(" ".join(h.added_lines) for h in file.hunks).lower()
            if svc in added_text:
                score += 0.35
                matched_signals.append(f"service_in_diff:{svc}")
                explanation_points.append(
                    f"Diff references impacted service '{svc}' (+0.35)."
                )
                primary_match_category = "service_identity"
                break

        # 2. Configuration key check (+0.30)
        found_configs: list[str] = []
        for cfg in file.config_keys:
            cfg_lower = cfg.lower()
            for err in context.error_terms:
                if err in cfg_lower or cfg_lower in err:
                    found_configs.append(cfg)
                    break
        if found_configs:
            score += 0.30
            matched_signals.extend(found_configs[:3])
            explanation_points.append(
                f"Diff modifies sensitive configuration keys matching incident keywords: {', '.join(found_configs[:3])} (+0.30)."
            )
            primary_match_category = "configuration_key"
        elif file.config_keys:
            # Modified config keys even if indirect
            score += 0.15
            matched_signals.extend(file.config_keys[:2])
            explanation_points.append(
                f"Diff modifies runtime configuration keys: {', '.join(file.config_keys[:2])} (+0.15)."
            )

        # 3. Error keyword overlap (+0.25)
        overlap_keywords: list[str] = []
        file_tokens = {tok.lower() for tok in file.extracted_identifiers}
        for kw in context.error_terms:
            if kw in file_tokens:
                overlap_keywords.append(kw)
        if overlap_keywords:
            score += 0.25
            matched_signals.extend(overlap_keywords[:4])
            explanation_points.append(
                f"Identifiers in diff match incident error terms: {', '.join(overlap_keywords[:4])} (+0.25)."
            )
            if primary_match_category not in {"service_identity", "configuration_key"}:
                primary_match_category = "error_keyword"

        # 4. Relevant error message matching
        if context.raw_error_messages:
            for msg in context.raw_error_messages:
                # check if file path or tokens match
                if any(sig.lower() in msg.lower() for sig in matched_signals):
                    matched_context = msg
                    break
            if not matched_context:
                matched_context = context.raw_error_messages[0]
        elif context.anomalies:
            matched_context = context.anomalies[0]
        else:
            matched_context = "Observed incident telemetry."

        if not explanation_points:
            explanation_points.append("Diff changed code in related application module.")

        summary_added = sum(len(h.added_lines) for h in file.hunks)
        summary_removed = sum(len(h.removed_lines) for h in file.hunks)
        change_summary = f"{file.file_path} (+{summary_added}, -{summary_removed} lines)"

        hypothesis = (
            f"The change in '{file.file_path}' may be correlated with the incident. "
            f"Evidence: modified signals [{', '.join(matched_signals[:3]) or 'code changes'}] align with "
            f"observed errors in '{matched_context}'. Verify effective runtime configuration and compare failures."
        )

        suggested_fix = (
            f"Inspect recent code change in '{file.file_path}'. "
            f"If {', '.join(found_configs or matched_signals[:2]) or 'new logic'} caused regression, "
            f"consider restoring previous configuration bounds or introducing defensive fallbacks."
        )

        verification_tests = [
            f"Run targeted unit/integration tests for '{file.file_path}'.",
            "Simulate failure conditions in staging environment with synthetic load.",
            "Compare error rates and response latencies before and after applying the commit.",
        ]

        match = CorrelationMatch(
            file_path=file.file_path,
            change_summary=change_summary,
            matched_signals=matched_signals,
            match_category=primary_match_category,  # type: ignore[arg-type]
            evidence_context=matched_context,
            raw_score=round(score, 3),
            hypothesis=hypothesis,
            explanation="; ".join(explanation_points),
            suggested_fix=suggested_fix,
            verification_tests=verification_tests,
        )
        matches.append(match)

    matches.sort(key=lambda m: (-m.raw_score, m.file_path))
    return matches


def compute_confidence(top_score: float) -> float:
    """
    Deterministic confidence calculation.
    Uses saturating function: min(0.95, round(top_score / (top_score + 1.2), 2)).
    """
    if top_score <= 0.0:
        return 0.0
    return min(0.95, round(top_score / (top_score + 1.2), 2))
