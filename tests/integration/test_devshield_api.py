"""Integration tests for DevShield AI API endpoints."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from incident_agent.api.main import app

client = TestClient(app)


def test_api_info_endpoint() -> None:
    response = client.get("/api-info")
    assert response.status_code == 200
    data = response.json()
    assert data["app_name"] == "DevShield AI"
    assert "ai_provider" in data
    assert data["ai_provider"]["parameter_count"] == "<= 8B parameters (Hackathon compliant)"
    assert len(data["features"]) >= 5


def test_validate_input_with_logs_and_diff() -> None:
    diff_text = """diff --git a/service/db.py b/service/db.py
--- a/service/db.py
+++ b/service/db.py
@@ -1,2 +1,2 @@
-timeout = 30
+timeout = 2
"""
    logs_text = "2026-03-20T10:00:00 [ERROR] [checkout] Database timeout connecting to replica"
    response = client.post(
        "/validate-input",
        json={"raw_logs": logs_text, "raw_diff": diff_text, "service": "checkout"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["valid"] is True
    assert data["log_event_count"] >= 1
    assert data["has_diff"] is True
    assert data["diff_file_count"] == 1


def test_correlate_change_endpoint() -> None:
    diff_text = """diff --git a/checkout/db.py b/checkout/db.py
--- a/checkout/db.py
+++ b/checkout/db.py
@@ -10,2 +10,2 @@
-POOL_TIMEOUT = 30
+POOL_TIMEOUT = 1
"""
    logs_text = "2026-03-20T10:00:00 [ERROR] [checkout] Database POOL_TIMEOUT while connecting"
    response = client.post(
        "/correlate-change",
        json={
            "raw_diff": diff_text,
            "raw_logs": logs_text,
            "summary": "Checkout connection timeout failure",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["total_files_analyzed"] == 1
    assert data["top_correlated_change"] is not None
    assert data["top_correlated_change"]["file_path"] == "checkout/db.py"
    assert data["is_hypothesis"] is True


def test_investigate_workflow_end_to_end() -> None:
    diff_text = """diff --git a/services/auth/tokens.py b/services/auth/tokens.py
--- a/services/auth/tokens.py
+++ b/services/auth/tokens.py
@@ -5,2 +5,2 @@
-TOKEN_TTL_SECONDS = 3600
+TOKEN_TTL_SECONDS = 10
"""
    logs_text = (
        '{"timestamp":"2026-03-20T10:00:00","service":"auth","severity":"ERROR","message":"Token expired or rejected for session"}\n'
        '{"timestamp":"2026-03-20T10:01:00","service":"auth","severity":"CRITICAL","message":"High volume of auth failures HTTP 401"}\n'
    )
    response = client.post(
        "/investigate",
        json={
            "title": "Auth Token Spike Incident",
            "service": "auth",
            "environment": "production",
            "raw_logs": logs_text,
            "raw_diff": diff_text,
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "completed"
    assert data["service"] == "auth"
    assert "report" in data
    assert "change_correlation" in data
    assert data["change_correlation"] is not None
    assert data["change_correlation"]["top_correlated_change"]["file_path"] == "services/auth/tokens.py"
    job_id = data["job_id"]

    # Verify listed in investigations
    list_res = client.get("/investigations")
    assert list_res.status_code == 200
    items = list_res.json()
    assert any(item["job_id"] == job_id for item in items)

    # Verify single fetch
    get_res = client.get(f"/investigations/{job_id}")
    assert get_res.status_code == 200
    assert get_res.json()["job_id"] == job_id

    # Verify markdown export
    export_res = client.get(f"/investigations/{job_id}/export/markdown")
    assert export_res.status_code == 200
    assert "# DevShield AI Investigation Report" in export_res.text
    assert "Change Impact Correlation" in export_res.text

    # Verify JSON export
    export_json = client.get(f"/investigations/{job_id}/export/json")
    assert export_json.status_code == 200
    assert "change_correlation" in export_json.json()

    # Verify review transition
    review_res = client.post(
        f"/investigations/{job_id}/review",
        json={
            "to_status": "reviewed",
            "reviewer": "Alice SRE",
            "note": "Hypothesis validated against auth deployment timing.",
        },
    )
    assert review_res.status_code == 200
    assert review_res.json()["review_status"] == "reviewed"


def test_seed_samples_endpoint() -> None:
    res = client.post("/seed-samples")
    assert res.status_code == 200
    assert res.json()["status"] == "seeded"

