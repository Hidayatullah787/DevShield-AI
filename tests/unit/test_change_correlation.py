"""Unit tests for DevShield Change Impact Correlation."""

from __future__ import annotations

from datetime import datetime
import pytest

from incident_agent.change_correlation.diff_parser import parse_git_diff, redact_secrets
from incident_agent.change_correlation.evidence_ranker import (
    IncidentSignalContext,
    compute_confidence,
    rank_file_changes,
)
from incident_agent.change_correlation.correlation_service import ChangeCorrelationService
from incident_agent.schemas.events import LogEvent, MetricPoint


SAMPLE_GIT_DIFF = """diff --git a/services/checkout/db_config.py b/services/checkout/db_config.py
index e69de29..d95f3ad 100644
--- a/services/checkout/db_config.py
+++ b/services/checkout/db_config.py
@@ -10,4 +10,4 @@
-POOL_TIMEOUT_SECONDS = 30
-MAX_CONNECTIONS = 50
+POOL_TIMEOUT_SECONDS = 2
+MAX_CONNECTIONS = 5
diff --git a/frontend/components/button.tsx b/frontend/components/button.tsx
index 1234567..89abcdef 100644
--- a/frontend/components/button.tsx
+++ b/frontend/components/button.tsx
@@ -5,2 +5,2 @@
-color: "blue"
+color: "red"
"""


def test_parse_git_diff_extracts_files_and_configs() -> None:
    files = parse_git_diff(SAMPLE_GIT_DIFF)
    assert len(files) == 2
    assert files[0].file_path == "services/checkout/db_config.py"
    assert len(files[0].hunks) == 1
    assert "POOL_TIMEOUT_SECONDS" in files[0].config_keys
    assert files[1].file_path == "frontend/components/button.tsx"


def test_diff_parser_redacts_secrets() -> None:
    secret_line = '+api_key = "ghp_1234567890abcdef1234567890abcdef"'
    redacted = redact_secrets(secret_line)
    assert "ghp_1234567890" not in redacted
    assert "[REDACTED_SECRET]" in redacted


def test_confidence_computation_formula() -> None:
    assert compute_confidence(0.0) == 0.0
    # score = 0.9 => 0.9 / (0.9 + 1.2) = 0.9 / 2.1 ~= 0.43
    assert compute_confidence(0.9) == 0.43
    # saturates at 0.95
    assert compute_confidence(100.0) == 0.95


def test_evidence_ranker_matches_database_timeout_incident() -> None:
    logs = [
        LogEvent(
            timestamp=datetime(2026, 3, 20, 10, 0),
            service="checkout",
            severity="ERROR",
            message="Database connection pool timeout while connecting to replica",
        )
    ]
    metrics = [
        MetricPoint(
            timestamp=datetime(2026, 3, 20, 10, 0),
            service="checkout",
            metric_name="request_latency_ms",
            value=3500.0,
        )
    ]

    files = parse_git_diff(SAMPLE_GIT_DIFF)
    context = IncidentSignalContext.from_incident_data(logs=logs, metrics=metrics)
    matches = rank_file_changes(files, context)

    assert len(matches) == 2
    # The checkout/db_config.py change should rank top due to service, config, and error term matches
    top = matches[0]
    assert top.file_path == "services/checkout/db_config.py"
    assert top.raw_score > matches[1].raw_score
    assert "checkout" in str(top.matched_signals)
    assert "timeout" in top.hypothesis.lower()
    assert "hypothesis" in top.hypothesis.lower() or "may be correlated" in top.hypothesis.lower()
    assert len(top.verification_tests) >= 2


def test_correlation_service_end_to_end() -> None:
    service = ChangeCorrelationService()
    logs = [
        LogEvent(
            timestamp=datetime(2026, 3, 20, 10, 0),
            service="checkout",
            severity="CRITICAL",
            message="Pool timeout: connection failed",
        )
    ]
    result = service.correlate(
        raw_diff=SAMPLE_GIT_DIFF,
        logs=logs,
        summary="Checkout service connection pool failures",
    )

    assert result.total_files_analyzed == 2
    assert result.top_correlated_change is not None
    assert result.top_correlated_change.file_path == "services/checkout/db_config.py"
    assert result.overall_confidence > 0.3
    assert result.is_hypothesis is True


def test_correlation_service_empty_diff_handled_gracefully() -> None:
    service = ChangeCorrelationService()
    result = service.correlate(raw_diff="")
    assert result.total_files_analyzed == 0
    assert result.matches == []
    assert result.top_correlated_change is None
    assert result.warning is not None
