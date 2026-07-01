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
> Component scripts live under `scripts/` as `<verb>-<noun>.{sh,ps1}` twins (e.g. `write-project-docs`, `provision-labels`). Skills live under `skills/<verb>/SKILL.md`. Bash invocations use `--flag` long options; the PowerShell twins use PascalCase `-Flag` params. (Grounded in README.md:5, the `scripts/` layout, CHANGELOG.md:77.)

## File & folder layout
Where things go, and the shape of a feature.
> `skills/` (plan | apply | update), `scripts/` (the cross-platform component twins), `project-docs/templates/` (the vendored `.project/` doc templates), `docs/` (the interview + writer engine docs), `.claude-plugin/` (plugin.json + marketplace.json), `.milestone-config/` (driver.json + feeder.json). (Grounded in the repo tree, README.md:5.)

## Test patterns
Where tests live, how they're named, fixtures/factories, and what a good test looks like.
> Verify the cross-platform twins stay behaviorally byte-equivalent and that every component is idempotent and non-destructive (a re-run of an already-applied step is a true no-op). (Grounded in CHANGELOG.md:77, BRIEF.md:65.)

## Canonical exemplars (mirror these)
The reference implementations to copy when building something similar. Point at real code.

| For… | Mirror | Notes |
|---|---|---|
| a new component script | `scripts/write-project-docs.sh` + `scripts/write-project-docs.ps1` | the bash/pwsh twin pattern, header contract, idempotent placement |
| a new skill | `skills/plan/SKILL.md` | announce-first, numbered procedure, output style, non-negotiables block |

## Commits & PRs
Message format and PR expectations.
> Feature branch → PR into the integration branch `develop`; merge on green CI; the protected branch `main` is release-only (Ken's, by hand). Conventional-style commit subjects (`feat:`, `chore:`, `docs:`). (Grounded in .milestone-config/driver.json `integrationBranch`/`protectedBranch`, the CHANGELOG.md PR-per-issue tables.)

## Versioning
Does the project follow semantic versioning? If so, **where the version lives** (e.g. `pyproject.toml`, `package.json`, `*.csproj`, a `VERSION` file) and the **bump cadence** (per feature / milestone). When semver is on, `milestone-driver` applies the bump per PR and `milestone-feeder` names milestones as versions so the driver can derive the target.
> SemVer. The version lives in `.claude-plugin/plugin.json` (currently `0.2.0`). milestone-driver applies the per-PR bump and milestone-feeder names milestones as versions so the driver can derive the target. (Grounded in the absence of `versioning` in .milestone-config/driver.json — the driver key is boolean-only: `false` = version-free, omitted = versioned — the feeder-side string-enum policy .milestone-config/feeder.json `versioning: "semver"`, .claude-plugin/plugin.json `version`, BRIEF.md:38, the CHANGELOG.md release headers.)
