# Hide Schema List and Bloom sections when Rime is not the active Input Method

The control panel previously showed the Rime Schema List and the Bloom section
regardless of which Input Method was active. When typing with Direct Mode or a
non-Rime Input Method (such as `msime` or `mozc`), a hint was displayed
(`rime_inactive_hint`) suggesting that selecting a Schema would switch to Rime
first.

In practice, when users configure other Input Methods such as `msime`, Schemas
have no effect on the active typing engine. Displaying the Schema List and Bloom
packages adds visual noise and confusion, as switching schemas produces no
observable change to the active Input Method. Furthermore, as established in the
domain model (see `CONTEXT.md`), _"A Schema only exists while the current Input
Method is Rime"_.

We therefore hide both the **Schema List** and the **Bloom** sections in the
control panel whenever `snapshot.isRime` is false.

## Consequences

- When Rime is not the active Input Method (e.g. `msime`, `keyboard-us`, Direct Mode):
  - The Schemas section (header, hint text, and schema rows) is completely hidden.
  - The Bloom section (installed packages, updates, refresh) is completely hidden.
  - The control panel height shrinks naturally via `fittedContentHeight` to fit
    only the Input Method rows.
  - Keyboard navigation (`allRows()`, `cursor`, `moveCursor`) and `Tab` section
    jumping strictly confine the cursor to `inputRows`, preventing invisible rows
    from being highlighted or activated.
- When Rime is active (`snapshot.isRime === true`):
  - The panel restores the full view: Input Methods, Schema List, and Bloom.
- Bloom management for Rime packages remains available at any time via the
  fullscreen Overlay.
