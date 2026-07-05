---
name: apply
description: This skill should be used when the user invokes "/milestone-bootstrapper:apply", or asks to "apply the plan", "deploy the bootstrap", or "provision the repo from the approved plan". Executes the approved provisioning plan file on the repo — it writes the project docs, the configs, the labels, the branch model, the CI workflow, and branch protection, in a fixed safe order, by invoking the already-built component scripts. Reads the plan file and deploys exactly it; it does NOT re-interview, re-detect, or re-plan. Ordered and idempotent: a re-run after a partial failure resumes from the first incomplete step. No flags. Authors no application code; opens no PRs.
---

# apply — deploy the approved provisioning plan to the repo (read-the-plan, faithful, ordered)

Resolve the provisioning plan file `plan` wrote for this project (by the same deterministic slug), then execute **exactly it**: populate the project docs, write the configs, provision the labels, create the branch model, emit the CI workflow, and assert branch protection — each step a thin invocation of the already-built component script that owns that slice, run in the **safe write order** (`SPEC.md` §7, as resolved below). The deploy verb of the bootstrapper pipeline: where `plan` *previews* the provisioning plan, `apply` *executes* it.

`apply` is **faithful** — it deploys what you approved. It does **NOT** re-run the understanding interview (#4), re-run stack detection (#3), or re-compose the plan. The plan file already recorded every resolved decision (the captured understanding, the config values, the labels, the branch model, the protection rule, the CI commands); `apply` reads those recorded values and hands them to the component scripts, which place them deterministically. It re-derives nothing ([BRIEF.md:22-26,64](../../BRIEF.md): preview-then-execute; the approved plan file is the contract). The plan-file format is owned by `SPEC.md` (§4 the field contract, §8 the worked shape) and rendered by `plan` (`skills/plan/SKILL.md` Step 5) — `apply` reads that format; it does not redefine it.

**No flags** — `apply` *is* the first-deploy write verb of the plan/apply/update trio; there is nothing to argument-parse ([BRIEF.md:64](../../BRIEF.md): "Verbs `plan` / `apply` / `update`, no flags"). It authors no application code and opens no PRs; the writes it performs are the project-docs population, the `.milestone-config/*` config files, and the GitHub suite-readiness state (labels, branches, protection, CI) — all performed by the component scripts (`scripts/*.sh` / `*.ps1`) the skill invokes, never by a dispatched agent.

This skill mirrors the sibling feeder deploy verb's shape ([`milestone-feeder/skills/create/SKILL.md`](../../../milestone-feeder/skills/create/SKILL.md)): a frontmatter `name`/`description`, an "Announce first" line, a numbered "Procedure" that reads the plan then deploys in a fixed order, defined partial-failure semantics (`create/SKILL.md:164-174,232-242`), an output style, and a non-negotiables block — transposed to the bootstrapper's surface (it deploys settings + docs, not issues).

## Announce first

Say this to the user before doing any work — pick the line that matches the resolution outcome (the plan file was found, or it was absent):

> **Plan file found:** Standing by while I deploy the approved provisioning plan to your repo — I'll populate the project docs, write the configs, provision the labels, create the branch model, emit the CI workflow, and assert branch protection, in that safe order. I'm deploying **exactly the plan you approved** — I re-interview nothing, re-detect nothing, and re-plan nothing; each step just runs the component that owns it.

> **No plan file yet:** I don't have a provisioning plan file for this project, so there's nothing to deploy. Run `/milestone-bootstrapper:plan` first — it interviews you, detects the stack, inspects the repo, and writes a reviewable plan file — then re-run `apply` to deploy it.

## Procedure

### Step 0 — Read the bootstrapper context + check the `gh` precondition

**Resolve the project-docs path.** Read `.milestone-config/feeder.json#projectDocs` when present, else default `.project/` (`SPEC.md` §4.1). The plan file also records this once as its `Project-docs path` field (Step 1); the two MUST agree. Use the plan file's recorded value as authoritative — it was resolved at plan time so `apply` writes to the same place (`SPEC.md` §4.1: "Resolved once at plan time so `apply` / `update` write to the same place").

**`appRoots` is already consumed — there is nothing to re-derive.** The plan file's `App-roots` field (`SPEC.md` §4.1, default `["."]`) was the **input** to `plan`'s per-root detection and glob-baking; by the time `apply` reads the plan, that work is **done** — the §A docs are the unioned capture and the §B `sourceGlobs` / `uiSurfaceGlobs` are already **root-absolute** strings. `apply` therefore does **not** re-run the detector per root, does **not** re-bake any glob, and does **not** write an `appRoots` key anywhere (it is plan-file-only — `SPEC.md` §6.1). `apply` reads the recorded root-absolute globs and passes them **verbatim** to the opaque config writers (Step 3 (2)). `.project/` and `.milestone-config/` are written at the **project root** regardless of `appRoots` (`SPEC.md` §4.1) — the resolved project-docs path above is unaffected by app-root nesting.

**Check the `gh` precondition up front — surface it, never let it fail silently** ([BRIEF.md:82](../../BRIEF.md)). The consequential tail (branches, CI registration, branch protection) needs `gh` authenticated, and **branch protection needs repo-admin scope**. Probe `gh` auth read-only:

```bash
# bash — read-only precondition probe; captures status without changing anything.
gh auth status >/dev/null 2>&1 && gh_ok=1 || gh_ok=0
```

```powershell
# PowerShell 7+ — same read-only probe.
gh auth status *> $null; $ghOk = $LASTEXITCODE -eq 0
```

| `gh` state | What `apply` does |
|---|---|
| Authenticated with sufficient scope | Proceed normally through all six steps. |
| Absent / not authenticated / insufficient scope | The **local** steps (project docs, configs) still run — they touch no remote. The **remote** steps (labels, branch model, CI registration, branch protection) are **🔴 blocked-on-precondition**: surface a clear message naming what to grant (`gh auth login`; repo-admin for protection) and do **not** attempt those writes. A step blocked on precondition is **reported 🔴, never silently skipped** ([BRIEF.md:82](../../BRIEF.md)). The component scripts also self-check this and exit non-zero with a named precondition before touching anything (`scripts/provision-labels.sh`, `scripts/provision-protection.sh` Preconditions) — `apply` surfacing it first means the human sees one clear message instead of a mid-run failure. |

The precondition gates only the *remote-dependent* steps' deployability — it never blocks the project-docs population or the config writes.

### Step 1 — Resolve the provisioning plan file

Derive `<slug>` **deterministically** from the one-line project goal, using the **same algorithm `plan` uses** (`skills/plan/SKILL.md` Step 5; `SPEC.md` §2.2): lowercase the goal, replace every run of non-alphanumeric characters with a single hyphen, strip leading/trailing hyphens, cap the length per `SPEC.md` §2.2 step 5 (trim a trailing hyphen if the cut lands on one). The same goal always resolves to the same path:

```
.milestone-bootstrapper/plan-<slug>.md
```

Resolve the plan file at that path:

| Resolution | Action |
|---|---|
| **Found** | Read it; deploy **exactly it** (Step 2 contract) — no interview, no detection, no re-plan. Proceed to Step 2. |
| **Absent** | **Stop with the no-plan message** (Announce-first, "No plan file yet"). `apply` does NOT silently run `plan` — `plan` is an interactive interview, and running it unattended mid-`apply` would re-interview the user, violating the plan-is-the-contract model ([BRIEF.md:22-26,64](../../BRIEF.md); the same non-interactive-deploy invariant the config writers hold, `scripts/write-driver-config.sh` header). Tell the user to run `/milestone-bootstrapper:plan` first, then re-run `apply`. |

**Staleness (a changed goal earns a fresh plan).** The slug is a function of the project goal, so a **changed** goal derives a **different** slug → no match at the path above → the **Absent** row fires (`SPEC.md` §3, Stale brief: re-plan, then apply the fresh file). A matching slug means the recorded plan is what you approved.

### Step 2 — Read the plan-file contract (the fields `apply` parses)

The plan file is the **load-bearing build artifact** — `apply` reads it and deploys from it, regenerating nothing (`SPEC.md` §1). Parse the fields by name (the format is `skills/plan/SKILL.md` Step 5 / `SPEC.md` §8; the field requirements are `SPEC.md` §4). A required field that is absent or unparseable is a **malformed plan** — error-and-stop with the missing field named, never deploy a partial spec (`SPEC.md` §3).

| Plan-file field | What `apply` reads it for |
|---|---|
| **Slug** (`SPEC.md` §4.1) | The plan's identity — Step 1 resolved the file by it. |
| **Status** (`READY` \| `FLAGGED`, `SPEC.md` §4.1, §4.3) | A consumer surfaces this; `apply` may proceed but **re-surfaces every 🔴 `[TBD]` entry to the human first** (`SPEC.md` §4.1). |
| **Project-docs path** (`SPEC.md` §4.1) | Where §A docs are written (Step 0 — the two MUST agree). |
| **App-roots** (`appRoots`, `SPEC.md` §4.1) | Context only — it already shaped the §A union and baked the §B globs at plan time. `apply` **re-derives nothing from it**: it does not re-detect per root, does not re-bake globs, and writes no `appRoots` key. The §B `sourceGlobs` / `uiSurfaceGlobs` it reads are already root-absolute (Step 0). |
| **§A. Project docs** — one row per doc: Doc · State · Reconcile · Captured understanding (`SPEC.md` §4.2, §5) | The doc-population entries — deployed at step (1). Each carries all four §4.2 per-entry fields. |
| **§B. Configs** — `driver.json#…` / `feeder.json#…` non-default keys: Key · State · Reconcile · Value (`SPEC.md` §4.2, §6.1) | The config values — deployed at step (2). |
| **§B. Labels** — one row per label: Label · State · Reconcile (`SPEC.md` §6.3) | The label taxonomy — deployed at step (3). |
| **§B. Branch model · protection · CI** — Target · State · Reconcile · Value (`SPEC.md` §6.3) | The branch names, the protection rule, the CI commands — deployed at steps (4)→(5)→(6). The branch names feed `driver.json` at step (2), which the branch/CI/protection scripts then read. |

**Read every entry's State and honor it** (`SPEC.md` §4.3, never collapsed):

| State | What `apply` does |
|---|---|
| `captured` | A recorded decision → deploy it (pass the value to the owning component). |
| `none` | A recorded "not applicable" → **a no-op for that entry, reported as a no-op** (e.g. `domainSkills` empty → omit the key; `design-system.md` = none → leave its anchor untouched; no protection rule recorded → skip protection). **It does NOT abort and does NOT fabricate a default** (issue AC-3). For project-doc anchors, `none` is itself a captured answer the writer records (`scripts/write-project-docs.sh`: `state: none` replaces the placeholder with the recorded "None" answer — no 🔴). |
| `[TBD]` 🔴 | A flagged genuine unknown → **re-surface it to the human** before proceeding; for project-doc anchors pass `--state tbd` so the writer **leaves the placeholder and flags it 🔴** (never fabricates — `scripts/write-project-docs.sh`: `tbd` leaves `[TBD]` in place). A `[TBD]` 🔴 config/branch/protection/CI value is surfaced and the entry is left unwritten rather than guessed. |

`apply` does **not** re-derive any of these — it does not re-run the interview for the §A content, the detector for the configs, or recompute the branch model. It reads the recorded values and deploys them through the owning component.

### Step 3 — Deploy (the six steps, in this fixed safe order)

This is the `SPEC.md` §7 safe write order: **low-risk writes first (docs, configs, labels), then the consequential tail (branch model → CI → branch protection)**. Each step is a **thin invocation** of the component that owns its slice — `apply` orchestrates ordering and reporting only; it does **not** duplicate or re-derive any component's logic (issue Design; `SPEC.md` §7). Each component is itself **idempotent**, so a re-run that is already applied is a no-op (Step 4).

> **Order note — CI before protection (the topological resolution).** Branch protection registers the CI workflow's job names (`unit-tests` / `preflight`) as the required status-check contexts, and those contexts must already exist when protection registers them ([BRIEF.md:90](../../BRIEF.md); `scripts/emit-ci-workflow.sh` CONTEXT-NAME STABILITY CONTRACT; `scripts/provision-protection.sh` "required status-check contexts are SOURCED, never guessed"). So within the consequential tail the **CI workflow (#11) is written strictly before branch protection (#12) is asserted** — the authoritative unit-invocation order is **branch model (#10) → CI (#11) → branch protection (#12)** (issue AC-1, AC-2). This is the topological resolution of the dependency stated in `SPEC.md` §7 / [BRIEF.md:90](../../BRIEF.md) ("protection's required status check depends on the CI workflow existing").

All component scripts ship as cross-platform twins — invoke the `.sh` on bash, the behaviorally-equivalent `.ps1` on PowerShell 7+ (the suite's cross-platform convention; `docs/write-project-docs.md` "What runs it"). The twins do the same work and take the same inputs, but **their CLI surfaces differ by language convention**: the bash scripts parse `--flag` long options (and `--dry-run`), while the PowerShell scripts expose PascalCase `param()` parameters — `-Flag` (and a `[switch]$DryRun`). So each PowerShell invocation below uses `-Repo` / `-IntegrationBranch` / `-DryRun` etc., NOT the bash `--repo` / `--integration-branch` / `--dry-run` spellings — passing `--flag` tokens to a `.ps1` leaves its params unbound and the script fails its required-key guard. Resolve `<projectDocs>` and `<repo>` from Step 0.

#### Step (1) — Project docs (lowest risk) — invokes #7

For each **§A** row, populate its doc by invoking the project-docs writer (`scripts/write-project-docs.sh`, #7). The writer is the per-`##`-anchor placement primitive; `apply` keys the recorded captured understanding by anchor using the **fixed field→doc→anchor map** (`docs/understanding-interview.md` §2; `docs/write-project-docs.md` "Field → doc → anchor routing (FIXED)" — read it, do not re-derive it), builds the per-anchor JSON map, and calls the writer once per target doc:

```bash
# bash — populate one doc from the recorded per-anchor map. <map> is the JSON
# the caller composed from the §A captured understanding keyed by the FIXED anchor
# map; each value is { "state": "captured"|"none"|"tbd", "content": "<text>" }.
./scripts/write-project-docs.sh --template "<projectDocs>/<doc>" --map "<map.json>"
```

```powershell
# PowerShell 7+ — the behaviorally-equivalent twin (PascalCase -Flag params).
./scripts/write-project-docs.ps1 -Template "<projectDocs>/<doc>" -Map "<map.json>"
```

- A row whose **State is `none`** records the recorded "None" answer under its anchor (`--state none` → no 🔴); a doc that is wholly not-applicable (e.g. `design-system.md` / `tokens.json` for a backend-only repo) is a no-op reported as a no-op.
- A row whose **State is `[TBD]` 🔴** passes `--state tbd` for that anchor — the writer leaves the `[TBD]` placeholder and the entry stays flagged. Never fabricate the content.
- The writer is idempotent and append-only: it places content under the named anchor, never renames/reorders/invents a heading, and a re-run that finds the doc already populated changes nothing (`scripts/write-project-docs.sh` header).

#### Step (2) — Configs — invokes #5 and #8 (order-independent within this step)

Write the two config slices. They are **order-independent relative to each other** — `feeder.json` (#5) and `driver.json` (#8) neither depend on the other, so either may run first within step (2) (issue Design; [BRIEF.md:47](../../BRIEF.md)). Both writers are non-interactive direct writers (Option A) — **never** the interactive `setup` interviews (`scripts/write-driver-config.sh` header: "deliberately does NOT invoke `milestone-driver:setup` … invoking it from `apply` would re-interview the user mid-run").

Pass each writer the **resolved values from the §B Configs rows** (the writer re-derives nothing; detection happened in `plan`):

```bash
# bash — feeder.json slice (#5): the feeder-owned keys projectDocs / reviewer /
# versioning. Omit projectDocs/reviewer when at the bundled default; omit
# --versioning when the Tier-6 answer was skipped (versioning has NO default).
./scripts/write-feeder-config.sh --repo "<repo>" [--project-docs "<path>"] [--reviewer "<val>"] [--versioning "<semver|none>"]

# bash — driver.json slice (#8): the three Core keys are REQUIRED; optionals are
# omitted when the plan did not record them (never written as null/empty). The
# branch names recorded in §B (branch model) ARE driver.json#integrationBranch /
# #protectedBranch — write them here so steps (4)-(6) can read them back.
./scripts/write-driver-config.sh --repo "<repo>" \
  --integration-branch "<integration>" --protected-branch "<protected>" \
  --source-globs '<json string[]>' \
  [--project-docs "<path>"] \
  [--domain-skills '<json string[]>'] [--non-negotiables '<json string[]>'] [--versioning false] [--ui-surface-globs '<json>'] \
  [--stack '<enum>'] [--stack-version-file '<path>'] \
  [--unit-test-cmd "<cmd>"] [--preflight-cmd "<cmd>"] [--e2e-env '<json>']
```

```powershell
# PowerShell 7+ — the behaviorally-equivalent twins (PascalCase -Flag params).
./scripts/write-feeder-config.ps1 -Repo "<repo>" [-ProjectDocs "<path>"] [-Reviewer "<val>"] [-Versioning "<semver|none>"]
./scripts/write-driver-config.ps1 -Repo "<repo>" -IntegrationBranch "<integration>" -ProtectedBranch "<protected>" -SourceGlobs '<json string[]>' [-ProjectDocs "<path>"] [-DomainSkills '<json>'] [-NonNegotiables '<json>'] [-Versioning false] [-UiSurfaceGlobs '<json>'] [-Stack '<enum>'] [-StackVersionFile '<path>'] [-UnitTestCmd "<cmd>"] [-PreflightCmd "<cmd>"] [-E2eEnv '<json>']
```

- **`--project-docs` / `-ProjectDocs`** → pass the SAME Step-0-resolved project-docs value to BOTH writers, so `feeder.json#projectDocs` and `driver.json#projectDocs` cannot diverge. `apply` passes the resolved value uniformly; the writer itself omits the key when it equals the default `.project/` (omit-when-default lives in the writer, not in `apply`).
- **`sourceGlobs` / `uiSurfaceGlobs` are passed VERBATIM** → the §B values are already **root-absolute** (the app-root prefix was baked at plan time — `SPEC.md` §4.1, §6.1; the `"."` prefix was a no-op, so a single-root plan's globs are unprefixed). `apply` hands them to `--source-globs` / `--ui-surface-globs` exactly as recorded — it does **not** re-prefix, re-derive, or know the app-roots. The writers persist them opaquely (their headers: re-derive nothing), which is why **no `appRoots` key is ever written** to `driver.json`.
- **`versioning`** (DUAL-WRITE — one Tier-6 answer, two writers, two DISTINCT keys) → the single recorded versioning answer is passed to BOTH the driver and the feeder writer, mapped per its type:
  - **DRIVER** (`driver.json#versioning`, boolean) → `--versioning false` / `-Versioning false` **only when the plan recorded non-versioned**; omit otherwise (absent-means-versioned — the driver writer emits only `false`).
  - **FEEDER** (`feeder.json#versioning`, string enum) → `--versioning semver` / `-Versioning semver` when **versioned**; `--versioning none` when **non-versioned**; **omit** when the Tier-6 answer was skipped/[TBD] (the feeder key has no default — absent = infer-or-ask, `milestone-feeder/docs/profile-schema.md:52`; never write a placeholder).
- **`stack` / `stackVersionFile`** → pass `--stack` / `-Stack` (the resolved enum) and `--stack-version-file` / `-StackVersionFile` (the version-file PATH) **only when the §B Configs row recorded them**; omit when absent (the writer omits `stack` for `none`/empty and `stackVersionFile` when not passed — `scripts/write-driver-config.sh` stack validation). Same optional-pass-through shape as `--domain-skills` / `--versioning`.
- **`nonNegotiables`** → pass `--non-negotiables` / `-NonNegotiables` (the recorded JSON string[]) **only when the §B Configs row `driver.json#nonNegotiables` recorded it**; omit when absent (the writer omits it when not passed). Same optional-pass-through shape as `--domain-skills`.
- Both writers are idempotent: a re-run whose assembled object is byte-identical to the existing file leaves it untouched (true no-op; `scripts/write-feeder-config.sh` Behavior). For the feeder slice specifically, an all-default assembled object (`{}`) is **not emitted at all** — the writer leaves `feeder.json` **absent** rather than writing `{}`, so `milestone-feeder`'s absent-only first-run `setup` fires (issue #77).
- **Why configs come before the branch/CI/protection tail:** `provision-branches`, `emit-ci-workflow`, and `provision-protection` all **read the branch names from `.milestone-config/driver.json`** (their headers: "Branch names are SOURCED, never chosen"; "CONSUMES the values #8 already resolved"). If the config step has not landed, those steps hit a precondition failure. The safe order places configs at step (2) so the tail's prerequisite exists.

#### Step (3) — Labels — invokes #6

Provision the label taxonomy (the eleven-label taxonomy — `SPEC.md` §6.3) idempotently:

```bash
# bash
./scripts/provision-labels.sh
```

```powershell
# PowerShell 7+
./scripts/provision-labels.ps1
```

- `--force` upsert: creates a missing label, corrects a drifted color/description, never duplicates on re-run (`scripts/provision-labels.sh` header).
- **Remote step** — if Step 0 flagged the `gh` precondition, this is **🔴 blocked-on-precondition** (the script self-checks `gh` and exits non-zero with a named precondition before touching any label).
- A `none`-state label row (the plan recorded no labels to add) is a reported no-op — `apply` does not abort.

#### Step (4) — Branch model — invokes #10

Create the integration + protected branches if missing and set the default-branch policy:

```bash
# bash
./scripts/provision-branches.sh --repo "<repo>"
```

```powershell
# PowerShell 7+ (PascalCase -Flag params; -DryRun is a [switch]).
./scripts/provision-branches.ps1 -Repo "<repo>"
```

- Reads `integrationBranch` / `protectedBranch` from the `driver.json` written at step (2). Creates the protected branch (the base), branches integration off it, points the default branch at protected. **Never deletes, force-pushes, or resets** (`scripts/provision-branches.sh` header) — a re-run on an already-correct repo changes nothing.
- **Remote step** — 🔴 blocked-on-precondition when Step 0 flagged `gh` (branch creation + default-branch change need write/repo-admin scope).

#### Step (5) — CI workflow (BEFORE protection) — invokes #11

Emit `.github/workflows/ci.yml` running the recorded test/preflight commands on PRs into the integration branch:

```bash
# bash
./scripts/emit-ci-workflow.sh --repo "<repo>"
```

```powershell
# PowerShell 7+ (PascalCase -Flag param).
./scripts/emit-ci-workflow.ps1 -Repo "<repo>"
```

- Consumes `integrationBranch` / `unitTestCmd` / `preflightCmd` from the `driver.json` written at step (2) — re-detects nothing. It emits one named job per gate; the job `name:` values (`unit-tests`, `preflight`) ARE the required-status-check contexts step (6) registers (`scripts/emit-ci-workflow.sh` CONTEXT-NAME STABILITY CONTRACT). **This is why CI precedes protection** — the contexts must exist before protection requires them.
- An absent command still gets its job (so the context exists) with a `[TBD]`-flagged step surfaced 🔴; a command is never fabricated (`scripts/emit-ci-workflow.sh` Behavior).
- Idempotent: an absent file is created, a byte-identical file is a no-op, a file that **differs** is **not clobbered** (exit 3 — human edits preserved; reconciling a changed plan is `update`'s job, surfaced 🔴 rather than overwritten).

#### Step (6) — Branch protection (AFTER CI) — invokes #12

Assert the protected branch's server-side safety floor:

```bash
# bash
./scripts/provision-protection.sh --repo "<repo>"
```

```powershell
# PowerShell 7+ (PascalCase -Flag params; -DryRun is a [switch]).
./scripts/provision-protection.ps1 -Repo "<repo>"
```

- Reads `protectedBranch` from `driver.json` (step 2) and the required-status-check contexts from the `.github/workflows/ci.yml` emitted at step (5) — that file must already exist, which is why this step is **last**.
- Asserts the floor (no direct push, PR required, CI checks required, `enforce_admins`, no force-push/deletions), **merging UP**: it GETs existing protection first and keeps the stronger value per field, so re-asserting is a safe idempotent no-op and a stronger-than-floor setting is preserved, never reconciled down (`scripts/provision-protection.sh` header).
- **Remote step needing repo-admin** — 🔴 blocked-on-precondition when Step 0 flagged `gh` or the token lacks repo-admin (the script probes admin permission before any write and hard-stops with a clear message on insufficient scope).

### Step 4 — Idempotency + resume model (no apply-side state ledger)

`apply` carries **no separate state ledger** (issue AC-5; [BRIEF.md:54](../../BRIEF.md)). A re-run re-invokes **every** component in the same safe order; each component **no-ops when its artifact is already present** — so a partial run is resumed simply by **re-running `apply`**: completed steps are skipped (the component finds its artifact already correct and changes nothing) and the run continues from the first incomplete step to completion. Re-asserting branch protection to match the plan is explicitly allowed (it is idempotent — merge-UP — not destructive; [BRIEF.md:65](../../BRIEF.md)). Idempotency lives in the units, mirroring the feeder create skill's defined idempotent-resume pattern (`create/SKILL.md:166-174`).

### Partial-failure path (halt, name the step, resume on re-run)

If **any single step's component fails mid-run** (e.g. the branch-protection API call fails for insufficient `gh` scope, or `emit-ci-workflow` exits 3 on a diverged file), `apply` **halts** — it does not run the remaining steps against a missing prerequisite. The failure is **defined, not silent** (issue AC-4; mirrors `create/SKILL.md:164-174,232-242`):

| On failure, `apply` does | It does NOT |
|---|---|
| **Halt** at the failed step. | Continue past a failed prerequisite (e.g. run protection after CI failed). |
| **Name the failed step** and its component exit code/message. | Swallow the error or report "done". |
| **Report what was already written** and what was not (every prior step's writes stay intact). | **Roll back, force-push, or delete** any prior write — never (`SPEC.md` §6.3; [BRIEF.md:65](../../BRIEF.md)). |
| For a **precondition** failure (insufficient `gh` scope), surface it **🔴** with what to grant. | Silently skip a precondition-blocked step. |

**Resume:** re-running `apply` after a partial failure re-invokes every component in the same safe order; the idempotent units no-op the already-completed steps and the run continues from the first incomplete step (Step 4). There is no rollback because every component is non-destructive and re-runnable — the resume *is* the recovery.

## Output style

Be concise — report status and outcomes flatly, no wall-of-text. Present the precondition status, the plan summary, the six-step deploy, and the per-step outcomes as **tables**, not inline prose. Mark anything that needs a human with 🔴 — every re-surfaced `[TBD]` and every blocked-on-precondition step. (Mirrors the suite's shared output style — [BRIEF.md:80](../../BRIEF.md); `create/SKILL.md` Output style; `plan`'s output style.)

## Non-negotiables

- **`apply` deploys the plan file; it re-derives nothing.** It does NOT re-run the understanding interview (#4), re-run stack detection (#3), or re-compose the plan. It reads the recorded values (the §A captured understanding, the §B configs/labels/branch/protection/CI entries) and hands them to the component scripts. The plan-file format is owned by `SPEC.md`, not redefined here ([BRIEF.md:22-26,64](../../BRIEF.md); `SPEC.md` §1).
- **Fixed safe write order: docs → configs → labels → branch model → CI → branch protection.** Low-risk writes first; the consequential tail is branch model (#10) → CI (#11) → branch protection (#12). **CI is written strictly before protection** because protection registers the CI job names as the required status checks and those contexts must already exist ([BRIEF.md:90](../../BRIEF.md); `SPEC.md` §7; the topological resolution of that stated dependency — issue AC-1, AC-2).
- **Each step is a thin invocation of the owning component; `apply` orchestrates only.** The doc step runs #7, the config step runs #5 and #8, the label step runs #6, the branch step runs #10, the CI step runs #11, the protection step runs #12. `apply` duplicates none of their logic (issue Design; `SPEC.md` §7).
- **Non-interactive — direct-write path only.** The config slices use the deterministic writers (#5/#8, Option A), never the interactive `milestone-feeder:setup` / `milestone-driver:setup` interviews — running those mid-`apply` would re-interview the user, breaking the plan-is-the-contract model (`scripts/write-driver-config.sh` header; `scripts/write-feeder-config.sh` header).
- **Ordered + idempotent; no apply-side state ledger.** Each component no-ops when its artifact is already present; a re-run after a partial failure resumes from the first incomplete step simply by re-running `apply`. Re-asserting protection to match the plan is allowed (idempotent merge-UP, not destructive) ([BRIEF.md:54,65](../../BRIEF.md); `create/SKILL.md:166-174`).
- **Three distinct states, never collapsed** — `captured` deploys; `none` is a reported no-op (omit the key / record the "None" answer / skip the step — never a fabricated default); `[TBD]` 🔴 is re-surfaced to the human and left unwritten/placeholder, never fabricated (`SPEC.md` §4.3; issue AC-3).
- **Partial failure is defined, never silent, and never rolls back.** On any step's failure, `apply` halts, names the failed step and what was/wasn't written, leaves every prior write intact, and never rolls back, force-pushes, or deletes (issue AC-4; `create/SKILL.md:164-174`).
- **The `gh` precondition is surfaced, never silent.** The local steps (docs, configs) run regardless; the remote steps (labels, branch model, CI registration, branch protection — the last needing repo-admin) are 🔴 blocked-on-precondition when `gh` auth/scope is missing, reported before the attempt, never failed silently mid-run ([BRIEF.md:82](../../BRIEF.md); issue AC-6).
- **Authors no application code, opens no PRs.** The writes are the project-docs population, the `.milestone-config/*` configs, and the GitHub suite-readiness state — performed by the component scripts, not by any dispatched agent. `apply` edits no application source file and opens no PR.
