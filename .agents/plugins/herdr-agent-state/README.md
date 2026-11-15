# herdr-agent-state

Reports TraeX agent lifecycle state to [Herdr](https://herdr.dev) so TraeX shows
up as a **live custom agent** in the herdr sidebar — registering at startup,
flipping between working / blocked / done as it runs, and being removed when
TraeX exits — instead of an undetected terminal process.

## Why this exists

Herdr does not currently include TraeX in its built-in agent or integration
lists. The supported path for an agent that reports its own lifecycle is the
socket API: `herdr pane report-agent`.

This plugin wires TraeX's lifecycle hooks to that command so state updates itself
as TraeX runs, with no manual commands.

## Lifecycle mapping

Verified against a real TraeX build by instrumenting every hook.

| TraeX hook | herdr result |
| --- | --- |
| `SessionStart` | register as `idle` |
| `UserPromptSubmit` | `working` |
| `PreToolUse`, `PostToolUse`, `PostToolUseFailure` | `working` |
| `SubagentStart` / `SubagentStop` | `working` (+ `subagent` label on start) |
| `PreCompact` / `PostCompact` | `working` (+ `compacting` label on pre) |
| `Stop` | `idle` + `done` label |
| `Notification` (`idle_prompt`) | `idle` + `done` label (real end-of-turn "waiting for you" signal) |
| `PermissionRequest` / `Notification` (`permission_prompt`) | `blocked` + request notification |
| `Interrupt` | `idle` + `interrupted` label |
| `SessionEnd` | released (removed from the sidebar) |

herdr's reportable states are only `idle`, `working`, `blocked`, `unknown`.
`done` is derived by herdr for a `working` → `idle` pane that has not been
viewed, so end-of-turn reports `idle` plus a visible `done` message.

Current TraeX builds expose reliable `PermissionRequest` and `Interrupt` hooks,
so approval waits and cancelled turns are represented directly. All notification
payloads are forwarded through Herdr's notification API with done/request sounds.
`PreModelRequest` and `PostModelRequest` are deliberately not wired: they only
observe model sampling and cannot set a working/blocked/idle state, so they add
overhead without changing the sidebar.
Startup registration is still deferred:
hooks (including `SessionStart`) first fire with the first turn, so a freshly
launched, un-prompted session does not appear until the first message.

## How it works

- `hooks/report_herdr_state.sh` calls `herdr pane report-agent` with a
  session-scoped `--source custom:traex:<session_id> --agent traex`, and
  `herdr pane release-agent` on exit.
- It no-ops unless `HERDR_PANE_ID` is set (i.e. only inside a herdr pane) and
  always exits 0, so it can never block or slow a TraeX turn.
- Hooks run synchronously and every report/release uses a nanosecond `--seq`,
  preserving lifecycle order without leaving stale async state behind.
- The Herdr source is scoped to the TraeX session as
  `custom:traex:<session_id>`. Herdr retains sequence watermarks per source and
  pane, so reusing one global source could make every later session invisible.
- `SessionEnd` uses `release-agent`, not a state report: a custom agent
  authority is pinned to the pane and would otherwise linger as a stale entry
  after TraeX quits. Releasing it mirrors how a detected agent disappears when
  its process exits.
- `PermissionRequest` and `Notification(permission_prompt)` both map to
  `blocked`; the next tool lifecycle event restores `working`.
- `__PLUGIN_DIR__` in `hooks/hooks.json` resolves to this `hooks/` directory, so
  the plugin is fully relocatable — no absolute paths.

## Requirements

- [herdr](https://herdr.dev) installed, with the `herdr` CLI on `PATH`.
- TraeX running inside a herdr pane (so `HERDR_PANE_ID` is present).
