# Input Fusion is a UI shell; bloom and hypr-input-switcher stay the engines

The plugin needs to show and change two very different things: which Schema Rime
is typing with (a runtime fcitx5 property) and which Schemas and packages are
installed and enabled (Bloom's domain). Reimplementing Bloom's recipe engine,
YAML AST patching, and dependency tracing in QML/JavaScript would duplicate a
mature Go implementation and its package state. So the plugin is a front end:
it reads Bloom's own files for display, and runs the `bloom` binary for
mutations. Automatic switching stays in the `hypr-input-switcher` daemon, which
owns the Hyprland event stream — a process the shell's lifetime cannot hold.

Bloom exposes no machine-readable output today, so we add a `--json` flag to
Bloom itself rather than parse its lipgloss-formatted text. This makes the
plugin's contract data instead of prose, and makes Bloom scriptable in general.

## Consequences

- The plugin must detect the `bloom` binary and degrade to a two-section panel
  without it; Bloom is not bundled (it is a separate, larger binary).
- Heavy or untrusted writes (`install`, `upgrade`, `remove` clone remote git and
  run recipes) run in a floating terminal, not inside the shell process. Fast,
  safe writes (`enable`, `disable`, `deploy`) run in-process.
- The daemon's rule engine keeps its own `~/.config/hypr-input-switcher/`
  configuration; the plugin is a second editor of it, not a replacement.
