---
name: apply
description: This skill should be used when the user invokes "/milestone-bootstrapper:apply", or asks to "apply the plan", "deploy the bootstrap", or "provision the repo from the approved plan". Executes the approved provisioning plan file on the repo — project docs, configs, labels, branch model, CI workflow, and branch protection — in a fixed safe order, by invoking the already-built component scripts. Reads the plan file and deploys exactly it; it does NOT re-interview, re-detect, or re-plan. Ordered and idempotent: a re-run after a partial failure resumes from the first incomplete step, as long as every component script remains independently idempotent. No flags. Authors no application code; opens no PRs.
---

# apply — deploy the approved provisioning plan to the repo (read-the-plan, faithful, ordered)

Resolve the provisioning plan file `plan` wrote for this project (same deterministic slug), then execute **exactly it**: populate the project docs, write the configs, provision the labels, create the branch model, emit the CI workflow, and assert branch protection — each a thin invocation of the component script that owns that slice, in the **safe write order** (`SPEC.md` §7). Where `plan` *previews* the provisioning plan, `apply` *executes* it.

`apply` is **faithful**: it does **NOT** re-run the understanding interview, re-run stack detection, or re-compose the plan. It reads the plan file's recorded values and hands them to the component scripts, which place them deterministically ([BRIEF.md:22-26,64](../../BRIEF.md): preview-then-execute; the approved plan file is the contract). The plan-file format is owned by `SPEC.md` (§4, §8) and rendered by `plan` (`skills/plan/SKILL.md` Step 5) — `apply` reads that format; it does not redefine it.

**No flags** — `apply` is the first-deploy write verb of the plan/apply/update trio ([BRIEF.md:64](../../BRIEF.md)). It authors no application code and opens no PRs; its writes are the project-docs population, the `.milestone-config/*` config files, and the GitHub suite-readiness state (labels, branches, protection, CI) — all performed by the component scripts (`scripts/*.sh` / `*.ps1`), never by a dispatched agent.

This skill mirrors the sibling feeder deploy verb's shape ([`milestone-feeder/skills/create/SKILL.md`](../../../milestone-feeder/skills/create/SKILL.md)): announce-first, a numbered procedure, defined partial-failure semantics (`create/SKILL.md:164-174,232-242`), an output style, and a non-negotiables block — transposed to the bootstrapper's surface (settings + docs, not issues).

## Announce first

Say this before doing any work — pick the line matching the resolution outcome:

> **Plan file found:** Standing by while I deploy the approved provisioning plan to your repo — project docs, configs, labels, branch model, CI workflow, and branch protection, in that safe order. I'm deploying **exactly the plan you approved** — no re-interview, no re-detection, no re-plan; each step just runs the component that owns it.

> **No plan file yet:** I don't have a provisioning plan file for this project, so there's nothing to deploy. Run `/milestone-bootstrapper:plan` first — it interviews you, detects the stack, and writes a reviewable plan file — then re-run `apply` to deploy it.

## Procedure

### Step 0 — Read the bootstrapper context + check the `gh` precondition

**Resolve the project-docs path** from `.milestone-config/feeder.json#projectDocs` (default `.project/`, `SPEC.md` §4.1) — the plan file's own `Project-docs path` field is authoritative, resolved once at plan time so `apply` writes to the same place.

**`appRoots` needs no re-deriving.** It shaped `plan`'s per-root detection and glob-baking; by the time `apply` reads the plan, the §A docs are already the unioned capture and the §B `sourceGlobs`/`uiSurfaceGlobs` are already root-absolute. `apply` does not re-detect, re-bake, or write an `appRoots` key anywhere (plan-file-only — `SPEC.md` §6.1) — it passes the recorded globs verbatim to the config writers (Step 3, step 2), regardless of app-root nesting.

**Check the `gh` precondition up front, never silently** ([BRIEF.md:82](../../BRIEF.md)) — the consequential tail (branches, CI, protection) needs `gh` authenticated, and protection needs repo-admin scope. Probe read-only:

```bash
gh auth status >/dev/null 2>&1 && gh_ok=1 || gh_ok=0
```

```powershell
gh auth status *> $null; $ghOk = $LASTEXITCODE -eq 0
```

