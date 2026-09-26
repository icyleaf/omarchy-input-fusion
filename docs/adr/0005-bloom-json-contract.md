# Bloom is read through a `--json` contract, not its files or its text

The plugin needs Bloom's Enabled Schemas, Installed Packages, and update state.
Bloom stores those across three places — `default.custom.yaml` in the Rime
directory, `state.json` and `registry.yaml` under `~/.config/bloom` — each with
its own schema and migration history. Reading them directly would duplicate
Bloom's parsing, and scraping Bloom's lipgloss-formatted output would make the
contract prose.

So we add a persistent `--json` flag to the Bloom CLI: each command writes
exactly one JSON object to stdout, with a shared `ok` boolean and, on failure,
an `error` string (still exiting non-zero). The plugin shells out to
`bloom --json list` and `bloom --json update` and parses only that object.

## Status

The read commands — `list`, `list --registry`, `update`, `doctor`, `version` —
emit JSON. The mutating commands do too, but the plugin does not call them yet;
writes land in a later phase and run in a terminal, not inside the shell
process.

## Consequences

- `bloom list` is local and cheap; remote checks are confined to `bloom update`
  (and `list --check-updates`), so the plugin can poll the former on a short
  cadence and the latter on a five-minute cache.
- The `--json` flag is a general Bloom feature, not a plugin-private protocol,
  so scripts and other front ends can use it.
- `bloom` is not bundled. A missing binary hides the Bloom section and leaves a
  two-section panel; a bloom build without `--json` surfaces a parse error in
  the section rather than a crash.
