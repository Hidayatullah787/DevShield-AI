"""Safe parser for Git diffs and code patch snippets."""

from __future__ import annotations

import re
from typing import Literal

from incident_agent.change_correlation.models import ChangedFile, ChangedHunk

# Security: limit diff input size to 512 KB to prevent memory exhaustion
MAX_DIFF_CHARACTERS = 512 * 1024
MAX_FILES_TO_PARSE = 100

SECRET_PATTERNS = [
    re.compile(r"(?i)(api[_-]?key|password|secret|bearer|auth[_-]?token)\s*[:=]\s*['\"][^'\"]+['\"]"),
    re.compile(r"(?i)bearer\s+[a-zA-Z0-9_\-\.]{15,}"),
    re.compile(r"ghp_[a-zA-Z0-9]{36}"),
]

IDENTIFIER_PATTERN = re.compile(r"\b[a-zA-Z_][a-zA-Z0-9_]{2,60}\b")
CONFIG_KEY_PATTERNS = [
    re.compile(r"(?i)\b([a-z0-9_]*(?:timeout|retries|retry|pool|port|host|url|buffer|limit|latency|interval|rate|concurrency|ttl|ssl|database)[a-z0-9_]*)\b"),
    re.compile(r"\b([A-Z0-9_]*(?:TIMEOUT|RETRIES|RETRY|POOL|PORT|HOST|URL|BUFFER|LIMIT|LATENCY|INTERVAL|RATE|CONCURRENCY|TTL|SSL|DATABASE)[A-Z0-9_]*)\b"),
]

STOP_IDENTIFIERS = {
    "true", "false", "none", "null", "self", "this", "import", "from", "return", "class",
    "def", "function", "const", "var", "let", "final", "string", "int", "bool", "float",
    "void", "async", "await", "if", "else", "for", "while", "try", "catch", "except", "throw"
}


def redact_secrets(line: str) -> str:
    """Scrub potential credentials or secrets from line content."""
    scrubbed = line
    for pattern in SECRET_PATTERNS:
        scrubbed = pattern.sub("[REDACTED_SECRET]", scrubbed)
    return scrubbed


def parse_git_diff(raw_diff: str) -> list[ChangedFile]:
    """Parse a unified git diff or patch string into structured ChangedFile models."""
    if not raw_diff or not raw_diff.strip():
        return []

    # Bounded input check
    content = raw_diff[:MAX_DIFF_CHARACTERS]
    lines = content.splitlines()

    files: list[ChangedFile] = []
    current_file: ChangedFile | None = None
    current_hunk: ChangedHunk | None = None

    def finalize_hunk() -> None:
        nonlocal current_hunk, current_file
        if current_file is not None and current_hunk is not None:
            current_file.hunks.append(current_hunk)
            current_hunk = None

    def finalize_file() -> None:
        nonlocal current_file
        finalize_hunk()
        if current_file is not None:
            # Extract identifiers and config keys across added and removed lines
            added_text = " ".join(" ".join(h.added_lines) for h in current_file.hunks)
            removed_text = " ".join(" ".join(h.removed_lines) for h in current_file.hunks)
            full_text = f"{current_file.file_path} {added_text} {removed_text}"

            tokens = set(IDENTIFIER_PATTERN.findall(full_text))
            cleaned_tokens = [t for t in tokens if t.lower() not in STOP_IDENTIFIERS and len(t) > 2]
            current_file.extracted_identifiers = sorted(cleaned_tokens)[:80]

            configs: set[str] = set()
            for pat in CONFIG_KEY_PATTERNS:
                configs.update(pat.findall(full_text))
            current_file.config_keys = sorted(configs)[:30]

            files.append(current_file)
            current_file = None

    file_diff_pattern = re.compile(r"^diff --git a/(.*?) b/(.*?)$")
    hunk_header_pattern = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)$")

    for line in lines:
        if len(files) >= MAX_FILES_TO_PARSE:
            break

        # Check for diff header
        match_diff = file_diff_pattern.match(line)
        if match_diff:
            finalize_file()
            file_path = match_diff.group(2)
            current_file = ChangedFile(file_path=file_path, change_type="modified")
            continue

        # Check for traditional --- and +++ lines if diff header is absent
        if line.startswith("--- ") and not current_file:
            continue
        if line.startswith("+++ "):
            path_part = line[4:].strip()
            if path_part.startswith("b/"):
                path_part = path_part[2:]
            if path_part != "/dev/null":
                if current_file is None:
                    current_file = ChangedFile(file_path=path_part, change_type="modified")
                else:
                    current_file.file_path = path_part
            continue

        # Check for hunk header
        hunk_match = hunk_header_pattern.match(line)
        if hunk_match:
            finalize_hunk()
            if current_file is None:
                current_file = ChangedFile(file_path="unknown_changed_file", change_type="modified")
            old_start = int(hunk_match.group(1))
            old_count = int(hunk_match.group(2) or 1)
            new_start = int(hunk_match.group(3))
            new_count = int(hunk_match.group(4) or 1)
            header_desc = hunk_match.group(5).strip()
            current_hunk = ChangedHunk(
                old_start=old_start,
                old_lines=old_count,
                new_start=new_start,
                new_lines=new_count,
                header=header_desc,
            )
            continue

        # Hunk content lines
        if current_hunk is not None:
            if line.startswith("+") and not line.startswith("+++"):
                current_hunk.added_lines.append(redact_secrets(line[1:]))
            elif line.startswith("-") and not line.startswith("---"):
                current_hunk.removed_lines.append(redact_secrets(line[1:]))

    finalize_file()

    # If format was a raw code snippet with +/- and no headers, handle gracefully
    if not files:
        added: list[str] = []
        removed: list[str] = []
        for line in lines:
            if line.startswith("+") and not line.startswith("+++"):
                added.append(redact_secrets(line[1:]))
            elif line.startswith("-") and not line.startswith("---"):
                removed.append(redact_secrets(line[1:]))
        if added or removed:
            single_hunk = ChangedHunk(added_lines=added, removed_lines=removed)
            snippet_file = ChangedFile(
                file_path="pasted_patch_snippet",
                hunks=[single_hunk],
            )
            full_text = " ".join(added + removed)
            tokens = set(IDENTIFIER_PATTERN.findall(full_text))
            snippet_file.extracted_identifiers = sorted(
                [t for t in tokens if t.lower() not in STOP_IDENTIFIERS and len(t) > 2]
            )[:80]
            configs: set[str] = set()
            for pat in CONFIG_KEY_PATTERNS:
                configs.update(pat.findall(full_text))
            snippet_file.config_keys = sorted(configs)[:30]
            files.append(snippet_file)

    return files
