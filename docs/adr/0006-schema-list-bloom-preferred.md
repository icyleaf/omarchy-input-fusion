# The panel's Schema list is Bloom-preferred with a Rime fallback

The control panel showed two overlapping Schema lists: Rime's Enabled set (from
`ListAllSchemas`) and Bloom's `Schemas`. They answer the same question — _what
can I type with_ — so we merge them into one **Schema List**: the Enabled
Schemas, plus, when `bloom --json list` succeeds, the Schemas owned by Installed
Packages (a superset). Without Bloom the list degrades to Rime's Enabled set,
which is all fcitx5 exposes.

The two axes stay separate. **Enable/Disable** is a Bloom write to
`default.custom.yaml`; **Set Active** is fcitx5's `SetSchema`. Active is always
read from fcitx5 on the fast poll, because Bloom has no Active concept. A Schema
can be Active without being Enabled (verified: `SetSchema` accepts a Schema that
is not in `schema_list`), but that lapses on the next redeploy, so the two
markers render independently.

## Consequences

- fcitx5's `ListAllSchemas` returns the Enabled set only; a Schema whose files
  are on disk but neither Enabled nor Bloom-tracked cannot appear at all. The
  Schema List is the widest set any surface can show.
- The Enabled toggle only exists while Bloom is available; the fallback list
  offers Set Active alone.
- `bloom install` does not auto-enable, so an installed Schema can sit
  disabled until the user enables it.
