# The bar widget owns all fcitx5 state; the control panel only renders a snapshot

While a layer-shell surface holds Wayland keyboard focus, fcitx5 treats it as a
separate input context: `CurrentInputMethod` reports that surface's transient
context instead of the focused application's, and `SetCurrentIM` returns
success but is deferred until focus returns to a text-input app. (Verified with
a bare `PanelWindow` carrying no fcitx code; `SetSchema`, `Activate`, and
`Deactivate` are not deferred, only the Input Method switch.) The Control Panel
is exactly such a focused surface, so it cannot read or switch input methods
while it is open.

We therefore split responsibilities: `Widget.qml` (which never takes focus) owns
every read and write and hands the panel an immutable snapshot at open time; the
panel lists that snapshot, and on selection closes first — releasing focus — then
asks the widget to apply the choice. This is why the panel has no fcitx
processes and why selecting a row closes the panel.

Reads are also suppressed while a switch plan runs. A poll issued just before a
plan can complete during it, and its result would overwrite the value the plan's
verify step is about to read, making a successful switch look like a failure.

## Consequences

- The panel's state cannot update while it is open, so a switch is never
  observable in the panel itself; the bar label reflects it after close.
- A plain keyboard layout is reported as `State` "inactive", the same as Direct
  Mode, so it is folded into the Direct row rather than listed as a second,
  identical target.
- `SetCurrentIM` can still be a silent no-op when no text-input window has
  focus (fcitx5 defers it); switching is reliable once any app is focused.
