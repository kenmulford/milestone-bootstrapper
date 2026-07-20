# driver.json — the keys this plugin writes

> This page restates `SPEC.md` §6.1 in plain language for quick lookup.
> `SPEC.md` §6.1 is the technical source of truth for what `apply`/`update`
> write — if a key here is added, renamed, or removed, update both.

`milestone-driver` reads its settings from `.milestone-config/driver.json`.
`milestone-bootstrapper` writes **some** of those settings for you when you run
`apply` (and re-syncs them on `update`) — the ones it can detect or capture
during its interview. This page lists exactly those keys, in plain language,
so you don't have to go digging through `SPEC.md` to remember one.

**Not every `driver.json` key is here.** Some keys are `milestone-driver`'s own
— things like how many issues it builds at once — and it writes those into
`driver.json` itself, outside this plugin entirely. See
["Keys this plugin doesn't write"](#keys-this-plugin-doesnt-write) below for
where to look for those.

## Keys this plugin writes

| Key | Required? | What it controls |
|---|---|---|
| `integrationBranch` | Always | Which branch `milestone-driver` opens pull requests into (e.g. `develop`). |
| `protectedBranch` | Always | Which branch is off-limits to direct pushes and PRs (e.g. `main`). |
| `sourceGlobs` | Always | Which file paths count as "your code" — only the implementer subagent may touch them. |
| `projectDocs` | When your `.project/` docs live somewhere non-default | Where your project's standing docs (conventions, architecture) live, so `milestone-driver` can ground its work in them. Same value also written to `feeder.json#projectDocs` — see [feeder-config-keys.md](feeder-config-keys.md). |
| `uiSurfaceGlobs` | UI projects only | Which paths are UI surfaces — drives the extra design review and visual sign-off step on UI issues. |
| `unitTestCmd` | When a test command was detected | The command that runs your unit tests. |
| `preflightCmd` | When a lint/format/static-analysis command was detected | A fast local command run before a pull request opens, so a red result surfaces early. |
| `e2eEnv` | When an end-to-end test environment was detected | Device/endpoint info for the end-to-end test runner. |
| `domainSkills` | When your stack has known best-practice skills | Framework-specific skills `milestone-driver`'s implementer should consult while writing code. |
| `nonNegotiables` | When you have hard constraints | Rules the implementer must always honor (framework versions, platform targets). |
| `versioning` | Only when your project is explicitly non-versioned | `false` means don't bump a version per PR. Left out entirely means versioned — this key is only ever written as `false`, never `true`. |
| `stack` | When a runtime stack was detected | Which runtime family (Node, Python, .NET, etc.) the CI workflow is scaffolded for. |
| `stackVersionFile` | When a version-file was found | The path to your stack's version-pin file (e.g. `.nvmrc`, `.python-version`). |
| `integrationProtection` | Only when you opted the integration branch into a protection floor | `"floor"` gates your integration branch with a pull request and required CI checks, while still letting admins override — so a transient CI break can't wedge the branch `milestone-driver` merges into. Left out entirely (the default, `"none"`) means the integration branch stays unprotected and the driver's pull requests merge ungated. |

Every optional key above is left out of the file entirely when it's at its
default — an absent key always means "use the default," never "value not yet
decided."

## Keys this plugin doesn't write

`driver.json` can carry other keys that `milestone-driver` writes into it
directly — through its own `setup` interview or while it runs — not through
this plugin's `apply`/`update`. If you're looking for one of these, the full
definition lives in `milestone-driver`'s own
[`docs/profile-schema.md`](https://github.com/kenmulford/milestone-driver/blob/main/docs/profile-schema.md):

- `parallel`, `maxParallelWorkers` — how many issues `milestone-driver` builds at once.
- `integrationGranularity` — whether each issue gets its own pull request, or a whole batch shares one.
- `ciWorkflow` — which CI workflow file to check when `preflightCmd` is `"github-ci"`.
- `e2eTestCmd`, `visualCapture` — the end-to-end test command and screenshot-capture setup.
- `integrations.trello` — optional Trello board sync.
- `implementerAgent`, `triageAgent`, `designReviewAgent`, `coherenceReviewAgent` — which agent handles each step (rarely overridden; sensible defaults ship out of the box).

See also [feeder-config-keys.md](feeder-config-keys.md) for `.milestone-config/feeder.json`.
