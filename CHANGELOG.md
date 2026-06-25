# Changelog

Notable changes to the **milestone-bootstrapper** plugin, newest first.

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
