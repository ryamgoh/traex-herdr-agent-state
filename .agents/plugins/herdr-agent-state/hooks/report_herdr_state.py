#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import time
from typing import Optional, Tuple

SOURCE_BASE = os.environ.get("HERDR_TRAEX_SOURCE", "custom:traex")
AGENT = "traex"
STATE_BY_EVENT = {
    "UserPromptSubmit": ("working", None),
    "PreToolUse": ("working", None),
    "PermissionRequest": ("blocked", "awaiting approval"),
    "PostToolUse": ("working", None),
    "PostToolUseFailure": ("working", None),
    "SubagentStart": ("working", "subagent"),
    "SubagentStop": ("working", None),
    "PreCompact": ("working", "compacting"),
    "PostCompact": ("working", None),
    "Stop": ("idle", "done"),
    "Interrupt": ("idle", "interrupted"),
}


def run_herdr(*args: str) -> None:
    subprocess.run(
        ["herdr", *args],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=2,
        check=False,
    )


def source_for(payload: dict) -> str:
    session_id = payload.get("session_id")
    if isinstance(session_id, str) and session_id:
        return f"{SOURCE_BASE}:{session_id}"
    return SOURCE_BASE


def report_state(source: str, state: str, message: Optional[str]) -> None:
    args = [
        "pane", "report-agent", os.environ["HERDR_PANE_ID"],
        "--source", source, "--agent", AGENT, "--state", state,
    ]
    if message:
        args.extend(["--message", message])
    run_herdr(*args, "--seq", str(time.time_ns()))


def report_session(payload: dict, source: str) -> None:
    session_id = payload.get("session_id")
    if not isinstance(session_id, str) or not session_id:
        return
    args = [
        "pane", "report-agent-session", os.environ["HERDR_PANE_ID"],
        "--source", source, "--agent", AGENT,
        "--seq", str(time.time_ns()), "--agent-session-id", session_id,
    ]
    transcript_path = payload.get("transcript_path")
    if isinstance(transcript_path, str) and transcript_path:
        args.extend(["--agent-session-path", transcript_path])
    run_herdr(*args)


def forward_notification(payload: dict, notification_type: str) -> None:
    title = payload.get("title")
    message = payload.get("message")
    args = ["notification", "show", title if isinstance(title, str) and title else "TraeX"]
    if isinstance(message, str) and message:
        args.extend(["--body", message])
    sound = {"idle_prompt": "done", "permission_prompt": "request"}.get(
        notification_type, "none",
    )
    run_herdr(*args, "--sound", sound)


def notification_state(notification_type: str) -> Optional[Tuple[str, Optional[str]]]:
    if notification_type == "permission_prompt":
        return "blocked", "awaiting approval"
    if notification_type == "idle_prompt":
        return "idle", "done"
    return None


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return

    event = str(payload.get("hook_event_name") or "")
    source = source_for(payload)
    if event == "SessionStart":
        report_session(payload, source)
        report_state(source, "idle", None)
        return
    if event == "SessionEnd":
        run_herdr(
            "pane", "release-agent", os.environ["HERDR_PANE_ID"],
            "--source", source, "--agent", AGENT, "--seq", str(time.time_ns()),
        )
        return
    if event == "Notification":
        notification_type = str(payload.get("notification_type") or "")
        forward_notification(payload, notification_type)
        state = notification_state(notification_type)
        if state:
            report_state(source, *state)
        return

    state = STATE_BY_EVENT.get(event)
    if state:
        report_state(source, *state)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
