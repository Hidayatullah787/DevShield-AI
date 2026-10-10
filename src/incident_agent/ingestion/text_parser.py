"""Helper to parse raw pasted text logs (JSONL, CSV, or syslog format) into LogEvents."""

from __future__ import annotations

import csv
import io
import json
import re
from datetime import UTC, datetime

from incident_agent.schemas.events import LogEvent

TIMESTAMP_REGEX = re.compile(
    r"\b(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)\b"
)
SEVERITY_REGEX = re.compile(r"\b(CRITICAL|FATAL|ERROR|WARN|WARNING|INFO|DEBUG)\b", re.IGNORECASE)
SERVICE_REGEX = re.compile(r"\[([a-zA-Z0-9_\-\.]{2,40})\]|\b(?:service|svc|app)=([a-zA-Z0-9_\-\.]{2,40})")


def parse_raw_log_text(
    raw_text: str,
    default_service: str = "api-service",
    default_env: str = "production",
) -> list[LogEvent]:
    """Parse text containing log records into structured LogEvent objects."""
    if not raw_text or not raw_text.strip():
        return []

    lines = [line.strip() for line in raw_text.strip().splitlines() if line.strip()]
    events: list[LogEvent] = []

    # Attempt 1: Check if content is CSV with header
    if len(lines) > 1 and ("," in lines[0] or "\t" in lines[0]) and ("timestamp" in lines[0].lower() or "message" in lines[0].lower()):
        try:
            reader = csv.DictReader(io.StringIO(raw_text))
            for row in reader:
                ts_str = row.get("timestamp") or row.get("time") or row.get("datetime")
                ts = datetime.now(UTC)
                if ts_str:
                    try:
                        ts = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
                    except Exception:
                        pass
                svc = row.get("service") or row.get("app") or default_service
                sev_raw = (row.get("severity") or row.get("level") or "INFO").upper()
                sev = "ERROR" if sev_raw in {"FATAL", "CRITICAL"} else sev_raw if sev_raw in {"DEBUG", "INFO", "WARN", "ERROR", "CRITICAL"} else "INFO"
                msg = row.get("message") or row.get("msg") or row.get("log") or str(row)
                events.append(
                    LogEvent(
                        timestamp=ts,
                        service=svc,
                        severity=sev,  # type: ignore[arg-type]
                        message=msg,
                        metadata={"env": default_env},
                    )
                )
            if events:
                return events
        except Exception:
            pass

    # Attempt 2: Line by line (JSON or plain text)
    for idx, line in enumerate(lines):
        # Check if line is JSON
        if line.startswith("{") and line.endswith("}"):
            try:
                data = json.loads(line)
                if isinstance(data, dict):
                    ts_str = data.get("timestamp") or data.get("time") or data.get("@timestamp")
                    ts = datetime.now(UTC)
                    if ts_str and isinstance(ts_str, str):
                        try:
                            ts = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
                        except Exception:
                            pass
                    svc = data.get("service") or data.get("app") or default_service
                    sev_raw = str(data.get("severity") or data.get("level") or "INFO").upper()
                    sev = "CRITICAL" if sev_raw in {"FATAL", "CRITICAL"} else sev_raw if sev_raw in {"DEBUG", "INFO", "WARN", "ERROR", "CRITICAL"} else "INFO"
                    msg = data.get("message") or data.get("msg") or data.get("log") or line
                    meta = data.get("metadata") if isinstance(data.get("metadata"), dict) else {"env": default_env}
                    events.append(
                        LogEvent(
                            timestamp=ts,
                            service=str(svc),
                            severity=sev,  # type: ignore[arg-type]
                            message=str(msg),
                            trace_id=str(data.get("trace_id")) if data.get("trace_id") else None,
                            metadata=meta,
                        )
                    )
                    continue
            except Exception:
                pass

        # Plain text log format
        ts_match = TIMESTAMP_REGEX.search(line)
        ts = datetime.now(UTC)
        if ts_match:
            try:
                clean_ts = ts_match.group(1).replace(" ", "T")
                ts = datetime.fromisoformat(clean_ts)
            except Exception:
                pass

        sev_match = SEVERITY_REGEX.search(line)
        sev_raw = sev_match.group(1).upper() if sev_match else "INFO"
        sev = "WARN" if sev_raw == "WARNING" else "CRITICAL" if sev_raw in {"FATAL", "CRITICAL"} else sev_raw if sev_raw in {"DEBUG", "INFO", "WARN", "ERROR", "CRITICAL"} else "INFO"

        svc_match = SERVICE_REGEX.search(line)
        svc = default_service
        if svc_match:
            svc = svc_match.group(1) or svc_match.group(2) or default_service

        events.append(
            LogEvent(
                timestamp=ts,
                service=svc,
                severity=sev,  # type: ignore[arg-type]
                message=line,
                metadata={"env": default_env},
            )
        )

    return events

