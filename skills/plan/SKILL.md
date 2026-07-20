---
name: plan
description: This skill should be used when the user invokes "/milestone-bootstrapper:plan", or asks to "plan the bootstrap", "preview the project setup", or "turn this repo into a reviewable provisioning plan". Interviews the human about the project's understanding (goal, architecture, stack, conventions, environment, versioning), inspects the repo, detects the stack, and writes a single reviewable provisioning plan file describing everything it would record into the project docs and change in the repo's suite-readiness — and writes nothing remote. Read-only on the repo and on GitHub: its entire output is one local scratch plan file. No flags. Authors no code; opens no PRs.
---

# plan — interview + inspect + detect → reviewable provisioning plan file

Read the bootstrapper's profile, check the `gh` precondition, run the understanding interview, detect the stack, inspect the repo (adopt-or-init), compose answers + signals via the doc/config mapping, and write one reviewable **provisioning plan file** — Job 1 (durable understanding), Job 2 (suite-readiness) — in the **exact format `SPEC.md` defines**. It **composes** three already-built components, performing **none of their writes itself**: the **understanding interview** (`docs/understanding-interview.md`, #4), **stack detection** (`scripts/detect-stack.sh`, #3), and the **doc/config mapping** (`docs/write-project-docs.md`, #7).

