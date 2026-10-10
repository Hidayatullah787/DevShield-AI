"""FastAPI application entrypoint for analysis workflows."""

from __future__ import annotations

import json
import logging
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime
from pathlib import Path
from time import perf_counter
from typing import Annotated, Any
from uuid import uuid4

from dataexcept import DataLoadingError
from fastapi import Depends, FastAPI, HTTPException, Query, Request
from fastapi.responses import Response
from pydantic import BaseModel, Field

from fastapi.middleware.cors import CORSMiddleware

from incident_agent import __version__
from incident_agent.agents.incident_agent import IncidentAnalysisAgent
from incident_agent.api.store import AnalysisJobRecord, AnalysisJobStore
from incident_agent.change_correlation.correlation_service import correlate_code_changes
from incident_agent.change_correlation.diff_parser import parse_git_diff
from incident_agent.change_correlation.models import ChangeCorrelationResult
from incident_agent.ingestion.text_parser import parse_raw_log_text
from incident_agent.core.settings import (
    load_observability_config,
    load_settings_from_yaml,
    load_webhook_export_config,
)
from incident_agent.export.webhook import (
    WebhookExportConfig,
    WebhookExportError,
    export_report_via_webhook,
)
from incident_agent.llm.factory import create_provider, load_llm_config
from incident_agent.schemas.anomaly import AnomalyCandidate
from incident_agent.schemas.events import LogEvent, MetricPoint
from incident_agent.schemas.final_report import FinalIncidentReport, ReviewStatus
from incident_agent.schemas.incident import CorrelatedIncidentCandidate
from incident_agent.schemas.pipeline import PipelineRunResult
from incident_agent.schemas.report import IncidentReport
from incident_agent.services.pipeline import run_pipeline_from_files
from incident_agent.utils.file_io import read_json
from incident_agent.utils.observability import (
    bind_context,
    configure_logging,
    get_logger,
    log_event,
)
from incident_agent.utils.security import (
    config_security_warnings,
    load_security_config_safe,
    require_read_path,
    require_write_path,
)

