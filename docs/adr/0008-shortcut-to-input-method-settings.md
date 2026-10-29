# Contextual shortcut to Input Method settings in the control panel

The control panel previously provided an entry to the `hypr-input-switcher` rules
editor, but offered no direct shortcut to configure the active Input Method or
the underlying fcitx5 framework. Users had to launch `fcitx5-configtool` manually
or open separate settings tools from the application launcher.

Different Input Methods in Linux have distinct configuration tools:
- `msime` (水杉输入法) provides its own dedicated settings application (`msime-linux-settings`).
- `rime` uses nested Schemas and packages whose management is built into Input
  Fusion's fullscreen Overlay (the Bloom tab).
- General input methods (`keyboard-us`, `mozc`) and framework settings use
  `fcitx5-configtool`.

We add a dynamic shortcut entry to the control panel footer that contextually
resolves to the appropriate settings tool for the active Input Method.

## Decision

- When `snapshot.isRime` is true:
  - Display label: *Rime 方案管理* (*Rime Schemas*).
  - Clicking closes the panel and opens the Input Fusion Overlay on its Bloom tab.
- When `snapshot.imName === "msime"`:
  - Display label: *水杉输入法设置* (*MSIME Settings*).
  - Clicking closes the panel and launches `msime-linux-settings` via `uwsm app`.
- Default (Direct Mode or other generic input methods):
  - Display label: *Fcitx5 配置* (*Fcitx5 Settings*).
  - Clicking closes the panel and launches `fcitx5-configtool` via `uwsm app`.

## Consequences

- The control panel footer gains a persistent management entry styled consistently
  with the Rules entry (⚙ icon, dynamic label, chevron).
- Pure resolution logic is encapsulated and tested in `FcitxController.settingsTarget`.
- Clicking closes the panel first to cleanly release Wayland keyboard grab and
  context before opening the external configuration tool or Overlay.