**Load-bearing invariant** (full statement in Non-negotiables): `plan` writes the plan file and NOTHING else ([BRIEF.md:22](../../BRIEF.md)) — `apply`/`update` (#13/#14) are the only verbs that execute it; these are consequential, long-lived decisions that deserve a human read first.

The plan-file format is owned by `SPEC.md`. The skill mirrors the sibling feeder `plan` skill's shape ([`milestone-feeder/skills/plan/SKILL.md:1-18`](../../../milestone-feeder/skills/plan/SKILL.md), `:258-262`), transposed to settings + docs (not issues).

## Announce first

Say this to the user before doing any work:

> Standing by while I interview you about the project, detect the stack, inspect the repo, and turn it all into a reviewable provisioning plan. This is read-only — I'll write a single plan file to local scratch and change nothing in your repo, your settings, or on GitHub. Review the plan, then run `/milestone-bootstrapper:apply` to deploy it.

## Procedure

### Step 0 — Read the bootstrapper profile + check the `gh` precondition

**Read the existing config (best-effort, read-only)** — `.milestone-config/driver.json`/`feeder.json`, neither **required** (a fresh repo has neither); seeds (a) the interview's defaults and (b) the adopt-or-init delta at Step 3.

Resolve the **target project-docs path** from `feeder.json#projectDocs` when set, else `.project/` (`SPEC.md` §4.1) — record once so the plan's `Target project-docs path` field and every §A entry agree.

Resolve the **app-roots** the same way (`SPEC.md` §4.1). **Default `["."]`** — the repo root *is* the app root (byte-identical to today). Step 0 seeds only this default; the real roots are discovered and confirmed at Step 2. See `references/nested-app-roots.md` for the nested/multi-root rule.

**Check the `gh` precondition up front — never let it fail silently** ([BRIEF.md:82](../../BRIEF.md)). Probe `gh auth status` read-only (bash: exit code; PowerShell 7+: `$LASTEXITCODE`):

| `gh` state | What `plan` does |
|---|---|
| Authenticated with sufficient scope | Proceed normally; remote-dependent entries (branch protection, CI) recorded as ordinary planned changes. |
| Absent / not authenticated / insufficient scope | **Surface a clear message** — never silent. `plan` still emits the plan file, marking those entries **🔴 blocked-on-precondition** rather than aborting; MUST NOT claim they will succeed. |

The precondition only gates *remote-dependent* entries — never the interview, detection, or plan-file write. Branch protection needs repo-admin scope; record on flagged entries.

### Step 1 — Run the understanding interview (#4)

Run the interview as `docs/understanding-interview.md` defines it (tier order, recording discipline); this step **invokes** it, tier-by-tier (§1, Tier order + gate questions):

| Tier | Captures | Target doc(s) |
|---|---|---|
| 1 · Goal & vision | What the project is for; what it optimizes for | `design-philosophy.md` |
| 2 · Architecture | Architectural stance, layering, boundaries | `design-philosophy.md` |
| 3 · Technology stack | Language + version, framework, SQL flavor + ORM, major libraries | `library-manifest.md` + `environment.md` |
| 4 · Environment model | Data stores + test-data isolation, caching, async/messaging, external services, deployment targets | `environment.md` |
| 5 · Mandated packages | Required libraries/tooling (distinct from detection) | `library-manifest.md` |
| 6 · Versioning policy | SemVer y/n, version-file location, bump cadence | `conventions.md` |
| 7 · Design system *(UI projects only)* | Tokens, components, layout, required states, a11y, voice | `design-system.md` + `tokens.json` |
| 8 · Configuration & secrets | Config/secret norms (connection strings, auth/JWT, API keys, notification targets, CORS, per-env config, build outputs) — names/buckets/shapes/env/required, never values | `config-catalog.md` |

Honor the engine's recording discipline (`docs/understanding-interview.md` §1, §3):

- **Never a blank prompt.** Seed each field from Step 2's detection when available, else an illustrative example (§1, Default rule) — run Step 2 first (or interleave) so stack-derived fields carry a seed.
- **Three distinct states, never collapsed** (§3.2; full rule in Non-negotiables): `captured` / `none` (not a gap) / `[TBD]` 🔴 (never fabricated).
- **Skip → `[TBD]` 🔴 with its consequence stated** (§3.3): the skip prompt must state what stays unknown and which lens loses grounding.
- **Skip Tier 7 for a repo with no UI surface** — `design-system.md`/`tokens.json` record `none` (the correct "no design-lens grounding" signal, not an omission; Tier order note, `SPEC.md` §5).

This step **captures** the understanding; it records nothing. The field → `##` anchor map is owned by `docs/understanding-interview.md` §2 — carry each answer forward for Step 4.

### Step 2 — Resolve the app-roots from the layout, then detect the stack (#3) — once per app-root, then union

**First, resolve `appRoots` from the repo layout — before the detector loop consumes it** (otherwise a nested repo never gets per-root detection). Inspect read-only where the app's source signals live (`package.json`/`*.csproj`/`pyproject.toml`/`src/`):

- Repo-root signals → `["."]` (single-root, the default — **byte-identical to today**).
- Nested signals (`siteroot/web`, `siteroot/api`, etc.) → those paths, **confirmed with the human** before the loop consumes them.

This grounds Step 0's `appRoots` field (`SPEC.md` §4.1) in the actual layout, driving the detect+union below and the baked globs (Step 4); Step 3 re-states it, confirming rather than re-discovering.

**Run the stack detector read-only, once per resolved app-root, and union the findings** — it reports per-root and writes nothing (`scripts/detect-stack.sh` header), accepting a `[REPO_DIR]` positional (`.sh` Usage; `.ps1` `-RepoDir`), orchestrated here, not in the detector. A mixed-stack monorepo carries **both** stacks' conventions/pins/`domainSkills`, deduped (`SPEC.md` §4.1, §5); `flag = human` from any root → `[TBD]` 🔴 for that root. Default `["."]` runs once — **byte-identical to today**. See `references/nested-app-roots.md`.

The detector emits TSV — one finding per stack (`stack signal convention manifestPin domainSkills flag versionFile`) — seeding the interview's defaults and the plan's entries. Map `stack` to the `driver.json#stack` enum via `references/stack-detection-mapping.md`; `flag=human` → `[TBD]` 🔴, never guessed.

Detection **seeds** the defaults; the interview's confirmed answer reaches the plan — this resolved-wins rule covers `stack`/`stackVersionFile` like the sibling keys.

### Step 3 — Inspect the repo (adopt-or-init: a read-only delta)

Determine whether this is a **fresh** repo (bootstrap from empty) or an **existing** repo (plan only the delta) ([BRIEF.md:67](../../BRIEF.md); `SPEC.md` §4.4):

| Signal read (read-only) | Tells the plan |
|---|---|
| `<projectDocs>/` docs present? (per-doc, per-anchor — a `[TBD]` anchor counts as **not present**) | Which §A entries are "would populate" vs "already present". |
| `.milestone-config/driver.json` / `feeder.json` keys present? (read at Step 0) | Which §B keys are "would add", "already present", or "would change" (differs). |
| Existing branches/labels/branch protection/CI workflow (read-only `gh`/`git`, only where Step 0's precondition allows) | Which §B entries are "would create" vs "already present"; if blocked, flag 🔴 unknown-pending-precondition rather than guessing absent. |
| App layout — resolved/confirmed in Step 2 | Re-states the resolved `appRoots` in the read-only reconcile — confirms, does not re-discover (`references/nested-app-roots.md`). |

Map each entry's current-vs-planned state onto the `SPEC.md` §4.4 **reconcile class**:

- **fresh repo** (no `<projectDocs>/`, no `.milestone-config/*` keys): every entry is create/populate — §A docs `human-owned` (first `apply` writes onto an empty doc), §B config keys/labels/branches/CI `add`, protection `patch`.
- **existing repo**: `no-op` (matches), `add` (absent), `patch` (differs), or `human-owned` (human-maintained doc — propose, never overwrite); the human sees only the delta (a fully-synced repo is all-`no-op`, `SPEC.md` §4.4).

### Step 4 — Compose the entries through the doc/config mapping (#7)

Compose Step 1's answers + Step 2's signals into the plan's two job sections, per `docs/write-project-docs.md`'s mapping. `plan` **records** the entries — running the writer is `apply`'s job.

**Section A — project-docs population (Job 1, the core)** — one entry per standing doc (`SPEC.md` §5), keyed by its `##` anchor (§2). Four §4.2 fields: **Target** (doc path), **Captured value** (real, cited, never a placeholder), **Reconcile class** (default `human-owned` — propose, never overwrite, except a first `apply` onto an empty doc), **State** (`captured`/`none`/`[TBD]` 🔴 — `none` for a doc that doesn't apply, e.g. `design-system.md` backend-only).

**Bake the app-roots into the emitted globs (root-absolute, at scaffold time)** — prefix each app-root onto that root's `sourceGlobs`/`uiSurfaceGlobs` (`SPEC.md` §4.1, §6.1). Default `["."]` is a no-op — globs unchanged (no-regression guarantee, §4.1). For nested/multi-root `appRoots`, see `references/nested-app-roots.md`.

**Section B — suite-readiness (Job 2, supporting)** — record only non-default/create-if-missing entries. Configs are machine-owned, never `human-owned`; **no `appRoots` key is ever written** (plan-file-only; `SPEC.md` §6, §6.1, §4.1).

| Entry | Detail | Reconcile |
|---|---|---|
| `integrationBranch` / `protectedBranch` | branch model | `add` |
| `sourceGlobs` / `uiSurfaceGlobs` (or `none`) | root-absolute, app-root-prefixed (above) | `add`/`patch` |
| `unitTestCmd` / `preflightCmd` / `e2eEnv` (or `none`) | [detected](references/stack-detection-mapping.md) | `add` |
| `domainSkills` / `nonNegotiables` | deduped **union** across app-roots (§2 detection / §A capture) | `add` |
| `stack` / `stackVersionFile` | §2 detection enum / `versionFile` column (PATH, omitted if empty) | `add` |
| `integrationProtection` | §1 gate — `floor` when opted in; omit for `none`/skip | `add` |
| `versioning` | Tier 6 — **DUAL-WRITE**: `driver.json#versioning` **boolean**; `feeder.json#versioning` **string enum** (`milestone-feeder/docs/profile-schema.md:52`). Versioned → omit/`"semver"`; non-versioned → `false`/`"none"`; skipped/`[TBD]` → omit both. | `add`/`patch` |
| `feeder.json#projectDocs` | when non-default | `add` |
| Version-file / bump target (Tier 6) | `captured` (`.claude-plugin/plugin.json`) plugin repo; `none` for `versioning: none`; **`[TBD]` 🔴** non-plugin, no version file ([BRIEF.md:38](../../BRIEF.md); `SPEC.md` §6.2). | `human-owned` |
| Label taxonomy | One per label, from the authoritative set (`SPEC.md` §6.3). | `add` |
| Branch model | One per branch (integration, protected) + default-branch policy; never delete (`SPEC.md` §6.3). | `add` |
| Branch protection | No direct push, PR + CI check required, optional review. | `patch` |
| CI workflow | `.github/workflows/` path running `unitTestCmd`/`preflightCmd` on PRs into the integration branch, the required check. | `add`/`patch` |

Apply each entry's reconcile class + state from the Step 3 delta. Record the **safe write order** (`SPEC.md` §7): 1) project docs, 2) configs, 3) labels, 4) branch model → protection → CI. Protection + CI are **🔴 blocked-on-precondition when Step 0 flagged `gh`.**

### Step 5 — Assemble + write the plan file

Derive the **deterministic slug** from the one-line goal (`SPEC.md` §2.2, the feeder's algorithm): lowercase, collapse non-alphanumeric runs to a hyphen, strip leading/trailing hyphens, cap the length per `SPEC.md` §2.2 step 5. Re-running `plan` on the same goal overwrites the same path — never a second divergent file.

Set the **plan-level status line** (`SPEC.md` §4.1): `READY` when every section is resolved or recorded `none`; `FLAGGED` when one or more 🔴 `[TBD]` fields (or 🔴 blocked-on-precondition entries) remain.

Write the reviewable plan file to the per-run scratch path (`SPEC.md` §2.1):

```
.milestone-bootstrapper/plan-<slug>.md
```

`.milestone-bootstrapper/` is the tool-namespaced, per-clone scratch directory — **should be gitignored** (analog to `.milestone-feeder/`/`.milestone-driver-*`), but `plan` writes there regardless and doesn't edit `.gitignore` (`apply`/`update` own that). Write **BOM-free UTF-8, LF endings, single trailing newline**.

Write the file in the **`SPEC.md` §8 shape** (§4 fields are the contract) — see `references/plan-file-skeleton.md`.

Every §A/§B entry carries all four §4.2 fields (Target / Captured value / Reconcile class / State) — missing any fails malformed-plan detection (`SPEC.md` §3, §4.2). Keep `none` (recorded decision) and `[TBD]` 🔴 (flagged unknown) distinct — never collapse them (`SPEC.md` §4.3).

The plan file is local scratch — nothing else is written, no GitHub state of any kind created. `apply` is the only verb that executes it; `update` reconciles a refreshed one.

## Output style

Be concise — report status and outcomes flatly, no wall-of-text. Present the precondition status, the captures, the adopt-or-init delta, and the change preview as **tables**, not inline prose. Mark anything that needs a human with 🔴 — every flagged `[TBD]` and every blocked-on-precondition entry. A genuine unknown stays `[TBD]` 🔴; it is never fabricated to make the plan look complete. (Mirrors the suite's shared output style — [BRIEF.md:80](../../BRIEF.md); `docs/understanding-interview.md` §4.)

## Non-negotiables

- **`plan` writes the plan file (local scratch) and NOTHING else.** No project-docs population, no `.milestone-config/*` write, no labels, no branches, no branch protection, no CI, no GitHub state of any kind ([BRIEF.md:22](../../BRIEF.md); `SPEC.md` §1). After a `plan` run, the repo's `.project/`, `driver.json`, `feeder.json`, branches, protection, labels, and CI workflows are byte-for-byte unchanged; the only new artifact is the plan file. The plan **records** the planned changes; `apply` / `update` are the only verbs that execute them.
- **It composes the other steps; it performs none of their writes.** `plan` runs the interview (#4), the detector (#3, read-only), and the doc/config mapping (#7) into the `SPEC.md` plan-file format — it does not write a doc, set a config key, or run the project-docs writer. The plan-file format is owned by `SPEC.md`, not redefined here.
- **Three distinct states, never collapsed** — `captured` / `none` / `[TBD]` 🔴. "None" / "not yet" is a recorded value (a captured decision, not a gap, not `[TBD]`). A genuine unknown is left `[TBD]` and flagged 🔴 — **never fabricated, never silently defaulted** (`SPEC.md` §4.3; [BRIEF.md:30,66](../../BRIEF.md)).
- **Adopt-or-init is a read-only diff** — a fresh repo plans full provisioning (all create/populate); an existing repo plans only the delta (`no-op` / `add` / `patch` / `human-owned`). `plan` reads existing state to compute this and still writes nothing.
- **The `gh` precondition is surfaced, never silent** — on failure `plan` emits a clear message and marks the remote-dependent entries (branch protection, CI registration) 🔴 blocked-on-precondition; it MAY still emit the plan, but MUST NOT claim those steps will succeed ([BRIEF.md:82](../../BRIEF.md)).
- **Deterministic slug; re-run overwrites, never diverges** — the same goal resolves to the same `.milestone-bootstrapper/plan-<slug>.md` path; re-running overwrites it with equivalent content (`SPEC.md` §2.2).
- **`appRoots` shapes detection and bakes the globs — it is never a config key.** Default `["."]` is byte-unchanged (single-root; the `"."` prefix is a no-op, never `./`). For nested apps, `plan` detects **once per app-root** and unions the signals into one `.project/` + `nonNegotiables`, and prefixes each app-root into that root's `sourceGlobs` / `uiSurfaceGlobs` so the persisted globs are root-absolute strings the writers take verbatim. `appRoots` lives **only** in the plan file — never written into `driver.json` / `feeder.json`, never persisted under `.project/`; configs + `.project/` stay at the project root (`SPEC.md` §4.1, §6.1).
- **Authors no code, opens no PRs, never touches branches.** Reads code and repo state to ground decisions; never edits a source file, creates a branch, or opens a PR.
