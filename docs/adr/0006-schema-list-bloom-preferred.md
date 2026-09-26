# The panel's Schema list is Bloom-preferred with a Rime fallback

The control panel showed two overlapping Schema lists: Rime's Enabled set (from
`ListAllSchemas`) and Bloom's `Schemas`. They answer the same question — _what
can I type with_ — so we merge them into one **Schema List**. fcitx5 exposes
only the Enabled set over D-Bus, and Bloom knows only the packages it tracked,
so neither alone can enumerate what is installed. The widest list needs the
filesystem: `bloom --json list` also scans the Rime user directory and reports
`present_schemas` (every `*.schema.yaml`). The Schema List is therefore Enabled
∪ Present ∪ Bloom-owned, plus the Active Schema if it is none of those.
Without `bloom` it degrades to Rime's Enabled set.

Including the Present set is what keeps a disabled Schema from vanishing. With
only Enabled ∪ owned, unchecking a schema that no package tracks would drop it
from the list with no way to re-enable it from the panel.

The two axes stay separate. **Enable/Disable** is a Bloom write to
`default.custom.yaml`; **Set Active** is fcitx5's `SetSchema`. Active is always
read from fcitx5 (and only while Rime is the current Input Method), because
Bloom has no Active concept. A Schema can be Active without being Enabled
(verified: `SetSchema` accepts a Schema that is not in `schema_list`), but that
lapses on the next redeploy, so the two markers render independently.

## Consequences

- `bloom --json list` carries `present_schemas`; the plugin reads it and treats
  a present Schema as Installed, ownerless unless a package owns it.
- The Enabled toggle only exists while Bloom is available; the fallback list
  offers Set Active alone.
- `bloom install` does not auto-enable, so an installed Schema can sit
  disabled until the user enables it.
