"""Domain models and schemas for Change Impact Correlation."""

from __future__ import annotations

from typing import Literal
from pydantic import BaseModel, Field


class ChangedHunk(BaseModel):
    """Represents a contiguous block of modified lines in a file diff."""

    old_start: int = 1
    old_lines: int = 0
    new_start: int = 1
    new_lines: int = 0
    header: str = ""
    added_lines: list[str] = Field(default_factory=list)
    removed_lines: list[str] = Field(default_factory=list)


class ChangedFile(BaseModel):
    """Represents a file changed in a git diff."""

    file_path: str
    change_type: Literal["modified", "added", "deleted", "renamed"] = "modified"
    hunks: list[ChangedHunk] = Field(default_factory=list)
    extracted_identifiers: list[str] = Field(default_factory=list)
    config_keys: list[str] = Field(default_factory=list)


class CorrelationMatch(BaseModel):
    """Represents a single correlation between a code change and incident evidence."""

    file_path: str
    change_summary: str
    matched_signals: list[str] = Field(default_factory=list)
    match_category: Literal[
        "service_identity",
        "configuration_key",
        "error_keyword",
        "exception_symbol",
        "component_path",
    ]
    evidence_context: str
    raw_score: float
    hypothesis: str
    explanation: str
    suggested_fix: str
    verification_tests: list[str] = Field(default_factory=list)


class ChangeCorrelationResult(BaseModel):
    """Overall outcome of Change Impact Correlation."""

    total_files_analyzed: int = 0
    total_hunks_analyzed: int = 0
    matches: list[CorrelationMatch] = Field(default_factory=list)
    top_correlated_change: CorrelationMatch | None = None
    overall_confidence: float = 0.0
    confidence_calculation_method: str = (
        "Rational saturating score function: confidence = min(0.95, round(top_score / (top_score + 1.2), 2)). "
        "Weights: Service match = 0.35, Config key = 0.30, Error keyword = 0.25, Anomaly/Path match = 0.15."
    )
    is_hypothesis: bool = True
    degraded_mode: bool = False
    ai_enriched: bool = False
    warning: str | None = None
