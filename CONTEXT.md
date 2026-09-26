# Input Fusion

An Omarchy plugin that fuses input-method control with the tools around it: a
bar widget for the live fcitx5 Input Method and Rime Schema, an Overlay for
rules and packages, and optional bridges to two engines — `bloom` for Rime
schemas and `hypr-input-switcher` for automatic switching. This glossary fixes
the vocabulary shared by the plugin and those engines.

## Language

**Input Method**:
An fcitx5-level input source selectable on its own, such as `keyboard-us` or
`rime`. Exactly one is current at a time.
_Avoid_: engine, IME, layout

**Schema**:
A Rime-internal profile nested inside the `rime` Input Method, such as
`sno_ch_jp` or `jaroomaji`. A Schema only exists while the current Input Method
is Rime.
_Avoid_: input method, sub-method, mode

**Active Schema**:
The Schema Rime is currently typing with. Changed at runtime over fcitx5 D-Bus.
_Avoid_: current schema, selected schema, enabled schema

**Set Active**:
To make a Schema the Active Schema. The only way to change what Rime types
with. A Schema can be Active without being Enabled, but that lapses on the next
redeploy.
_Avoid_: activate, enable, switch to

**Enabled Schema**:
A Schema listed in Rime's `default.custom.yaml` `schema_list`, making it
selectable at all. Managed by Bloom; independent of which Schema is Active.
_Avoid_: available schema, installed schema, active schema

**Enable** (and **Disable**):
To add a Schema to, or remove it from, the Enabled list so it survives a
redeploy. Managed by Bloom. Never used to mean Set Active.
_Avoid_: activate, deactivate, install

**Installed Package**:
A Rime package Bloom has installed and tracks in `state.json`, along with the
files and Schemas it owns.
_Avoid_: schema, recipe

**Installed Schema**:
A Schema whose files are present in the Rime user directory, whether or not it
is Enabled. Present because an Installed Package owns it, or because it was
placed outside Bloom.
_Avoid_: present schema, available schema

**Owner Package**:
The Installed Package whose `schemas` include a given Schema. Shown on a
Schema List row to explain where the Schema came from.
_Avoid_: source, provider

**Ownerless Schema**:
A Schema in the Schema List that no Installed Package owns — enabled by hand,
or left behind by Bloom drift. It can be Enabled and Disabled, but not
uninstalled.
_Avoid_: orphan, dangling schema, untracked

**Schema List**:
The set of Schemas a surface offers: the Enabled Schemas, plus — when Bloom is
available — the Schemas owned by Installed Packages. This is the most any
surface can show, since fcitx5 exposes only the Enabled set.
_Avoid_: all schemas, available schemas

**Input Method Group**:
An fcitx5 collection of Input Methods that can be switched among directly. Only
members of the current group are selectable.
_Avoid_: profile, set

**Direct Mode**:
The state where fcitx5 is deactivated and typing falls through to the bare
keyboard layout. This is how the `english` label is realized.
_Avoid_: off, English mode, inactive

**Keep**:
The `default_input_method` value that leaves the current Input Method untouched
instead of forcing one. Requires daemon version 0.4.0 or newer.
_Avoid_: none, passthrough, unchanged

**Default Input Method**:
The Input Method applied when no rule matches.
_Avoid_: fallback, global method

**Client Rule**:
A switch on the active window's class (and optionally title). Evaluated top to
bottom; the first match wins.
_Avoid_: window rule, app rule

**Layer Rule**:
A switch on a layer-shell surface's namespace, since overlays (menus, Omarchy
plugins) never appear as windows and cannot be matched by a Client Rule. An open
Layer Rule outranks the active window.
_Avoid_: overlay rule, namespace rule

**Bloom Bridge**:
The optional part of the plugin that surfaces Bloom's Enabled Schemas,
Installed Packages, and updates. Reads state through `bloom --json`. Fast
writes (enable, disable, deploy) run in-process; heavy writes (install,
upgrade, remove) run Bloom in a terminal rather than inside the shell process.
_Avoid_: bloom plugin, schema manager

**Rule Bridge**:
The optional part of the plugin that surfaces the `hypr-input-switcher` daemon's
configuration and status. The daemon itself keeps doing the automatic
switching; the plugin only edits its config and shows its state.
_Avoid_: auto switcher, daemon UI

**Overlay**:
The fullscreen plugin surface used to edit rules, Input Methods, and Bloom
packages.
_Avoid_: panel, dialog, settings window

**Bar Widget**:
The compact plugin surface that shows live status and opens a control panel.
It is a distinct plugin kind from the Overlay.
_Avoid_: indicator, tray item, module