| `gh` state | What `apply` does |
|---|---|
| Authenticated, sufficient scope | Proceed through all six steps. |
| Absent / insufficient scope | Local steps (docs, configs) still run. Remote steps (labels, branch model, CI, protection) are **🔴 blocked-on-precondition** — named clearly (`gh auth login`; repo-admin for protection), never attempted. The components self-check this too; surfacing it first gives one clear message instead of a mid-run failure. |

The precondition gates only the remote-dependent steps, never the docs or config writes.

### Step 1 — Resolve the provisioning plan file

Derive `<slug>` **deterministically** from the one-line project goal, using the same algorithm `plan` uses (`skills/plan/SKILL.md` Step 5; `SPEC.md` §2.2): lowercase, collapse non-alphanumeric runs to a single hyphen, strip leading/trailing hyphens, cap the length per `SPEC.md` §2.2 step 5. The same goal always resolves to `.milestone-bootstrapper/plan-<slug>.md`.

| Resolution | Action |
|---|---|
| **Found** | Read it; deploy **exactly it** (Step 2 contract). No interview, detection, or re-plan. |
| **Absent** | Stop with the no-plan message (Announce-first). `apply` never silently runs `plan` — `plan` is an interactive interview, and running it unattended mid-`apply` would re-interview the user, violating the plan-is-the-contract model ([BRIEF.md:22-26,64](../../BRIEF.md)). Tell the user to run `/milestone-bootstrapper:plan` first, then re-run `apply`. |

**A changed goal earns a fresh plan.** The slug is a function of the goal, so a changed goal derives a different slug → no match at the path above → the **Absent** row fires (`SPEC.md` §3). A matching slug means the recorded plan is what you approved.

### Step 2 — Read the plan-file contract (the fields `apply` parses)

The plan file is the **load-bearing build artifact** — `apply` reads it and deploys from it, regenerating nothing (`SPEC.md` §1). Parse the fields by name (format: `skills/plan/SKILL.md` Step 5 / `SPEC.md` §8; requirements: `SPEC.md` §4). A required field that is absent or unparseable is a **malformed plan** — error-and-stop with the missing field named, never deploy a partial spec.

