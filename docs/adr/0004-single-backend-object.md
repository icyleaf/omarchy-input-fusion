# One Backend object owns the backend processes, not each call site

`omarchy-bitwarden` keeps 21 near-identical `Process` blocks inline in its
single entry file, one per backend call, each repeating the same
`StdioCollector` + `JSON.parse` + stderr-funnel logic. Its data format is sound
but the mechanism is copy-pasted, and the front end leaks process objects into
every call site.

Input Fusion talks to two engines (fcitx5 over D-Bus, and the `bloom` binary),
so that duplication would multiply. We put every backend process behind one
`Backend.qml`: a `call(verb, args)` entry point, reused `Process` objects, a
per-call sequence guard, and typed parsed state exposed as properties.
`FcitxController.js` keeps only the pure argv-building and parsing functions.

## Consequences

- Call sites depend on a small verb vocabulary and typed properties, not on
  `Process` or raw JSON.
- A stale response from a superseded call is dropped by the sequence guard
  rather than overwriting newer state.
