"""DevShield AI Change Impact Correlation package."""

from incident_agent.change_correlation.correlation_service import ChangeCorrelationService
from incident_agent.change_correlation.diff_parser import parse_git_diff
from incident_agent.change_correlation.evidence_ranker import (
    IncidentSignalContext,
    compute_confidence,
    rank_file_changes,
)
from incident_agent.change_correlation.models import (
    ChangeCorrelationResult,
    ChangedFile,
    ChangedHunk,
    CorrelationMatch,
)

__all__ = [
    "ChangeCorrelationResult",
    "ChangedFile",
    "ChangedHunk",
    "CorrelationMatch",
    "ChangeCorrelationService",
    "IncidentSignalContext",
    "parse_git_diff",
    "rank_file_changes",
    "compute_confidence",
]
