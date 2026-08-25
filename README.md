# Hypr Input Switcher - Omarchy 4.0 Overlay Plugin

A visual rule management overlay plugin designed for **Omarchy 4.0+ (Quickshell)**, allowing users to inspect, configure, and persist automatic input method switching rules for `hypr-input-switcher` in real time with **100% Pure Quickshell & JavaScript (Zero Python Dependency)**.

---

## ✨ Features

- 🪟 **Visual Rule Management**: Easily view, add, edit, reorder, and remove window rules (Class, Regex support, Window Title, and Target Input Method).
- 🎯 **Pure Native Window Picker**: Click-to-pick any target window on screen (chaining `slurp` + `hyprctl`) directly in Quickshell to auto-fill window `class` and `title`.
- ⌨️ **Input Method Management**: Dedicated tab to manage input methods, display names, engine backends, and inline Rime schemas (e.g. `rime_frost`, `jaroomaji`).
- 🔍 **System Diagnostics Banner**: Live status indicator displaying binary installation, version, daemon process state (with a one-click `▶ Start Service` button), and configuration file health.
- ↕️ **Rule Priority Reordering**: Move rules up and down to match first-fit execution precedence in `hypr-input-switcher`.
- ⚙️ **Default Input Method Switching**: Switch global fallback input method behavior (`english`, `chinese`, `keep`, etc.) on the fly.
- 💾 **Native Atomic YAML Sync**: Powered by a bundled pure JavaScript YAML engine and `Quickshell.Io.FileView` for instant atomic saves and hot reload with zero external runtime dependencies.
- 🎨 **Native Omarchy 4.0 Styling**: Full integration with Omarchy `qs.Commons` and `qs.Ui` theme tokens, rounded cards, keyboard focus handling, and backdrop dismissal.

---

## 📂 Repository Structure

```text
.
├── manifest.json            # Omarchy 4.0 plugin manifest (id: icyleaf.hypr-input-switcher)
├── Overlay.qml              # Pure Quickshell Overlay QML UI
├── i18n.js                  # Internationalization translation module (EN / ZH)
├── yaml.js                  # Pure JavaScript YAML parser and serializer
├── install.sh               # Quick install, validation, and activation script
├── LICENSE                  # MIT License
├── README.md                # Plugin documentation
└── assets/
    └── logo.svg             # Official Hypr Input Switcher SVG logo
```

---

## 🛠️ Requirements

- **Omarchy 4.0+** (`omarchy-shell` / Quickshell)
- **[hypr-input-switcher](https://github.com/icyleaf/hypr-input-switcher)** (`/usr/bin/hypr-input-switcher` or in `$PATH`)
- **[slurp](https://github.com/emersion/slurp)** _(optional)_: Enables interactive screen window picking

---

## 🚀 Installation

### Option 1: Using the Install Script (Local Development)

Run the installation script directly from the repository root:

```bash
./install.sh
```

### Option 2: Via Omarchy Plugin Manager (Git Remote)

Once published to a Git repository:

```bash
omarchy plugin add https://github.com/<your-username>/omarchy-hypr-input-switcher
omarchy plugin enable icyleaf.hypr-input-switcher
```

### Option 3: Manual Installation

```bash
mkdir -p ~/.config/omarchy/plugins/icyleaf.hypr-input-switcher
cp -r ./* ~/.config/omarchy/plugins/icyleaf.hypr-input-switcher/

# Rescan and enable the plugin in Omarchy Shell
omarchy-shell shell rescanPlugins
omarchy plugin enable icyleaf.hypr-input-switcher
```

---

## ⌨️ Usage & Keybinding

Omarchy Shell utilizes IPC commands to toggle overlays:

### Test in Terminal

```bash
omarchy-shell shell toggle icyleaf.hypr-input-switcher
# or
omarchy shell shell toggle icyleaf.hypr-input-switcher
```

### Hyprland Keybinding

Add a keybinding to your Hyprland configuration (e.g. `~/.config/hypr/hyprland.conf` or `~/.config/hypr/bindings.conf`):

```ini
# Toggle Hypr Input Switcher Overlay with Super + Shift + I
bind = $mainMod SHIFT, I, exec, omarchy-shell shell toggle icyleaf.hypr-input-switcher
```

---

## 📄 License

MIT
