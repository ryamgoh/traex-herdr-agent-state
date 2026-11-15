# Contributing

Thanks for your interest in improving this plugin.

## Development setup

Requirements:

- Python 3.9+
- A POSIX shell (Linux or macOS)
- Optional: a real TraeX and Herdr install for manual end-to-end checks

Clone and validate the plugin manifest:

```bash
git clone https://github.com/ryamgoh/traex-herdr-agent-state.git
cd traex-herdr-agent-state
traecli plugin validate --path .agents/plugins/herdr-agent-state
```

## Running the tests

The test suite does not need Herdr installed. It places a fake `herdr` binary
on `PATH`, replays every hook event across two sessions, and asserts the exact
CLI calls:

```bash
sh test/report_herdr_state_test.sh
```

Also compile-check the Python bridge:

```bash
python3 -m py_compile .agents/plugins/herdr-agent-state/hooks/report_herdr_state.py
```

## Making a change

1. Fork the repository and create a topic branch.
2. Make your change and add or update a case in
   `test/report_herdr_state_test.sh`.
3. Run the test suite and the manifest validation above.
4. Update the lifecycle mapping table in `README.md` if hook behavior changes,
   and bump the plugin version in
   `.agents/plugins/herdr-agent-state/.codex-plugin/plugin.json`.
5. Open a pull request describing the TraeX build you tested against.

## Design principles to preserve

- **Never block the agent.** Hook failures must be swallowed and timeouts
  must stay short; Herdr being unavailable cannot interrupt a TraeX task.
- **Order matters.** Every report uses a nanosecond sequence number, and
  session-scoped source authorities must stay isolated.
- **No payload persistence.** The bridge reads only the fields it needs; do
  not write transcript content to disk.
- **Verify empirically.** TraeX hook behavior is build-dependent. Document
  which build a mapping was verified against instead of assuming the docs are
  complete.

## Reporting issues

Please include your TraeX version, Herdr version, operating system, and the
output of `/hooks` inside TraeX. For state-ordering bugs, the Herdr pane logs
are more useful than screenshots alone.