The fields `apply` reads: **Slug** (identity — Step 1 resolved the file by it); **Status** (`READY`\|`FLAGGED` — re-surface every 🔴 `[TBD]` regardless); **Project-docs path** (where §A lands — Step 0's value MUST agree); **App-roots** (context only, already baked into §A/§B at plan time, re-derived from nowhere); **§A Project docs** rows (Doc·State·Reconcile·Captured understanding — step (1)); **§B Configs** rows (Key·State·Reconcile·Value — step (2)); **§B Labels** rows (Label·State·Reconcile — step (3)); **§B Branch model/protection/CI** rows (Target·State·Reconcile·Value — steps (4)→(6); the branch names also feed `driver.json` at step (2) for the tail to read back).

**Every entry's State is honored, never collapsed** (`SPEC.md` §4.3):

| State | What `apply` does |
|---|---|
| `captured` | A recorded decision → deploy it. |
| `none` | A recorded "not applicable" → **a no-op, reported as a no-op** (e.g. empty `domainSkills` omits the key; no protection rule skips protection). Never aborts, never fabricates a default (issue AC-3). For project-doc anchors, `none` is itself a captured answer the writer records (no 🔴). |
| `[TBD]` 🔴 | A flagged genuine unknown → **re-surfaced to the human** before proceeding; for doc anchors the writer leaves the placeholder, flagged (never fabricated). A `[TBD]` config/branch/protection/CI value is surfaced and left unwritten rather than guessed. |

`apply` re-derives none of this — it deploys the recorded values through the owning component.

### Step 3 — Deploy (the six steps, in this fixed safe order)

This is the `SPEC.md` §7 safe write order: **low-risk writes first (docs, configs, labels), then the consequential tail (branch model → CI → branch protection)**. Each step is a **thin invocation** of the component that owns its slice — `apply` orchestrates ordering and reporting only, never duplicating a component's logic (issue Design; `SPEC.md` §7) — and each component is itself independently **idempotent** (Step 4). Steps (3)–(6) each also perform a cheap post-write read-back with exactly one retry on mismatch before halting — never a second retry, never a rollback; see each step's reference file for the exact check.

> **Order note — CI before protection.** Branch protection registers the CI workflow's job names (`unit-tests`/`preflight`) as required status-check contexts, which must already exist when protection runs ([BRIEF.md:90](../../BRIEF.md); `scripts/emit-ci-workflow.sh` CONTEXT-NAME STABILITY CONTRACT). So the tail's order is **branch model (#10) → CI (#11) → branch protection (#12)** — CI strictly before protection (issue AC-1, AC-2), the topological resolution of that dependency (`SPEC.md` §7).

Every component ships as bash/PowerShell twins — same behavior, different CLI convention (bash `--flag`/`--dry-run`; PowerShell PascalCase `-Flag`/`[switch]$DryRun`). A `.ps1` won't bind bash-style `--flag` tokens, so use the twin matching your shell. Resolve `<projectDocs>` and `<repo>` from Step 0; each step below points to its reference file for the exact invocation and flags, needed only when actually running or building that step.

#### Step (1) — Project docs (lowest risk) — invokes #7

For each **§A** row, populate its doc via the project-docs writer, keyed by anchor using the **fixed field→doc→anchor map** (`docs/understanding-interview.md` §2). A `none` row records the recorded "None" answer under its anchor; a `[TBD]` 🔴 row leaves the placeholder in place, flagged. The writer is idempotent and append-only. CLI syntax + flags: [`references/project-docs.md`](references/project-docs.md).

#### Step (2) — Configs — invokes #5 and #8 (order-independent within this step)

Write `feeder.json` (#5) and `driver.json` (#8) from the §B Configs rows — order-independent relative to each other, both non-interactive direct writers (**never** the interactive `setup` interviews, which would re-interview the user mid-run). Values (including `sourceGlobs` / `uiSurfaceGlobs`) are passed verbatim; the single recorded versioning answer dual-writes to each file's distinct key shape. Configs land before the branch/CI/protection tail because those steps read the branch names back from `driver.json`. CLI syntax + the full flag-by-flag mapping (versioning dual-write, stack/nonNegotiables optional pass-through): [`references/configs.md`](references/configs.md).

#### Step (3) — Labels — invokes #6

Provision the eleven-label taxonomy (`SPEC.md` §6.3) idempotently — `--force` upsert: create/correct, never duplicate. **Remote step**, 🔴 blocked-on-precondition per Step 0. A `none`-state row is a reported no-op. CLI: [`references/labels.md`](references/labels.md).

#### Step (4) — Branch model — invokes #10

Create the integration + protected branches if missing and set the default-branch policy, read from the `driver.json` written at step (2). Never deletes, force-pushes, or resets. **Remote step**, 🔴 blocked-on-precondition per Step 0. CLI: [`references/branch-model.md`](references/branch-model.md).

#### Step (5) — CI workflow (BEFORE protection) — invokes #11

Emit `.github/workflows/ci.yml` from the `driver.json` test/preflight commands. Its job `name:` values ARE the required-status-check contexts step (6) registers — why CI must land first. An absent command still gets a 🔴-flagged job rather than a fabricated one; a file that differs from the emitted shape is never clobbered (exit 3, surfaced 🔴 — `update`'s job to reconcile). CLI: [`references/ci-workflow.md`](references/ci-workflow.md).

#### Step (6) — Branch protection (AFTER CI) — invokes #12

Assert the protected branch's safety floor (no direct push, PR + CI checks required, `enforce_admins`, no force-push/deletions) against the contexts CI just emitted — that file must already exist, which is why this step is last. **Merges UP**: GETs existing protection and keeps the stronger value per field, never reconciling down. **Remote step needing repo-admin**, 🔴 blocked-on-precondition per Step 0. CLI: [`references/branch-protection.md`](references/branch-protection.md).

### Step 4 — Idempotency + resume model (no apply-side state ledger)

`apply` carries **no separate state ledger** (issue AC-5; [BRIEF.md:54](../../BRIEF.md)). A re-run re-invokes **every** component in the same safe order; each component **no-ops when its artifact is already present** — so a partial run is resumed simply by **re-running `apply`**, as long as every component script remains independently idempotent: completed steps are skipped (the component finds its artifact already correct and changes nothing) and the run continues from the first incomplete step to completion. Re-asserting branch protection to match the plan is explicitly allowed (idempotent — merge-UP — not destructive; [BRIEF.md:65](../../BRIEF.md)). Idempotency lives in the units, mirroring the feeder create skill's defined idempotent-resume pattern (`create/SKILL.md:166-174`).

### Partial-failure path (halt, name the step, resume on re-run)

If **any single step's component fails mid-run** (e.g. branch-protection fails for insufficient `gh` scope, or `emit-ci-workflow` exits 3 on a diverged file), `apply` **halts** — it does not run the remaining steps against a missing prerequisite. The failure is **defined, not silent** (issue AC-4; mirrors `create/SKILL.md:164-174,232-242`):

| On failure, `apply` does | It does NOT |
|---|---|
| **Halt** at the failed step. | Continue past a failed prerequisite (e.g. run protection after CI failed). |
| **Name the failed step** and its component exit code/message. | Swallow the error or report "done". |
| **Report what was already written** and what was not (every prior step's writes stay intact). | **Roll back, force-push, or delete** any prior write — never (`SPEC.md` §6.3; [BRIEF.md:65](../../BRIEF.md)). |
| For a **precondition** failure (insufficient `gh` scope), surface it **🔴** with what to grant. | Silently skip a precondition-blocked step. |

**Resume:** re-running `apply` after a partial failure re-invokes every component in the same safe order; the idempotent units no-op the already-completed steps and the run continues from the first incomplete step (Step 4), as long as every component script remains independently idempotent. There is no rollback because every component is non-destructive and re-runnable — the resume *is* the recovery.

## Output style

Be concise — report status and outcomes flatly, no wall-of-text. Present the precondition status, the plan summary, the six-step deploy, and the per-step outcomes as **tables**, not inline prose. Mark anything that needs a human with 🔴 — every re-surfaced `[TBD]` and every blocked-on-precondition step. (Mirrors the suite's shared output style — [BRIEF.md:80](../../BRIEF.md); `create/SKILL.md` Output style; `plan`'s output style.)

## Non-negotiables

- **Deploys the plan file; re-derives nothing.** No re-run of the understanding interview, stack detection, or plan re-composition — recorded values (§A docs, §B configs/labels/branch/protection/CI) pass straight to the component scripts. The plan-file format is owned by `SPEC.md`, not redefined here ([BRIEF.md:22-26,64](../../BRIEF.md); `SPEC.md` §1).
- **Fixed safe write order: docs → configs → labels → branch model → CI → branch protection**, with **CI strictly before protection** — protection's required status checks must already exist as CI job names ([BRIEF.md:90](../../BRIEF.md); `SPEC.md` §7; issue AC-1, AC-2).
- **Each step is a thin invocation of its owning component** (docs→#7, configs→#5/#8, labels→#6, branch model→#10, CI→#11, protection→#12) — `apply` orchestrates only, duplicating no component's logic (issue Design; `SPEC.md` §7).
- **Non-interactive, direct-write path only.** Config writers (#5/#8) are invoked directly, never the interactive `setup` interviews — running those mid-`apply` would re-interview the user, breaking the plan-is-the-contract model (`scripts/write-driver-config.sh`/`write-feeder-config.sh` headers).
- **Ordered + idempotent, no apply-side state ledger.** A re-run after a partial failure resumes from the first incomplete step by re-running `apply`, as long as every component script remains independently idempotent; re-asserting protection (merge-UP) is allowed, never destructive ([BRIEF.md:54,65](../../BRIEF.md); `create/SKILL.md:166-174`).
- **Three states, never collapsed** — `captured` deploys; `none` is a reported no-op, never a fabricated default; `[TBD]` 🔴 is re-surfaced and left unwritten/placeholder, never fabricated (`SPEC.md` §4.3; issue AC-3).
- **Partial failure halts — after each remote-writing step's bounded one-retry read-back — names the failed step, reports what was/wasn't written, and never rolls back, force-pushes, or deletes** (issue AC-4; `create/SKILL.md:164-174`).
- **The `gh` precondition is surfaced, never silent** — local steps (docs, configs) run regardless; remote steps (labels, branch model, CI, protection — the last needing repo-admin) are 🔴 blocked-on-precondition, reported before the attempt ([BRIEF.md:82](../../BRIEF.md); issue AC-6).
- **Authors no application code, opens no PRs.** The writes are the project-docs population, the `.milestone-config/*` configs, and the GitHub suite-readiness state — performed by the component scripts, not by any dispatched agent. `apply` edits no application source file and opens no PR.
