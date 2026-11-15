# Roadmap

This is a personal-maintained project. Items are ideas and may change based on
what Herdr and TraeX expose upstream.

## Supported today

- Full TraeX lifecycle coverage: session, prompt, tool, subagent, compaction,
  notification, permission, interrupt and session-end hooks (13 events).
- Ordered state reporting with nanosecond sequence numbers.
- Per-session source authorities, so parallel sessions in one pane never
  overwrite each other.
- Herdr notification forwarding with distinct `done` and `request` sounds.
- Explicit agent release on session end (no stale sidebar entries).
- Dependency-free shell test harness with a fake `herdr` CLI, covering two
  sessions and every event.
- Marketplace install, direct git install, and user-level hooks fallback.

## Under consideration

- **CI:** GitHub Actions running the shell test suite and Python syntax checks
  on every pull request.
- **Usage metrics sidecar:** record transcript/session identifiers per Herdr
  pane so a companion metrics plugin can attribute usage to the correct
  session when several panes share a working directory.
- **Model metadata:** surface the model name from the TraeX hook payload in the
  Herdr sidebar when the field is present.
- **Configurable labels:** allow the `working`, `blocked` and `idle` display
  labels to be customized via plugin configuration instead of constants.
- **Windows support:** the bridge is POSIX shell today; a native Windows path
  would need a PowerShell or pure-Python entry point.
- **Upstream Herdr integration:** contribute the lifecycle mapping upstream so
  TraeX is detected natively and this plugin becomes unnecessary.

## Not planned

- Polling Herdr or TraeX processes. The design is purely event-driven through
  lifecycle hooks.
- Caching or rewriting hook payloads. The bridge only reads the fields it
  needs and never persists conversation content.
