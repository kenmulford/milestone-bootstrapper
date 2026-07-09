# feeder.json — the keys this plugin writes

> This page restates `SPEC.md` §6.1 in plain language for quick lookup.
> `SPEC.md` §6.1 is the technical source of truth for what `apply`/`update`
> write — if a key here is added, renamed, or removed, update both.

`milestone-feeder` reads its settings from `.milestone-config/feeder.json`.
`milestone-bootstrapper` writes **some** of those settings for you when you run
`apply` (and re-syncs them on `update`) — the ones it can detect or capture
during its interview. This page lists exactly those keys, in plain language,
so you don't have to go digging through `SPEC.md` to remember one.

**Not every `feeder.json` key is here.** Some keys are `milestone-feeder`'s own
— things like whether it hands a finished milestone straight to
`milestone-driver` — and it writes those into `feeder.json` itself, outside
this plugin entirely. See
["Keys this plugin doesn't write"](#keys-this-plugin-doesnt-write) below for
where to look for those.

## Keys this plugin writes

| Key | Required? | What it controls |
|---|---|---|
| `projectDocs` | When your `.project/` docs live somewhere non-default | Where your project's standing docs live, so `milestone-feeder` can ground issue-writing in them. Same value also written to `driver.json#projectDocs` — see [driver-config-keys.md](driver-config-keys.md). |
| `versioning` | When your project's versioning policy was captured | Whether `milestone-feeder` versions milestones: `"semver"` or `"none"`. Left out entirely means "not captured" — `milestone-feeder` infers it or asks. |

**If `feeder.json` would otherwise carry only default values, this plugin
doesn't create the file at all.** `milestone-feeder` treats an absent file as
"first run here" and offers its own setup — writing a `{}` file would
suppress that. So don't worry if you don't see a `feeder.json` yet; it means
everything's still at its default.

## Keys this plugin doesn't write

`feeder.json` can carry other keys that `milestone-feeder` writes into it
directly — through its own `setup` interview or while it runs — not through
this plugin's `apply`/`update`. If you're looking for one of these, the full
definition lives in `milestone-feeder`'s own
[`docs/profile-schema.md`](https://github.com/kenmulford/milestone-feeder/blob/main/docs/profile-schema.md):

- `autoHandoff` — whether a finished milestone gets handed straight to `milestone-driver` to start building.
- `architectAgent`, `issueAuthorAgent` — which agent handles each planning step (rarely overridden; sensible defaults ship out of the box).
- `issueSize` — an optional sizing rule for how big an issue should be.
- `sourceGlobs` (self-protection) — this is `milestone-feeder`'s own repo's source paths, not your project's. Only relevant if you're working on `milestone-feeder` itself.

See also [driver-config-keys.md](driver-config-keys.md) for `.milestone-config/driver.json`.
