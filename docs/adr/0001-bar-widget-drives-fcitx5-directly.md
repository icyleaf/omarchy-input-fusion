# Bar widget drives fcitx5 directly, bypassing the rule engine

The Bar Widget reads and switches the current Input Method and Schema by
talking to fcitx5 over D-Bus (`busctl --json=short`), rather than asking the
`hypr-input-switcher` daemon to apply a change. The daemon's job is automatic
switching: it re-evaluates Client and Layer Rules whenever the active window
changes and may overwrite a manual choice soon after. Routing manual clicks
through the daemon would therefore either be meaningless (rules still win) or
require a new manual-override concept the daemon does not have. We chose direct
control and document the trade-off in the panel instead.

## Consequences

- A manual switch can be silently undone by the next rule evaluation when the
  daemon is running. The panel shows a hint in that case rather than hiding it.
- The widget depends only on fcitx5's D-Bus surface, so it works with the daemon
  stopped, and stays useful as a plain input-method indicator.
