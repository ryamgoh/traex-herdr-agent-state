#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BRIDGE="$ROOT_DIR/.agents/plugins/herdr-agent-state/hooks/report_herdr_state.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/traex-herdr-test.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

mkdir -p "$TMP_DIR/bin"
cat >"$TMP_DIR/bin/herdr" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$*" >>"$HERDR_TEST_LOG"
EOF
chmod +x "$TMP_DIR/bin/herdr"

export PATH="$TMP_DIR/bin:$PATH"
export TMPDIR="$TMP_DIR"
export HERDR_ENV=1
export HERDR_PANE_ID=test:p1
export HERDR_SOCKET_PATH="$TMP_DIR/herdr.sock"
export HERDR_TEST_LOG="$TMP_DIR/herdr.log"

run_event() {
  event_name="$1"
  extra="${2:-}"
  session_id="${3:-session-1}"
  printf '{"hook_event_name":"%s","turn_id":"019fff61-112b-7e71-a107-176c4b3ea32b","session_id":"%s","transcript_path":"/tmp/transcript.jsonl"%s}\n' "$event_name" "$session_id" "$extra" | sh "$BRIDGE"
}

run_event SessionStart ',"source":"startup"'
run_event UserPromptSubmit
run_event PreToolUse ',"tool_name":"Bash"'
run_event PermissionRequest ',"tool_name":"Bash"'
run_event PostToolUse ',"tool_name":"Bash"'
run_event PermissionRequest ',"tool_name":"apply_patch"'
run_event PostToolUseFailure ',"tool_name":"apply_patch","error":"denied"'
run_event SubagentStart ',"agent_type":"review"'
run_event SubagentStop ',"agent_type":"review"'
run_event PreCompact ',"trigger":"auto"'
run_event PostCompact ',"trigger":"auto"'
run_event Notification ',"notification_type":"permission_prompt","title":"Permission required","message":"Approve Bash"'
run_event Notification ',"notification_type":"background_task_complete","title":"Task finished","message":"Build completed"'
run_event Stop
run_event Notification ',"notification_type":"idle_prompt","title":"Agent idle","message":"Waiting for input"'
run_event Interrupt ',"reason":"user_interrupt"'
run_event SessionEnd ',"reason":"prompt_input_exit"'
run_event SessionStart ',"source":"startup"' session-2
run_event UserPromptSubmit '' session-2
run_event Stop '' session-2
run_event SessionEnd ',"reason":"prompt_input_exit"' session-2

assert_line() {
  expected="$1"
  if ! grep -F -- "$expected" "$HERDR_TEST_LOG" >/dev/null; then
    printf 'missing call: %s\n' "$expected" >&2
    printf '%s\n' 'actual calls:' >&2
    cat "$HERDR_TEST_LOG" >&2
    exit 1
  fi
}

assert_line 'pane report-agent-session test:p1 --source custom:traex:session-1 --agent traex'
assert_line '--agent-session-id session-1 --agent-session-path /tmp/transcript.jsonl'
assert_line 'pane report-agent test:p1 --source custom:traex:session-1 --agent traex --state idle'
assert_line '--state working'
assert_line '--state blocked --message awaiting approval'
assert_line '--state working --message subagent'
assert_line '--state working --message compacting'
assert_line '--state idle --message done'
assert_line '--state idle --message interrupted'
assert_line 'notification show Agent idle --body Waiting for input --sound done'
assert_line 'notification show Permission required --body Approve Bash --sound request'
assert_line 'notification show Task finished --body Build completed --sound none'
assert_line 'pane release-agent test:p1 --source custom:traex:session-1 --agent traex'
assert_line 'pane report-agent-session test:p1 --source custom:traex:session-2 --agent traex'
assert_line '--agent-session-id session-2 --agent-session-path /tmp/transcript.jsonl'
assert_line 'pane report-agent test:p1 --source custom:traex:session-2 --agent traex --state working'
assert_line 'pane release-agent test:p1 --source custom:traex:session-2 --agent traex'

blocked_count="$(grep -c -- '--state blocked --message awaiting approval' "$HERDR_TEST_LOG")"
[ "$blocked_count" -eq 3 ] || {
  printf 'expected three blocked reports, got %s\n' "$blocked_count" >&2
  exit 1
}

before="$(wc -l <"$HERDR_TEST_LOG")"
env -u HERDR_PANE_ID sh "$BRIDGE" <<'EOF'
{"hook_event_name":"UserPromptSubmit"}
EOF
after="$(wc -l <"$HERDR_TEST_LOG")"
[ "$before" -eq "$after" ] || {
  printf 'bridge reported outside a Herdr pane\n' >&2
  exit 1
}

python3 - "$ROOT_DIR/.agents/plugins/herdr-agent-state/hooks/hooks.json" <<'PY'
import json
import sys

expected = {
    "PreToolUse", "PermissionRequest", "PostToolUse",
    "PostToolUseFailure", "Notification", "SubagentStart",
    "SubagentStop", "PreCompact", "PostCompact", "SessionStart",
    "SessionEnd", "UserPromptSubmit", "Stop", "Interrupt",
}
hooks = json.load(open(sys.argv[1], encoding="utf-8"))["hooks"]
if set(hooks) != expected:
    raise SystemExit(f"hook coverage mismatch: {sorted(set(hooks) ^ expected)}")
PY

printf 'all Herdr lifecycle bridge tests passed\n'