app = FastAPI(
    title="DevShield AI Incident Analysis Agent",
    version=__version__,
    description="DevShield AI: From production error to evidence-backed fix.",
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.state.job_store = AnalysisJobStore()
logger = get_logger(__name__)


def _setup_observability() -> None:
    try:
        config = load_observability_config()
        configure_logging(level=config.log_level, json_logs=config.json_logs)
    except Exception as error:
        configure_logging()
        log_event(
            logger,
            level=logging.WARNING,
            event="observability.config.fallback",
            message="failed to load observability config; using defaults",
            error_type=type(error).__name__,
            error=str(error),
        )


_setup_observability()


class ErrorResponse(BaseModel):
    """Standard API error payload."""

    detail: str


class AnalyzeRequest(BaseModel):
    """Request schema for ad hoc incident analysis."""

    logs: list[LogEvent]
    metrics: list[MetricPoint]


class AnalyzeResponse(BaseModel):
    """Response schema for ad hoc incident analysis."""

    reports: list[IncidentReport]


class PipelineAnalyzeRequest(BaseModel):
    """Request schema for full file-based pipeline execution."""

    logs_path: str
    metrics_path: str
    config_path: str = "configs/default.yaml"
    artifact_root: str = "artifacts/pipeline"
    bucket_size_minutes: int | None = None
    retrieval_enabled: bool | None = None
    knowledge_source_paths: list[str] | None = None
    metrics_source: str = "file"
    prometheus_url: str | None = None
    prometheus_step_seconds: int | None = None
    prometheus_queries: dict[str, str] | None = None


class ConfigInspectionResponse(BaseModel):
    """Config inspection response."""

    config_path: str
    config: dict[str, Any]
    warnings: list[str] = Field(default_factory=list)


class AnalysisJobSubmitRequest(BaseModel):
    """Job submission request for local file-based execution."""

    logs_path: str
    metrics_path: str
    config_path: str = "configs/default.yaml"
    artifact_root: str = "artifacts/pipeline"
    bucket_size_minutes: int | None = None
    retrieval_enabled: bool | None = None
    knowledge_source_paths: list[str] | None = None
    metrics_source: str = "file"
    prometheus_url: str | None = None
    prometheus_step_seconds: int | None = None
    prometheus_queries: dict[str, str] | None = None


class AnalysisJobStatusResponse(BaseModel):
    """Job status response."""

    job_id: str
    status: str
    created_at: str
    updated_at: str
    run_id: str | None = None
    artifact_dir: str | None = None
    error: str | None = None


class AnalysisJobReportsResponse(BaseModel):
    """Report retrieval response for a job."""

    job_id: str
    reports: list[FinalIncidentReport] = Field(default_factory=list)


class ReportReviewTransitionRequest(BaseModel):
    """Request payload for report review transitions."""

    to_status: ReviewStatus
    reviewer: str = Field(min_length=1)
    note: str = Field(min_length=1)


class ReportReviewTransitionResponse(BaseModel):
    """Response payload after report review transition."""

    job_id: str
    report: FinalIncidentReport


class IncidentListResponse(BaseModel):
    """Incident listing response."""

    incidents: list[CorrelatedIncidentCandidate] = Field(default_factory=list)


class AnomalyListResponse(BaseModel):
    """Anomaly listing response."""

    anomalies: list[AnomalyCandidate] = Field(default_factory=list)


class ReportWebhookExportRequest(BaseModel):
    """Webhook export request payload."""

    destination_url: str
    config_path: str = "configs/default.yaml"


class ReportWebhookExportResponse(BaseModel):
    """Webhook export response payload."""

    job_id: str
    incident_id: str
    delivery_id: str
    status: str
    attempts: int
    payload_id: str | None = None


def get_job_store(request: Request) -> AnalysisJobStore:
    """Dependency injection provider for job store."""

    store = request.app.state.job_store
    if not isinstance(store, AnalysisJobStore):
        raise RuntimeError("Application job store is not initialized.")
    return store


@app.middleware("http")
async def request_context_middleware(
    request: Request,
    call_next: Callable[[Request], Awaitable[Response]],
) -> Response:
    request_id = request.headers.get("x-request-id") or uuid4().hex
    start = perf_counter()
    with bind_context(request_id=request_id):
        log_event(
            logger,
            level=logging.INFO,
            event="api.request.started",
            message="api request started",
            method=request.method,
            path=request.url.path,
        )
        try:
            response = await call_next(request)
        except Exception as error:
            duration_ms = round((perf_counter() - start) * 1000, 2)
            log_event(
                logger,
                level=logging.ERROR,
                event="api.request.failed",
                message="api request failed",
                method=request.method,
                path=request.url.path,
                duration_ms=duration_ms,
                error_type=type(error).__name__,
                error=str(error),
            )
            raise
        duration_ms = round((perf_counter() - start) * 1000, 2)
        response.headers["x-request-id"] = request_id
        log_event(
            logger,
            level=logging.INFO,
            event="api.request.completed",
            message="api request completed",
            method=request.method,
            path=request.url.path,
            duration_ms=duration_ms,
            status_code=response.status_code,
        )
        return response


@app.get("/health", summary="Health check")
def health() -> dict[str, str]:
    """Simple health endpoint."""

    return {"status": "ok"}


@app.get(
    "/config",
    response_model=ConfigInspectionResponse,
    summary="Inspect loaded config",
    responses={400: {"model": ErrorResponse}},
)
def inspect_config(
    config_path: Annotated[
        str, Query(description="Path to YAML config file.")
    ] = "configs/default.yaml",
) -> ConfigInspectionResponse:
    """Inspect the YAML config used by local workflows."""

    try:
        security_config = load_security_config_safe("configs/default.yaml")
        path = require_read_path(config_path, config=security_config, workspace_root=Path.cwd())
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    try:
        loaded = load_settings_from_yaml(path)
    except DataLoadingError as error:
        if isinstance(error.original, FileNotFoundError):
            raise HTTPException(
                status_code=400, detail=f"Config path does not exist: {config_path}"
            ) from error
        raise HTTPException(status_code=400, detail=str(error)) from error
    return ConfigInspectionResponse(
        config_path=config_path,
        config=loaded,
        warnings=config_security_warnings(path),
    )


@app.post("/analyze", response_model=AnalyzeResponse, summary="Analyze ad hoc events")
def analyze(request: AnalyzeRequest) -> AnalyzeResponse:
    """Analyze a batch of logs and metrics."""

    config = load_llm_config()
    provider = create_provider(config, config_path="configs/default.yaml")
    agent = IncidentAnalysisAgent(provider=provider, report_model=config.report_model)
    reports = agent.analyze(logs=request.logs, metrics=request.metrics)
    return AnalyzeResponse(reports=reports)


@app.post(
    "/analyze-pipeline",
    response_model=PipelineRunResult,
    summary="Run full local pipeline directly",
    responses={400: {"model": ErrorResponse}},
)
def analyze_pipeline(request: PipelineAnalyzeRequest) -> PipelineRunResult:
    """Run full file-based pipeline and persist output artifacts."""

    try:
        workspace_root = Path.cwd()
        security_config = load_security_config_safe("configs/default.yaml")
        config_path = require_read_path(
            request.config_path, config=security_config, workspace_root=workspace_root
        )
        logs_path = require_read_path(
            request.logs_path,
            config=security_config,
            workspace_root=workspace_root,
        )
        metrics_path = require_read_path(
            request.metrics_path,
            config=security_config,
            workspace_root=workspace_root,
        )
        artifact_root = require_write_path(
            request.artifact_root,
            config=security_config,
            workspace_root=workspace_root,
        )
        return run_pipeline_from_files(
            log_path=str(logs_path),
            metric_path=str(metrics_path),
            config_path=str(config_path),
            artifact_root=str(artifact_root),
            bucket_size_minutes=request.bucket_size_minutes,
            retrieval_enabled=request.retrieval_enabled,
            knowledge_source_paths=request.knowledge_source_paths,
            metrics_source=request.metrics_source,
            prometheus_url=request.prometheus_url,
            prometheus_step_seconds=request.prometheus_step_seconds,
            prometheus_queries=request.prometheus_queries,
        )
    except Exception as error:
        raise HTTPException(
            status_code=400,
            detail=f"Pipeline execution failed: {error}",
        ) from error


@app.post(
    "/analysis-jobs",
    response_model=AnalysisJobStatusResponse,
    summary="Submit local incident analysis job",
    responses={400: {"model": ErrorResponse}},
)
def submit_analysis_job(
    request: AnalysisJobSubmitRequest,
    job_store: Annotated[AnalysisJobStore, Depends(get_job_store)],
) -> AnalysisJobStatusResponse:
    """Submit and execute a local file-based analysis job."""

    job = job_store.create_submitted_job()
    try:
        workspace_root = Path.cwd()
        security_config = load_security_config_safe("configs/default.yaml")
        config_path = require_read_path(
            request.config_path, config=security_config, workspace_root=workspace_root
        )
        logs_path = require_read_path(
            request.logs_path,
            config=security_config,
            workspace_root=workspace_root,
        )
        metrics_path = require_read_path(
            request.metrics_path,
            config=security_config,
            workspace_root=workspace_root,
        )
        artifact_root = require_write_path(
            request.artifact_root,
            config=security_config,
            workspace_root=workspace_root,
        )
        pipeline_result = run_pipeline_from_files(
            log_path=str(logs_path),
            metric_path=str(metrics_path),
            config_path=str(config_path),
            artifact_root=str(artifact_root),
            bucket_size_minutes=request.bucket_size_minutes,
            retrieval_enabled=request.retrieval_enabled,
            knowledge_source_paths=request.knowledge_source_paths,
            metrics_source=request.metrics_source,
            prometheus_url=request.prometheus_url,
            prometheus_step_seconds=request.prometheus_step_seconds,
            prometheus_queries=request.prometheus_queries,
        )
        incidents = _load_incidents(pipeline_result.artifact_dir)
        anomalies = _load_anomalies(pipeline_result.artifact_dir)
        completed = job_store.mark_completed(
            job_id=job.job_id,
            run_id=pipeline_result.run_id,
            artifact_dir=pipeline_result.artifact_dir,
            reports=pipeline_result.final_reports,
            incidents=incidents,
            anomalies=anomalies,
        )
        return _status_response(completed)
    except Exception as error:
        failed = job_store.mark_failed(job_id=job.job_id, error=str(error))
        raise HTTPException(
            status_code=400,
            detail=f"Job {failed.job_id} failed: {error}",
        ) from error


@app.get(
    "/analysis-jobs/{job_id}/reports",
    response_model=AnalysisJobReportsResponse,
    summary="Retrieve final reports for a submitted job",
    responses={404: {"model": ErrorResponse}},
)
def get_job_reports(
    job_id: str,
    job_store: Annotated[AnalysisJobStore, Depends(get_job_store)],
    review_status: Annotated[ReviewStatus | None, Query()] = None,
) -> AnalysisJobReportsResponse:
    """Retrieve generated final reports for a job."""

    job = job_store.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Job not found: {job_id}")
    reports = job.reports
    if review_status is not None:
        reports = [report for report in reports if report.review_status == review_status]
    return AnalysisJobReportsResponse(job_id=job_id, reports=reports)


@app.post(
    "/analysis-jobs/{job_id}/reports/{incident_id}/review",
    response_model=ReportReviewTransitionResponse,
    summary="Transition review status for one report",
    responses={400: {"model": ErrorResponse}, 404: {"model": ErrorResponse}},
)
def transition_job_report_review(
    job_id: str,
    incident_id: str,
    request: ReportReviewTransitionRequest,
    job_store: Annotated[AnalysisJobStore, Depends(get_job_store)],
) -> ReportReviewTransitionResponse:
    """Transition report lifecycle status and persist review metadata."""

    job = job_store.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Job not found: {job_id}")
    try:
        report = job_store.transition_report_review(
            job_id=job_id,
            incident_id=incident_id,
            to_status=request.to_status,
            reviewer=request.reviewer,
            note=request.note,
        )
    except KeyError:
        raise HTTPException(
            status_code=404,
            detail=f"Report not found for incident_id={incident_id}",
        ) from None
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    return ReportReviewTransitionResponse(job_id=job_id, report=report)


@app.post(
    "/analysis-jobs/{job_id}/reports/{incident_id}/export-webhook",
    response_model=ReportWebhookExportResponse,
    summary="Export approved report to generic webhook",
    responses={400: {"model": ErrorResponse}, 404: {"model": ErrorResponse}},
)
def export_job_report_webhook(
    job_id: str,
    incident_id: str,
    request: ReportWebhookExportRequest,
    job_store: Annotated[AnalysisJobStore, Depends(get_job_store)],
) -> ReportWebhookExportResponse:
    """Export one approved report and persist webhook delivery audit."""

    job = job_store.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Job not found: {job_id}")
    report = next((item for item in job.reports if item.incident_id == incident_id), None)
    if report is None:
        raise HTTPException(
            status_code=404,
            detail=f"Report not found for incident_id={incident_id}",
        )
    try:
        security_config = load_security_config_safe("configs/default.yaml")
        config_path = require_read_path(
            request.config_path, config=security_config, workspace_root=Path.cwd()
        )
        settings = load_webhook_export_config(config_path)
        audit_log_path = require_write_path(
            Path(job.artifact_dir or "artifacts/pipeline") / "exports" / "webhook_deliveries.jsonl",
            config=security_config,
            workspace_root=Path.cwd(),
        )
    except Exception as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    try:
        delivery = export_report_via_webhook(
            report=report,
            destination_url=request.destination_url,
            audit_log_path=audit_log_path,
            config=WebhookExportConfig(
                timeout_seconds=settings.timeout_seconds,
                max_retries=settings.max_retries,
                retry_backoff_seconds=settings.retry_backoff_seconds,
                allowed_urls=settings.allowed_urls,
                allowed_hosts=settings.allowed_hosts,
                allow_http=settings.allow_http,
                allow_private_networks=settings.allow_private_networks,
            ),
        )
    except WebhookExportError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    return ReportWebhookExportResponse(
        job_id=job_id,
        incident_id=incident_id,
        delivery_id=delivery.delivery_id,
        status=delivery.status,
        attempts=delivery.attempts,
        payload_id=delivery.payload_id,
    )


@app.get(
    "/incidents",
    response_model=IncidentListResponse,
    summary="List generated incident candidates",
    responses={404: {"model": ErrorResponse}},
)
def list_incidents(
    job_store: Annotated[AnalysisJobStore, Depends(get_job_store)],
    job_id: Annotated[str | None, Query(description="Optional job id filter.")] = None,
) -> IncidentListResponse:
    """List incidents for one job or all jobs."""

    if job_id:
        job = job_store.get(job_id)
        if job is None:
            raise HTTPException(status_code=404, detail=f"Job not found: {job_id}")
        return IncidentListResponse(incidents=job.incidents)

    incidents: list[CorrelatedIncidentCandidate] = []
    for job in job_store.list():
        incidents.extend(job.incidents)
    return IncidentListResponse(incidents=incidents)


@app.get(
    "/anomalies",
    response_model=AnomalyListResponse,
    summary="List generated anomalies",
    responses={404: {"model": ErrorResponse}},
)
def list_anomalies(
    job_store: Annotated[AnalysisJobStore, Depends(get_job_store)],
    job_id: Annotated[str | None, Query(description="Optional job id filter.")] = None,
) -> AnomalyListResponse:
    """List anomalies for one job or all jobs."""

    if job_id:
        job = job_store.get(job_id)
        if job is None:
            raise HTTPException(status_code=404, detail=f"Job not found: {job_id}")
        return AnomalyListResponse(anomalies=job.anomalies)

    anomalies: list[AnomalyCandidate] = []
    for job in job_store.list():
        anomalies.extend(job.anomalies)
    return AnomalyListResponse(anomalies=anomalies)


def _status_response(job: AnalysisJobRecord) -> AnalysisJobStatusResponse:
    return AnalysisJobStatusResponse(
        job_id=job.job_id,
        status=job.status,
        created_at=job.created_at.isoformat(),
        updated_at=job.updated_at.isoformat(),
        run_id=job.run_id,
        artifact_dir=job.artifact_dir,
        error=job.error,
    )


def _load_incidents(artifact_dir: str) -> list[CorrelatedIncidentCandidate]:
    path = Path(artifact_dir) / "incidents" / "incidents.json"
    if not path.exists():
        return []
    payload = read_json(path)
    rows = payload.get("incidents", [])
    if not isinstance(rows, list):
        return []
    return [CorrelatedIncidentCandidate.model_validate(item) for item in rows]


def _load_anomalies(artifact_dir: str) -> list[AnomalyCandidate]:
    path = Path(artifact_dir) / "anomalies" / "anomalies.json"
    if not path.exists():
        return []
    payload = read_json(path)
    rows = payload.get("anomalies", [])
    if not isinstance(rows, list):
        return []
    return [AnomalyCandidate.model_validate(item) for item in rows]


# =====================================================================
# DevShield AI Unified API Endpoints
# =====================================================================


class ApiInfoResponse(BaseModel):
    app_name: str = "DevShield AI"
    tagline: str = "From production error to evidence-backed fix."
    version: str
    status: str = "ready"
    ai_provider: dict[str, Any]
    features: list[str]
    total_investigations: int


class InputValidationRequest(BaseModel):
    raw_logs: str | None = None
    raw_diff: str | None = None
    service: str = "api-service"
    environment: str = "production"


class InputValidationResponse(BaseModel):
    valid: bool
    log_event_count: int
    detected_services: list[str] = Field(default_factory=list)
    has_diff: bool
    diff_file_count: int
    warnings: list[str] = Field(default_factory=list)


class ChangeCorrelationApiRequest(BaseModel):
    raw_diff: str
    logs: list[LogEvent] = Field(default_factory=list)
    raw_logs: str | None = None
    summary: str = ""


class InvestigateRequest(BaseModel):
    title: str = "Incident Investigation"
    service: str = "api-service"
    environment: str = "production"
    raw_logs: str | None = None
    logs: list[LogEvent] = Field(default_factory=list)
    raw_diff: str | None = None
    metrics: list[MetricPoint] = Field(default_factory=list)


class InvestigationSummary(BaseModel):
    job_id: str
    title: str
    service: str
    environment: str
    severity: str
    status: str
    created_at: str
    summary: str
    has_change_correlation: bool
    review_status: ReviewStatus


class InvestigationDetailResponse(BaseModel):
    job_id: str
    title: str
    service: str
    environment: str
    severity: str
    status: str
    created_at: str
    incident_summary: str
    report: IncidentReport
    final_report: FinalIncidentReport | None = None
    anomalies: list[AnomalyCandidate] = Field(default_factory=list)
    incidents: list[CorrelatedIncidentCandidate] = Field(default_factory=list)
    change_correlation: ChangeCorrelationResult | None = None
    review_status: ReviewStatus = "draft"
    ai_provider_info: dict[str, Any]


@app.get("/api-info", response_model=ApiInfoResponse, summary="DevShield AI platform status")
def get_api_info(
    job_store: Annotated[AnalysisJobStore, Depends(get_job_store)],
) -> ApiInfoResponse:
    """Return backend capabilities, active AI provider details, and system status."""
    try:
        config = load_llm_config()
        provider_name = config.provider
        model_name = config.report_model
    except Exception:
        provider_name = "mock"
        model_name = "gpt-4.1-mini"

    open_weight_model = "qwen2.5-coder:7b"
    return ApiInfoResponse(
        version=__version__,
        ai_provider={
            "provider_name": provider_name,
            "report_model": model_name,
            "open_weight_model": open_weight_model,
            "parameter_count": "<= 8B parameters (Hackathon compliant)" if provider_name != "openai" else "commercial",
            "model_license": "Apache 2.0" if "qwen" in model_name.lower() or "mistral" in model_name.lower() else "Evaluation / Open Source",
            "runtime": "Local Ollama / OpenAI-compatible / Deterministic Fallback",
            "degraded_mode": False,
            "deterministic_pipeline_active": True,
        },
        features=[
            "Incident Dashboard & Metrics Aggregation",
            "Multi-format Log Ingestion (JSONL, CSV, Plain Syslog)",
            "Heuristic & Statistical Anomaly Detection",
            "Root-Cause Analysis Engine (Graph & Dependency aware)",
            "Change Impact Correlation (Git Diff to Telemetry Match)",
            "Transparent Rule-Based Evidence Ranking",
            "Auditable Report Review & Webhook Export",
        ],
        total_investigations=len(job_store.list()),
    )


@app.post("/validate-input", response_model=InputValidationResponse, summary="Validate logs and diffs")
def validate_input(request: InputValidationRequest) -> InputValidationResponse:
    """Validate pasted or uploaded log events and git diff before starting investigation."""
    warnings: list[str] = []
    events = parse_raw_log_text(request.raw_logs or "", default_service=request.service, default_env=request.environment)
    services = sorted({e.service for e in events})

    if not events and not request.raw_diff:
        warnings.append("No logs or code diff provided.")

    diff_files = 0
    if request.raw_diff and request.raw_diff.strip():
        parsed_files = parse_git_diff(request.raw_diff)
        diff_files = len(parsed_files)
        if diff_files == 0:
            warnings.append("Git diff could not be structured into hunks; treating as raw code snippet.")

    return InputValidationResponse(
        valid=len(events) > 0 or diff_files > 0,
        log_event_count=len(events),
        detected_services=services,
        has_diff=bool(request.raw_diff and request.raw_diff.strip()),
        diff_file_count=diff_files,
        warnings=warnings,
    )


@app.post("/correlate-change", response_model=ChangeCorrelationResult, summary="Correlate code diff with signals")
def correlate_change(request: ChangeCorrelationApiRequest) -> ChangeCorrelationResult:
    """Run Change Impact Correlation between provided git diff and incident telemetry."""
    logs = list(request.logs)
    if request.raw_logs and not logs:
        logs = parse_raw_log_text(request.raw_logs)

    try:
        config = load_llm_config()
        provider = create_provider(config, config_path="configs/default.yaml")
    except Exception:
        provider = None
        config = None

    return correlate_code_changes(
        raw_diff=request.raw_diff,
        logs=logs,
        summary=request.summary,
        provider=provider,
        model_name=config.completion_model if config else None,
    )


@app.post("/investigate", response_model=InvestigationDetailResponse, summary="Start complete investigation")
def investigate(
    request: InvestigateRequest,
    job_store: Annotated[AnalysisJobStore, Depends(get_job_store)],
) -> InvestigationDetailResponse:
    """Execute end-to-end incident investigation: logs + metrics + RCA + Change Impact Correlation."""
    logs = list(request.logs)
    if request.raw_logs and not logs:
        logs = parse_raw_log_text(request.raw_logs, default_service=request.service, default_env=request.environment)

    if not logs:
        # Create a synthetic fallback error event if only diff or service was provided
        logs = [
            LogEvent(
                timestamp=datetime.now(UTC),
                service=request.service,
                severity="ERROR",
                message=f"Reported incident anomaly on service '{request.service}'",
                metadata={"env": request.environment},
            )
        ]

    # Analyze logs and metrics
    try:
        config = load_llm_config()
        provider = create_provider(config, config_path="configs/default.yaml")
    except Exception:
        from incident_agent.llm.mock import MockLLMProvider
        provider = MockLLMProvider()
        config = None

    agent = IncidentAnalysisAgent(
        provider=provider,
        report_model=config.report_model if config else "gpt-4.1-mini",
    )
    reports = agent.analyze(logs=logs, metrics=request.metrics)
    primary_report = reports[0] if reports else IncidentReport(
        title=request.title,
        severity="HIGH",
        impacted_service=request.service,
        incident_summary="Service disruption detected from supplied telemetry.",
        likely_root_causes=["Unhandled exception or connection failure in application stack."],
        recommended_actions=["Verify service health and compare recent deployments."],
        evidence=[],
    )

    # Change correlation if diff provided
    change_result: ChangeCorrelationResult | None = None
    if request.raw_diff and request.raw_diff.strip():
        change_result = correlate_code_changes(
            raw_diff=request.raw_diff,
            logs=logs,
            metrics=request.metrics,
            summary=primary_report.incident_summary,
            provider=provider,
            model_name=config.completion_model if config else None,
        )

    # Persist in job store
    job = job_store.create_submitted_job()
    final_rep = FinalIncidentReport(
        incident_id=f"inc-{job.job_id}",
        incident_summary=primary_report.incident_summary,
        root_cause_explanation="; ".join(primary_report.likely_root_causes),
        executive_summary=primary_report.title,
        engineering_handoff="; ".join(primary_report.recommended_actions),
        remediation_suggestions=primary_report.recommended_actions,
        facts=[e.content for e in primary_report.evidence],
        inferences=primary_report.likely_root_causes,
        uncertainties=["Hypothesis generated via heuristic & telemetry analysis; operational verification required."],
        citations=[e.content[:60] for e in primary_report.evidence],
        review_status="draft",
    )
    job_store.mark_completed(
        job_id=job.job_id,
        run_id=job.job_id,
        artifact_dir="artifacts/memory",
        reports=[final_rep],
        incidents=[],
        anomalies=[],
        change_correlation=change_result,
        service=request.service,
        environment=request.environment,
    )

    # Extract max severity
    severities = [l.severity for l in logs]
    highest_sev = "CRITICAL" if "CRITICAL" in severities else "HIGH" if "ERROR" in severities else "MEDIUM" if "WARN" in severities else "LOW"

    return InvestigationDetailResponse(
        job_id=job.job_id,
        title=primary_report.title or request.title,
        service=request.service,
        environment=request.environment,
        severity=highest_sev,
        status="completed",
        created_at=job.created_at.isoformat(),
        incident_summary=primary_report.incident_summary,
        report=primary_report,
        final_report=final_rep,
        anomalies=[],
        incidents=[],
        change_correlation=change_result,
        review_status="draft",
        ai_provider_info={
            "provider": config.provider if config else "mock",
            "model": config.report_model if config else "mock",
            "degraded_mode": change_result.degraded_mode if change_result else False,
            "warning": change_result.warning if change_result else None,
        },
    )


@app.get("/investigations", response_model=list[InvestigationSummary], summary="List all investigations")
def list_investigations(
    job_store: Annotated[AnalysisJobStore, Depends(get_job_store)],
    service: Annotated[str | None, Query(description="Filter by service name.")] = None,
    severity: Annotated[str | None, Query(description="Filter by severity.")] = None,
) -> list[InvestigationSummary]:
    """List completed and in-progress investigations."""
    summaries: list[InvestigationSummary] = []
    for job in reversed(job_store.list()):
        svc = job.service or "api-service"
        if service and service.lower() != svc.lower():
            continue
        report = job.reports[0] if job.reports else None
        sev = "HIGH"
        review_status: ReviewStatus = report.review_status if report else "draft"
        summary_text = report.incident_summary if report else "Investigation submitted"

        summaries.append(
            InvestigationSummary(
                job_id=job.job_id,
                title=report.executive_summary if report else f"Investigation {job.job_id}",
                service=svc,
                environment=job.environment or "production",
                severity=sev,
                status=job.status,
                created_at=job.created_at.isoformat(),
                summary=summary_text,
                has_change_correlation=job.change_correlation is not None,
                review_status=review_status,
            )
        )
    return summaries


@app.get("/investigations/{job_id}", response_model=InvestigationDetailResponse, summary="Get investigation details")
def get_investigation_detail(
    job_id: str,
    job_store: Annotated[AnalysisJobStore, Depends(get_job_store)],
) -> InvestigationDetailResponse:
    """Retrieve full details of an investigation."""
    job = job_store.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Investigation not found: {job_id}")

    final_rep = job.reports[0] if job.reports else None
    rep = IncidentReport(
        title=final_rep.executive_summary if final_rep else f"Job {job_id}",
        severity="HIGH",
        impacted_service=job.service or "api-service",
        incident_summary=final_rep.incident_summary if final_rep else "No summary available",
        likely_root_causes=final_rep.inferences if final_rep else [],
        recommended_actions=final_rep.remediation_suggestions if final_rep else [],
        evidence=[],
    )

    return InvestigationDetailResponse(
        job_id=job.job_id,
        title=final_rep.executive_summary if final_rep else f"Job {job_id}",
        service=job.service or "api-service",
        environment=job.environment or "production",
        severity="HIGH",
        status=job.status,
        created_at=job.created_at.isoformat(),
        incident_summary=final_rep.incident_summary if final_rep else "",
        report=rep,
        final_report=final_rep,
        anomalies=job.anomalies,
        incidents=job.incidents,
        change_correlation=job.change_correlation,
        review_status=final_rep.review_status if final_rep else "draft",
        ai_provider_info={"provider": "mock", "degraded_mode": False},
    )


@app.post("/investigations/{job_id}/review", summary="Update investigation review status")
def update_investigation_review(
    job_id: str,
    request: ReportReviewTransitionRequest,
    job_store: Annotated[AnalysisJobStore, Depends(get_job_store)],
) -> dict[str, Any]:
    """Transition review status for an investigation."""
    job = job_store.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Investigation not found: {job_id}")
    if not job.reports:
        raise HTTPException(status_code=400, detail="Investigation has no reports to review")

    incident_id = job.reports[0].incident_id
    updated = job_store.transition_report_review(
        job_id=job_id,
        incident_id=incident_id,
        to_status=request.to_status,
        reviewer=request.reviewer,
        note=request.note,
    )
    return {
        "job_id": job_id,
        "incident_id": incident_id,
        "review_status": updated.review_status,
        "reviewer": request.reviewer,
        "note": request.note,
    }


@app.get("/investigations/{job_id}/export/{format}", summary="Export investigation report")
def export_investigation(
    job_id: str,
    format: str,
    job_store: Annotated[AnalysisJobStore, Depends(get_job_store)],
) -> Response:
    """Export investigation report in Markdown or JSON format."""
    job = job_store.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Investigation not found: {job_id}")

    final_rep = job.reports[0] if job.reports else None
    corr = job.change_correlation

    if format.lower() in {"json"}:
        data = {
            "job_id": job.job_id,
            "created_at": job.created_at.isoformat(),
            "service": job.service,
            "environment": job.environment,
            "report": final_rep.model_dump(mode="json") if final_rep else None,
            "change_correlation": corr.model_dump(mode="json") if corr else None,
        }
        return Response(content=json.dumps(data, indent=2), media_type="application/json")

    # Markdown export
    lines: list[str] = [
        f"# DevShield AI Investigation Report: {job.job_id}",
        "",
        f"**Service:** {job.service or 'api-service'} | **Environment:** {job.environment or 'production'} | **Status:** {final_rep.review_status if final_rep else 'draft'}",
        f"**Timestamp:** {job.created_at.isoformat()}",
        "",
        "## 1. Executive Summary",
        final_rep.incident_summary if final_rep else "Service disruption under investigation.",
        "",
        "## 2. Likely Root-Cause Hypotheses",
    ]
    if final_rep and final_rep.inferences:
        for rca in final_rep.inferences:
            lines.append(f"- {rca}")
    else:
        lines.append("- Telemetry signals indicate anomalous error rates.")

    lines.extend([
        "",
        "## 3. Change Impact Correlation (Code Changes)",
    ])
    if corr and corr.matches:
        lines.append(f"Analyzed {corr.total_files_analyzed} files ({corr.total_hunks_analyzed} hunks). Overall confidence: {int(corr.overall_confidence * 100)}%.")
        lines.append(f"Confidence formula: {corr.confidence_calculation_method}")
        lines.append("")
        for m in corr.matches:
            lines.append(f"### File: `{m.file_path}` (Match Category: {m.match_category})")
            lines.append(f"**Hypothesis:** {m.hypothesis}")
            lines.append(f"**Why Flagged:** {m.explanation}")
            lines.append(f"**Suggested Fix:** {m.suggested_fix}")
            lines.append("**Verification Tests:**")
            for t in m.verification_tests:
                lines.append(f"  - {t}")
            lines.append("")
    else:
        lines.append("No code diff provided or correlated with this investigation.")

    lines.extend([
        "## 4. Remediation Actions",
    ])
    if final_rep and final_rep.remediation_suggestions:
        for act in final_rep.remediation_suggestions:
            lines.append(f"- {act}")
    else:
        lines.append("- Inspect recent production deployments and infrastructure telemetry.")

    lines.extend([
        "",
        "---",
        "*Report generated by DevShield AI — Safe investigation assistant. Never auto-executes code in production.*",
    ])
    return Response(content="\n".join(lines), media_type="text/markdown")


@app.post("/seed-samples", summary="Seed sample investigations for demonstration")
def seed_sample_investigations(
    job_store: Annotated[AnalysisJobStore, Depends(get_job_store)],
) -> dict[str, Any]:
    """Seed sample realistic incident investigations into job store."""
    sample_diff = (
        "diff --git a/services/checkout/db_config.py b/services/checkout/db_config.py\n"
        "--- a/services/checkout/db_config.py\n"
        "+++ b/services/checkout/db_config.py\n"
        "@@ -15,3 +15,3 @@\n"
        "-POOL_TIMEOUT_SECONDS = 30\n"
        "+POOL_TIMEOUT_SECONDS = 2\n"
        "-MAX_CONNECTIONS = 50\n"
        "+MAX_CONNECTIONS = 5\n"
    )
    sample_logs = (
        '{"timestamp":"2026-03-20T10:00:00","service":"checkout","severity":"ERROR","message":"Database connection pool timeout while connecting to replica","metadata":{"env":"prod"}}\n'
        '{"timestamp":"2026-03-20T10:01:00","service":"checkout","severity":"CRITICAL","message":"Connection pool exhausted: HTTP 503 Service Unavailable","metadata":{"env":"prod"}}\n'
    )
    req = InvestigateRequest(
        title="Checkout Service Connection Pool Exhaustion",
        service="checkout",
        environment="production",
        raw_logs=sample_logs,
        raw_diff=sample_diff,
    )
    res = investigate(req, job_store=job_store)
    return {"status": "seeded", "sample_job_id": res.job_id}

