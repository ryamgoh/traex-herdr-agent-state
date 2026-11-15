# TraeX → Herdr Agent State

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: Linux | macOS](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-blue)](#requirements)
[![Python: 3.9+](https://img.shields.io/badge/python-3.9%2B-blue)](#requirements)

A [TraeX](https://trae.ai) plugin marketplace containing one plugin,
`herdr-agent-state`, which makes TraeX appear as a **live custom agent** in the
[Herdr](https://herdr.dev) sidebar. It registers at startup, flips between
`working`, `blocked` and `idle` as TraeX runs, and disappears when TraeX exits.

Herdr does not ship a built-in TraeX integration. This plugin makes TraeX a
self-reporting agent through Herdr's supported socket API
(`herdr pane report-agent`), with no polling and no changes to Herdr itself.

## What is supported

| Area | Support |
| --- | --- |
| Platforms | Linux, macOS |
| Runtime | TraeX with command hooks enabled; Python 3.9+; the `herdr` CLI on `PATH` |
| Herdr states | `idle`, `working`, `blocked` (plus Herdr-derived `done`) |
| TraeX lifecycle events | 13 events, see the [lifecycle mapping](#lifecycle-mapping) |
| Notifications | Completion and permission-request notifications forwarded to Herdr with sounds |
| Multi-instance | Per-session source authority so parallel TraeX sessions never overwrite each other |
| Ordering | Nanosecond sequence numbers keep lifecycle updates ordered |
| Failure mode | Hook errors are swallowed; a Herdr outage can never block a TraeX task |

See [ROADMAP.md](ROADMAP.md) for planned work.

## How it works

```text
TraeX lifecycle hook (stdin JSON payload)
        │
        ▼
report_herdr_state.sh        # environment guards, fail-fast
        │
        ▼
report_herdr_state.py        # event to Herdr state mapping, ordered CLI calls
        │
        ▼
herdr pane report-agent …    # Herdr socket API, --seq ordered
```

- The shell wrapper verifies the Herdr environment (`HERDR_ENV`, `HERDR_PANE_ID`,
  `HERDR_SOCKET_PATH`) and required binaries before doing anything.
- The Python bridge maps each TraeX hook event to a Herdr state and reports it
  with a nanosecond `--seq`, preserving order even when hooks fire in quick
  succession.
- Each TraeX session reports under its own source authority
  (`custom:traex:<session_id>`), so an old session's sequence watermark cannot
  suppress a newer session in the same pane.
- Exit calls `herdr pane release-agent` so the agent does not linger as a stale
  sidebar entry.

## Install

This repo is a TraeX plugin marketplace. Registering the marketplace is the
recommended path because it enables `plugin upgrade` and `--auto-update`:

```bash
traecli plugin marketplace add \
  https://github.com/ryamgoh/traex-herdr-agent-state.git --auto-update
traecli plugin install herdr-agent-state
```

Some builds use the `traex` binary name instead of `traecli`; the commands are
identical.

Direct git install (no marketplace, so no automatic upgrades):

```bash
traecli plugin install \
  "https://github.com/ryamgoh/traex-herdr-agent-state.git:.agents/plugins/herdr-agent-state" \
  --type git
```

Then restart TraeX (hooks load at session start) and verify:

- In TraeX: `/hooks` lists the events, trusted and sourced from this plugin.
- In Herdr: `herdr agent list` shows `traex` after the first turn, changing
  state as you work and disappearing when TraeX exits.

### User-level hooks fallback

Instead of installing the plugin, point entries in
`$TRAECLI_HOME/hooks.json` (for example `~/.trae/cli/hooks.json`) at absolute
paths of `report_herdr_state.sh` from a local clone. Do not run both the
installed plugin and user-level hooks at once, or every event reports twice.

## Lifecycle mapping

Verified against a real TraeX build by instrumenting every hook and observing
which actually fire.

| TraeX hook | Herdr result | Notes |
| --- | --- | --- |
| `SessionStart` | register as `idle` | Fires with the first turn on current builds |
| `UserPromptSubmit` | `working` | A turn begins |
| `PreToolUse`, `PostToolUse`, `PostToolUseFailure` | `working` | Tool activity |
| `SubagentStart` | `working` + `subagent` label | |
| `SubagentStop` | `working` | |
| `PreCompact` | `working` + `compacting` label | |
| `PostCompact` | `working` | |
| `Stop` | `idle` + `done` label | Turn ending |
| `Notification` (`idle_prompt`) | `idle` + `done` label | The real "turn finished, waiting for you" signal |
| `PermissionRequest` | `blocked` (`awaiting approval`) | Clears on the next tool lifecycle event |
| `Notification` (`permission_prompt`) | `blocked` (`awaiting approval`) | Also forwards a Herdr request notification |
| `Interrupt` | `idle` + `interrupted` label | Herdr renders an unseen interrupted pane as done |
| `SessionEnd` | released | Agent removed from the sidebar |

Herdr's reportable states are only `idle`, `working`, `blocked`, `unknown`.
`done` is not reportable; Herdr derives it for a pane that went
`working` to `idle` without being viewed, so end-of-turn reports `idle` plus a
visible `done` message.

Two TraeX hook events are intentionally not wired: `PreModelRequest` and
`PostModelRequest` only observe model sampling. Their output is diagnostic and
cannot drive a `working`/`blocked`/`idle` state, so handling them would add hook
overhead without changing anything in the sidebar.

## Configuration

The bridge activates only when Herdr injects all of the following into the hook
environment:

- `HERDR_ENV=1`
- `HERDR_PANE_ID`
- `HERDR_SOCKET_PATH`

Outside a Herdr-managed pane the wrapper exits silently, which is why the
plugin is safe to keep installed globally.

## Known limitations

- **Deferred startup registration.** On current TraeX builds, `SessionStart`
  first fires together with the first turn rather than at idle launch, so a
  freshly opened, un-prompted session does not appear in the sidebar until you
  send the first message.
- Hook behavior is build-dependent; if a future TraeX build changes its hook
  contract, re-run the test suite and update the mapping table.
- Verified against Herdr 0.7.4: `herdr integration` lists no TraeX integration,
  and every command this plugin calls (`pane report-agent`,
  `pane report-agent-session`, `pane release-agent`, `notification show`) exists.
  Re-check `herdr integration status` after upgrading Herdr, since a native
  TraeX integration could ship in a later release and make this plugin
  unnecessary.

## Development

```bash
# No Herdr install required: the test fakes the herdr CLI.
sh test/report_herdr_state_test.sh
```

The harness drops a fake `herdr` binary on `PATH`, replays every hook event
across two sessions, and asserts the exact socket API calls, including
session-scoped source authorities and release on exit.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues and pull requests are welcome.

## License

MIT — see [LICENSE](LICENSE).
