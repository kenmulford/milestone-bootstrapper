# Changelog

Notable changes to the **milestone-bootstrapper** plugin, newest first.

## v0.7.1 — retire the dead `feeder.json#reviewer` key

Patch release.

- `write-feeder-config.{sh,ps1}` no longer write `feeder.json#reviewer` — milestone-feeder retired this own-key upstream (self-check gate removed; the key is ignored gracefully if present), but this plugin never stopped emitting it (#149)
- `SPEC.md` §6.1, `BRIEF.md`, and the `plan`/`apply`/`update` skill docs no longer document `reviewer` as a live key; `SPEC.md` §6.1 also gained a missing `driver.json#projectDocs` row
- `update`'s union-write docs now call out the one consequence of the retirement: a `feeder.json` written before this fix that still carries `reviewer` loses it on the next `update` (safe — the key was already inert)
- New human-facing reference docs: `docs/driver-config-keys.md` and `docs/feeder-config-keys.md` list every key each config file can carry and which plugin owns it, linked from the README

### Consumer notes

- No action needed. A repo whose `feeder.json` already has `reviewer` set will have it silently dropped the next time `update` runs — this key did nothing after milestone-feeder retired it, so there's no behavior change to the feeder itself.

## v0.7.0 — detector-to-config consistency check

**Theme:** `detect-stack` maps each detected stack to a `domainSkills` value seeded into `.milestone-config/driver.json` at bootstrap, but nothing re-verified that config against the detector afterward — the same reactive-only drift hole v0.6.1 closed for `library-manifest.md`, applied to the one other deterministically-checkable field the detector emits. This release closes it, and extends the shipped `check` verb to cover it — no new verb.

### ✨ Detector-to-config consistency check

| Issue | PR | What |
|---|---|---|
| #139 Add check-driver-config.{sh,ps1} | #142 | New read-only component-script twin — the `domainSkills`-scoped sibling of `check-project-docs.{sh,ps1}`. Set-compares the union of detected app-stack `domainSkills` against `driver.json`'s recorded value, reporting any difference; `--check`/`-Check` exits nonzero for CI. Honors the tracked Ruby exemption (resolves #104) so it never false-positives on Rails/Ruby repos. |
| #140 Extend the check skill | #143 | `skills/check/SKILL.md` now invokes `check-driver-config.{sh,ps1}` alongside `check-project-docs.{sh,ps1}` and aggregates both scripts' independent advisory reports — each attributed distinctly, never merged or swallowed. A new precondition gate skips `check-driver-config` (with an advisory "not yet configured" line) when `.milestone-config/driver.json` doesn't exist yet, rather than surfacing its hard error. |

### Consumer notes (upgrading from v0.6.1)

- `/milestone-bootstrapper:check` now reports drift for TWO things: `.project/` doc freshness (v0.6.1) and `.milestone-config/driver.json`'s `domainSkills` field (this release). Both are advisory-only — neither is ever auto-rewritten.
- New component script `scripts/check-driver-config.{sh,ps1}` is also available directly for CI: pass `--check`/`-Check` to exit nonzero on drift.
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none

## v0.6.1 — .project freshness check

**Theme:** Nothing re-verified `.project/` against the code after creation — drift surfaced only reactively, at a broken build-time citation or a human-initiated re-plan. This release adds a standalone, read-only freshness check that re-derives what `.project/` should say from the repo's own detection signals and reports drift proactively, on demand or in CI.

### ✨ .project freshness check

| Issue | PR | What |
|---|---|---|
| #129 Add check-project-docs.{sh,ps1} | #134 | New read-only component-script twin that re-runs `detect-stack.{sh,ps1}` to re-derive the detected application stack(s) and diffs each against `.project/library-manifest.md#Runtime & frameworks`, reporting drift. `--check`/`-Check` makes drift a nonzero (exit 2) CI gate; without the flag drift is informational only (exit 0). Never writes any `.project/` file on any code path. |
| #130 Add a flagless `check` skill verb | #135 | New fourth verb alongside `plan`/`apply`/`update` — `skills/check/SKILL.md`, invoked as `/milestone-bootstrapper:check`. A thin, read-only orchestration layer that invokes `check-project-docs.{sh,ps1}` and surfaces any detected drift as an advisory review prompt; writes nothing and only reports. |

### Consumer notes (upgrading from v0.5.1)

- New optional verb: run `/milestone-bootstrapper:check` any time to review whether your `.project/` docs have drifted from what the repo's own detection now implies. Purely advisory — it never rewrites your docs.
- New component script `scripts/check-project-docs.{sh,ps1}` is available directly for CI: pass `--check`/`-Check` to exit nonzero on drift.
- **No schema changes** to `.milestone-config/driver.json`.
- **Version note:** the `0.6.0` bump (#128) was merged to `main` ahead of these features (no tag/release was cut for it). `0.6.1` is the actual feature release; `0.6.0` was never released as a distinct version.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none

## v0.5.1 — audit remediation: verify loops, resumability, size budgets

Patch release — the audit-remediation milestone (10 issues, all merged CI-green).

- SPEC.md documents `config-catalog.md` as the 7th project doc (#103); plan-file slug length pinned to one exact number, SPEC §2.2 (#105)
- Rails/Ruby stack detection in detect-stack + write-driver-config (#104)
- plan/apply/update SKILL.md worked examples split into `references/` (#106, #107, #108)
- Read-back verify + retry loop on apply's remote-writing deploy steps (#109); entry-level resumability in update's reconcile pass (#110)
- README/apply/update honesty + usability fixes (#111); CI size-budget gate for SKILL.md word ceilings (#112)

## v0.5.0 — provision `md-epic`, de-dup the label taxonomy

**Theme:** `milestone-driver` 1.15.0 reads a new label, `md-epic`, to treat an issue as a parent issue whose body lists several milestones in build order — but the driver only *reads* it; provisioning it is the bootstrapper's job. Before adding it, the label taxonomy is de-duped to a single canonical prose enumeration (`SPEC.md` §6.3) so future label changes touch one prose site instead of drifting across three.

### ✨ Features / enhancements

| Issue | PR | What |
|---|---|---|
| #95 Provision the `md-epic` parent-issue label | #96 | `provision-labels.sh` / `.ps1` now upsert an eleventh label, `md-epic` (color `006B75`, "Parent issue grouping several milestones into one ordered feature (driver builds them in order)"), as a new **suite slice** — owned by the bootstrapper as its creator, alongside the existing driver and feeder slices. `SPEC.md` §6.3 becomes the single canonical prose enumeration of all eleven labels; `BRIEF.md` Job 2 and `skills/plan/SKILL.md` §B now cite it instead of holding their own copy (the `plan`-generated plan file still enumerates every label by name — only the SKILL's duplicate list was removed). `skills/apply/SKILL.md` updated to the eleven-label count. |

### Consumer notes (upgrading from v0.4.0)

- **Existing bootstrapped repos: re-run `update` to provision `md-epic`.** A repo bootstrapped before this release has no `md-epic` label; `apply`/`update` create it idempotently (create-if-missing, upserts color/description on drift) alongside the other ten.
- **No new profile key.** `md-epic` is a fixed literal, not a `driver.json`/`feeder.json` key — no config migration needed.
- **Prose de-dup, no behavior change to the ten existing labels.** `SPEC.md` §6.3 is now the sole canonical label enumeration; `BRIEF.md` and `skills/plan/SKILL.md` point at it. The generated `plan` file's label preview is unchanged in completeness.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: #96 — autonomous re-wording of the `md-epic` description to fit GitHub's 100-char label-description limit.

## v0.4.0 — bootstrapper fidelity: config/secrets, deploy targets, versioning & stack detection

**Theme:** The scaffolded `.project/` docs and `.milestone-config/` profiles now capture more of a project as first-class, structured, citable facts — a config & secrets catalog, deployment targets, and versioning that actually reaches the feeder — while the config writers stop drifting from the driver/feeder schemas and front-end detection covers the mainstream JS frameworks.

### ✨ Features / enhancements

| Issue | PR | What |
|---|---|---|
| #76 Structured config & secrets catalog in `.project/` | #87 | New `project-docs/templates/config-catalog.md` — a `.env.example`-style **norms-only** doc (7 fixed `##` anchors: connection strings, auth/JWT, third-party API keys, notification targets, CORS origins, per-env app config, build outputs; recorded as key · source bucket · format · env · required?, **never values**) + a Tier 8 "Configuration & secrets" interview pass that cues the four common holes (local-dev DB engine, full JWT key set, complete CORS origins, sender/from address). In-repo only; consumers ground on it via existing generic `.project/#anchor` resolution. |
| #78 Deployment targets as a first-class fact | #84 | New fixed `## Deployment targets` anchor in the `environment.md` template + a Tier-4 interview question, so the deploy target (Cloudflare/AWS/Azure/Vercel/…) is a structured, citable fact instead of free-text hosting prose. Records, does not provision; `## Runtime & hosting` left intact. |
| #80 Driver-config writer emits `nonNegotiables` | #89 | The driver-config writer (both `.sh`/`.ps1` twins) now emits the optional `nonNegotiables` key (`string[]`), routed through the full lifecycle (`plan` → `apply` → `update` union), closing the real drift vs a `driver:setup`-provisioned profile. Keep-and-widen — delegating to the interactive setup skills is infeasible from non-interactive `apply`; `versioning` stays boolean, `implementerAgent` stays default-filled. |
| #81 Detect React / Vue / Svelte / Next front-end stacks | #86 | `detect-stack` (both twins) now discriminates Angular → Next → React → Vue → Svelte → generic (most-specific-first, one finding per `package.json`, Next before React) instead of collapsing every non-Angular JS stack to "Node (generic)". Strengthens the grounding digest the feeder architect relies on. |

### 🐛 Fixes

| Issue | PR | What |
|---|---|---|
| #77 Empty `{}` `feeder.json` defeated first-run setup | #83 | `write-feeder-config` (both twins) now short-circuits when the assembled object is empty — leaving `feeder.json` **absent** instead of writing `{}` — so an all-default freshly-bootstrapped repo correctly triggers `milestone-feeder:setup` (label alignment + key confirmation) on its first `plan`. Non-destructive (never writes AND never deletes); a run resolving any non-default key still writes a present file. This repo's own committed `{}` removed to dogfood the fix. Supersedes the v0.2.1 `#54` note. |
| #79 Versioning answer never reached the feeder | #88 | The Tier-6 versioning answer is now **dual-written**: the driver keeps `driver.json#versioning` (boolean, for its bump/extraction) AND the feeder writer emits `feeder.json#versioning` as `"semver"`/`"none"` (omitted when unanswered → feeder infers-or-asks). Routed through `plan`/`apply` with the `{driver boolean, feeder string}` mapping; the pre-existing `<semver \| false>` doc drift corrected (the driver key is boolean-only). |
| #75 Dead `allowCrossMarketplaceDependenciesOn` in `marketplace.json` | #82 | Removed the now-dead `allowCrossMarketplaceDependenciesOn` key — it permitted a cross-marketplace dependency the plugin no longer declares. JSON stays valid; `plugin.json` still declares no `dependencies`. Dead-config cleanup, no functional change. |

### Consumer notes (upgrading from v0.3.1)

- **`feeder.json` is no longer emitted empty.** An all-default freshly-bootstrapped repo now gets **no** `feeder.json`, so its first `milestone-feeder:plan` triggers `setup`. Already-bootstrapped repos carrying a stale `{}` are **not** auto-remediated — delete a stale `{}` manually if you want first-run setup to fire. (Supersedes the v0.2.1 `#54` note that `feeder.json` is emitted as `{}`.)
- **Versioning now reaches the feeder.** The bootstrapper dual-writes `feeder.json#versioning` (`"semver"`/`"none"`) alongside the driver's boolean, so "answer once → milestone-feeder names milestones as versions" holds.
- **New `.project/` outputs.** A bootstrap run now scaffolds `config-catalog.md` (config/secrets norms) and a `## Deployment targets` anchor in `environment.md`; downstream agents can cite `.project/config-catalog.md#<section>` and the deployment-targets anchor as grounding. Existing repos pick these up via the future `refresh`/`update` reconcile, not automatically.
- **Wider stack detection.** `detect-stack` now recognizes React/Vue/Svelte/Next (previously Angular/MAUI-only).
- **Additive schema/output changes only:** new `feeder.json#versioning` key, the driver writer now emits `nonNegotiables`, and two new `.project/` template artifacts. No existing key changed shape or default, and no plan-file contract broke.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: **#83** (removed this repo's committed `{}` `feeder.json` dogfood artifact), **#84** (`.project/` existing-repo reconciliation deferred to future `refresh`), **#86** (also edited the `plan` stack lookup table), **#87** (config-catalog `.project/` deferral), **#88** (dropped the non-producible `"versioning":"semver"` from this repo's `driver.json` + fixed `conventions.md` grounding), **#89** (in-scope widening of `update` to round-trip `nonNegotiables`). Review before the `develop → main` release.

## v0.3.1 — slash commands register in Claude Desktop

**Theme:** Drop the cross-marketplace `superpowers` dependency so the plugin's skills register as slash commands in Claude Desktop (the CLI already worked). `superpowers` is still required at runtime — it's now a documented prerequisite you install yourself rather than an auto-installed dependency.

### 🛠️ Maintenance

| Issue | PR | What |
|---|---|---|
| #72 Drop the cross-marketplace `superpowers` dependency | this PR | Removed the `dependencies` array from `.claude-plugin/plugin.json`. The cross-marketplace declaration (`superpowers@claude-plugins-official`) made Claude Desktop load the plugin but skip registering its skills as slash commands (upstream `anthropics/claude-code#9444`); the CLI was unaffected. `superpowers` is now a documented prerequisite in the README and `.project/library-manifest.md` instead of an auto-installed dependency. Mirrors the confirmed sibling fix `milestone-driver#246`. The `marketplace.json` `allowCrossMarketplaceDependenciesOn` cleanup is deliberately deferred to a suite-wide companion, gated on all four suite plugins dropping the dependency first. |

### Consumer notes (upgrading from v0.3.0)

- **Install `superpowers` yourself.** It's no longer auto-installed when you install milestone-bootstrapper — add the `claude-plugins-official` marketplace and install `superpowers` alongside the plugin. The README and library-manifest now describe it as a prerequisite.
- **Claude Desktop now registers the commands.** After upgrading and reloading, `/milestone-bootstrapper:*` registers and autocompletes in Claude Desktop. The Claude Code CLI was already registering them and is unchanged.
- **No script, skill, schema, or plan-file contract changed** — this release only removes a manifest field and updates forward-facing docs.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none.

## v0.3.0 — runnable CI for detected stacks

**Theme:** A freshly-bootstrapped repo's emitted `ci.yml` is now runnable — the bootstrapper detects the project's stack, persists it, and scaffolds the matching per-job runtime setup, so the first PR's CI goes green instead of failing on a missing toolchain.

### ✨ Runnable CI scaffolding

| Issue | PR | What |
|---|---|---|
| #63 Add `stack` / `stackVersionFile` to the `driver.json` writer + SPEC §6.1 | #67 | `write-driver-config` (both twins) gained `stack` (enum `node \| python \| dotnet \| maui \| rust \| plugin \| none`) and the optional `stackVersionFile` (the detected version-file path) — env fallbacks, enum validation (mirroring the `--versioning` reject shape), and omit-when-default discipline; documented in `SPEC.md §6.1`. Foundation only — no emitter behavior. |
| #64 Scaffold a per-stack runtime setup step in the emitted CI workflow | #68 | `emit-ci-workflow` (both twins) now consumes `stack`/`stackVersionFile` and prepends a runtime setup STEP inside the existing `unit-tests`/`preflight` jobs — node → `setup-node@v6` + `npm ci`/`npm install`, python → `setup-python@v6`, dotnet/maui → `setup-dotnet@v5`, rust/plugin/none → none. Setup is **fail-open** (a missing optional detail → sane default + `::warning::`, never a failed job), uses no new jobs (the required-status-check contexts stay byte-stable), and never auto-scaffolds Playwright/E2E. An absent `stack` key emits the prior two-job frame byte-for-byte. |
| #65 Populate `stack`/`stackVersionFile` from real detection, end-to-end | #69 | `detect-stack` (both twins) gained an additive 7th TSV column carrying the detected version-file PATH (node `.nvmrc`/`.node-version`, python `.python-version`, dotnet/maui `global.json`; empty otherwise — never a resolved version). `plan` maps the descriptive stack to the enum and records both keys in the §B Configs plan-file row; `apply`/`update` pass `--stack`/`--stack-version-file` through to the writer, mirroring the `domainSkills`/`versioning` pipeline. |

### 🛠️ Maintenance

| Issue | PR | What |
|---|---|---|
| #66 Resolve the driver-schema question for `stack`/`stackVersionFile` | this PR | Decided: **permanent exemption**, not cross-repo convergence. The milestone-driver plugin never reads these keys (only this bootstrapper's CI emitter does), and a schema documents what *its* plugin consumes — so `stack`/`stackVersionFile` are canonically defined in this repo's `SPEC.md §6.1` and deliberately kept out of the driver's `profile-schema.md`. The writer's exemption comment is relabeled permanent; a one-line pointer in `milestone-driver/docs/profile-schema.md` (companion change in that repo) keeps `driver.json` fully documented with no per-key lockstep. |

### Consumer notes (upgrading from v0.2.1)

- **New capability — runnable CI for detected stacks.** When the bootstrapper detects a Node / Python / .NET / MAUI / Rust stack, the emitted `ci.yml` now installs the matching runtime before your test/preflight gates run, so a freshly-bootstrapped repo's first PR gets green CI instead of red-CI'ing on a missing toolchain.
- **Fully backward-compatible.** A `driver.json` with no `stack` key — any pre-v0.3.0 bootstrap, or a stack the detector doesn't recognize — emits the prior two-job frame byte-for-byte. Existing repos pick up the richer workflow on their next `plan` → `apply`/`update`.
- **No Playwright / E2E in CI by default** — heavy, expensive browser jobs are never auto-scaffolded; E2E stays opt-in and consumer-owned.
- **New `driver.json` keys `stack` / `stackVersionFile` are additive and bootstrapper-owned** — the milestone-driver plugin neither reads nor validates them, so **no driver or feeder change is needed** to consume a v0.3.0 config. Their canonical definition is in this repo's `SPEC.md §6.1` (#66).

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none.

## v0.2.1 — dogfood the suite on its own repo

**Theme:** Practice what the suite preaches — give this repo its own populated `.project/` brain docs, and align its hand-authored config with what the scaffolder actually emits.

### 🛠️ Maintenance

| Issue | PR | What |
|---|---|---|
| #58 Bootstrap this repo's own `.project/` (dogfood) | #59 | Populated `.project/` (design-philosophy, library-manifest, environment, conventions; design-system/tokens recorded `none` for this no-UI repo) with this repo's real, cited understanding, captured via the bootstrapper's own `write-project-docs` against the templates. The feeder, driver, and coherence-reviewer now ground on house docs instead of thin inferred grounding. |
| #54 Drop the stray `versioning` key from this repo's own `.milestone-config/feeder.json` | this PR | `feeder.json` is now `{}` — the exact output `scripts/write-feeder-config.sh` emits for this repo (both `projectDocs` and `reviewer` at their bundled defaults). `versioning` is a driver-owned key (`scripts/write-feeder-config.sh` excludes it from the feeder slice and routes it to `driver.json`), where it stays correctly declared. Removes the misleading reference shape. |

### Consumer notes (upgrading from v0.2.0)

- **No behavior change for consumers.** Both changes are to this repo's own dogfood artifacts (`.project/`, `.milestone-config/feeder.json`) — no script, skill, schema, or plan-file contract changed.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none.

## v0.2.0 — nested-app scaffolding

**Theme:** Scaffold repos whose apps live nested under a subdirectory (e.g. `siteroot/web`, `siteroot/api`), not just at the repo root — while configs and `.project/` stay at the project root.

### ✨ Nested-app scaffolding

| Issue | PR | What |
|---|---|---|
| #49 Support a configurable app-root so scaffolded root-level configs can address nested apps | #51 | New plan-file-only `appRoots` field (array, default `["."]`). When set, `plan` discovers the app-roots from the repo layout, runs the stack detector **once per root and unions** the findings into one `.project/` + `nonNegotiables`, and **bakes each app-root as a root-absolute prefix** into the emitted `sourceGlobs`/`uiSurfaceGlobs` (e.g. `siteroot/web/**`). Configs + `.project/` stay at the project root. Default `["."]` is byte-identical to today. |
| #33 marketplace.json: add description/category/tags to plugin entry (match feeder/driver) | #50 | The `plugins[0]` entry now carries `description`, `category` (`"development"`), and `tags`, matching the milestone-feeder / milestone-driver marketplace shape for cross-suite discoverability. |

### Consumer notes (upgrading from v0.1.1)

- **Nested-app repos** can now be bootstrapped: set `appRoots` (e.g. `["siteroot/web", "siteroot/api"]`) in the plan and the bootstrapper scaffolds against those folders while keeping the shared config + house docs at the repo root. A repo whose app is at the top level needs no change — the default `["."]` produces byte-identical output to v0.1.1.
- **Bootstrapper-only — no consumer changes.** `appRoots` is a **plan-file-only** field: the baked globs are ordinary root-absolute strings the config writers persist verbatim, so `appRoots` is **never** written into `driver.json`/`feeder.json` and is **not** persisted under `.project/`. milestone-driver and milestone-feeder need no changes to consume a nested-app config.
- **No schema changes** to `.milestone-config/driver.json` — `appRoots` lives only in the plan-file contract; #33 touched only `.claude-plugin/marketplace.json` (plugin-entry metadata) and bumped `plugin.json` to `0.2.0`.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none.

## v0.1.1 — grounding seam

_Released 2026-06-22._

**Theme:** Provision one `projectDocs` pointer for both consumers in a single bootstrap pass, so the feeder and driver resolve the project's standing-docs directory from the same place and cannot drift.

This is the first versioned release of milestone-bootstrapper; versioned releases begin here at v0.1.1. The v0.1.0 entry below was authored before versioning, when the plugin shipped version-free.

### ✨ Grounding seam

| Issue | PR | What |
|---|---|---|
| #40 Emit projectDocs from both write-driver-config twins (.sh + .ps1), mirroring the feeder writer's omit-when-default discipline | #42 | `scripts/write-driver-config.{sh,ps1}` now emit an additive, optional `projectDocs` key into `driver.json` — default `.project/`, omit-when-default, first optional key — exactly as `write-feeder-config` emits it, with a new `--project-docs` / `-ProjectDocs` input and `DRIVER_PROJECT_DOCS` env fallback. Both twins stay byte-equivalent. |
| #41 Wire apply's Configs step to pass the resolved projectDocs to the driver writer too | #43 | `skills/apply/` now passes the once-resolved project-docs value to the driver-config writer in both CLI forms, mirroring the feeder invocation — so one bootstrap pass writes the same `projectDocs` into both `feeder.json` and `driver.json`. |

### Consumer notes

- Additive, optional `projectDocs` key — a bootstrapped repo with the docs dir left at the default `.project/` is byte-for-byte unchanged (omit-when-default preserves current behavior). A customized docs dir now lands the identical value in both `feeder.json` and `driver.json`.
- Emits ahead of the sibling `milestone-driver` schema/consumer by the deliberate "safe to ship independently and first" decision; the driver consumer treats absent `projectDocs` as `.project/`, so there is no behavior regression while the sibling driver-side reader is pending.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: #42 (accepted cross-twin asymmetry on the explicit-empty `-ProjectDocs ''` input — faithfully reproduces the existing feeder-twin behavior and is unreachable via `apply`'s always-resolved value path).

## milestone-bootstrapper v1 — project brain + suite-ready bootstrap

**Theme:** Capture a project's durable understanding into a populated `.project/` doc set and make the repo suite-ready, so `milestone-feeder` and `milestone-driver` plan and build against grounded house docs and conventions.

### ✨ Features / enhancements

| Issue | PR | What |
|---|---|---|
| #1 Scaffold the plugin (manifest pair, superpowers dependency, repo hygiene) | #16 | `.claude-plugin/` manifest pair + the vendored `.project/` doc templates (6 templates + `SPEC.md`) the population engine fills. |
| #2 Define the provisioning-plan-file format | #17 | `SPEC.md` — the reviewable contract `plan` writes and `apply`/`update` read: deterministic slug, fields-a-consumer-parses, reconcile classes, three-state recording. |
| #3 Stack detection + best-practice/domainSkills inference | #18 | `scripts/detect-stack.{sh,ps1}` — detect the stack and map each choice to its conventions note, version pin, and `domainSkills` candidate (driver table verbatim). |
| #4 Understanding-interview engine | #21 | `docs/understanding-interview.md` — tier-by-tier capture of goal/architecture/stack/environment/versioning, recorded under stable `.project/` anchors. |
| #5 feeder.json config-slice writer | #19 | `scripts/write-feeder-config.{sh,ps1}` — direct-write the feeder-owned keys against the canonical schema (Option A; delegation stays interactive-only). |
| #6 Label taxonomy provisioner | #20 | `scripts/provision-labels.{sh,ps1}` — idempotent `gh label create --force` of the 10 driver+feeder labels, legacy reconcile first. |
| #7 project-docs writer | #22 | `scripts/write-project-docs.{sh,ps1}` — place composed interview + detection content under each template's stable anchor; three-state discipline. |
| #8 driver.json config-slice writer | #23 | `scripts/write-driver-config.{sh,ps1}` — direct-write the driver slice from the plan (domainSkills, versioning, Core keys); omit defaults. |
| #9 `plan` skill | #24 | `skills/plan/` — interview + inspect + detect → a reviewable provisioning plan file; writes nothing remote. |
| #10 Branch-model provisioner | #25 | `scripts/provision-branches.{sh,ps1}` — create-if-missing the integration + protected branches, set the default-branch policy; adopt-or-init, non-destructive. |
| #11 CI-workflow emitter | #26 | `scripts/emit-ci-workflow.{sh,ps1}` — emit a PR-gating CI workflow with stable status-check context names; absent commands flagged, never guessed. |
| #12 Branch-protection provisioner | #27 | `scripts/provision-protection.{sh,ps1}` — assert the lockdown floor via the GitHub API; GET-merge so it never weakens stronger protection. |
| #13 `apply` skill | #28 | `skills/apply/` — ordered, idempotent execution of the approved plan (docs → configs → labels → branch model → CI → protection). |
| #14 `update` skill | #29 | `skills/update/` — diff-first reconcile of a refreshed plan: PATCH tool-owned configs (union write — never drops a live key), PROPOSE human-owned docs, flag live-only targets, true no-op when synced. |

### Consumer notes

- New plugin, version `0.1.0` (version-free mode — no per-PR version bump).
- Surface: three flagless verbs — `/milestone-bootstrapper:plan` (preview), `:apply` (first deploy), `:update` (reconcile, diff-first, non-destructive).
- Cross-platform: every script ships a bash (`.sh`, requires `jq`) and a PowerShell 7+ (`.ps1`) twin with byte-identical behavior. Skill invocations use `--flag` on bash and PascalCase `-Flag` on PowerShell.
- Depends on the `superpowers` plugin (cross-marketplace).
- The `.project/` doc templates are vendored from the canonical `project-docs` suite source.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none.
