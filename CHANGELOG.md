# Changelog

Notable changes to the **milestone-bootstrapper** plugin, newest first.

## milestone-bootstrapper v0.1.1 — grounding seam

**Theme:** Provision one `projectDocs` pointer for both consumers in a single bootstrap pass, so the feeder and driver resolve the project's standing-docs directory from the same place and cannot drift.

### ✨ Grounding seam

| Issue | PR | What |
|---|---|---|
| #40 Emit projectDocs from both write-driver-config twins (.sh + .ps1), mirroring the feeder writer's omit-when-default discipline | #42 | `scripts/write-driver-config.{sh,ps1}` now emit an additive, optional `projectDocs` key into `driver.json` — default `.project/`, omit-when-default, first optional key — exactly as `write-feeder-config` emits it, with a new `--project-docs` / `-ProjectDocs` input and `DRIVER_PROJECT_DOCS` env fallback. Both twins stay byte-equivalent. |
| #41 Wire apply's Configs step to pass the resolved projectDocs to the driver writer too | #43 | `skills/apply/` now passes the once-resolved project-docs value to the driver-config writer in both CLI forms, mirroring the feeder invocation — so one bootstrap pass writes the same `projectDocs` into both `feeder.json` and `driver.json`. |

### Consumer notes

- Additive, optional `projectDocs` key — a bootstrapped repo with the docs dir left at the default `.project/` is byte-for-byte unchanged (omit-when-default preserves current behavior). A customized docs dir now lands the identical value in both `feeder.json` and `driver.json`.
- Emits ahead of the sibling `milestone-driver` schema/consumer by the deliberate "safe to ship independently and first" decision; the driver consumer treats absent `projectDocs` as `.project/`, so there is no behavior regression while the sibling driver-side reader is pending.
- Version-free mode — no per-PR version bump.

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
