# Conventions

<!--
Project doc (.project/). Cite as `.project/conventions.md#<section>`. This is the file the
implementer and coherence-reviewer lean on hardest — "reuse conventions" and
"does this fit the app?" both resolve here. Prefer pointing at a canonical
exemplar in the codebase (path:line) over prose. Keep ## headings stable — they
are citation anchors.
-->

## Naming
Files, types, functions, tests, branches.
> [TBD] — e.g. "PascalCase types; `*ViewModel` suffix; tests mirror the unit name + `Tests`; branches `issue/<n>-<slug>`."

## File & folder layout
Where things go, and the shape of a feature.
> [TBD] — e.g. "One feature = a folder under `Features/` with View, ViewModel, and Tests colocated."

## Test patterns
Where tests live, how they're named, fixtures/factories, and what a good test looks like.
> [TBD]

## Canonical exemplars (mirror these)
The reference implementations to copy when building something similar. Point at real code.

| For… | Mirror | Notes |
|---|---|---|
| [TBD] (e.g. a new list page) | [TBD path:line] | [TBD] |
| [TBD] (e.g. a service call) | [TBD path:line] | [TBD] |

## Commits & PRs
Message format and PR expectations.
> [TBD]

## Versioning
Does the project follow semantic versioning? If so, **where the version lives** (e.g. `pyproject.toml`, `package.json`, `*.csproj`, a `VERSION` file) and the **bump cadence** (per feature / milestone). When semver is on, `milestone-driver` applies the bump per PR and `milestone-feeder` names milestones as versions so the driver can derive the target.
> [TBD] — e.g. "SemVer; version in `pyproject.toml`; minor bump per feature milestone."
