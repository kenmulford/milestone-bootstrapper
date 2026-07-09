---
name: update
description: This skill should be used when the user invokes "/milestone-bootstrapper:update", or asks to "reconcile my refreshed plan", "my project changed — sync the bootstrap", "we adopted Redis / switched the ORM — update the docs and config", or "re-apply the plan onto the already-bootstrapped repo". Reconciles a refreshed provisioning plan onto an already-bootstrapped repo — diff-first, non-destructive. Re-runs `plan` first if no plan file exists, then diffs the refresh against live `.project/` docs and `.milestone-config/` configs: PATCHes drifted configs (diff first), ADDs what's new, PROPOSES — never overwrites — human-owned doc edits, and FLAGS — never deletes — anything absent from the plan. A fully-synced repo is a true no-op. No flags. Authors no code; opens no PRs.
---

# update — reconcile a refreshed plan onto an already-bootstrapped repo (diff-first, propose human-owned, non-destructive)

Refresh the plan file `plan` wrote for this project (same deterministic slug), then reconcile it onto the live repo, diffing each entry against live state per the PATCH/ADD/PROPOSE/FLAG contract. Where `apply` deploys onto a fresh repo, `update` re-deploys onto one that exists — the **architecture-changed path is first-class** ("we adopted Redis", "switched the ORM"): re-run `plan`, `update` reconciles the delta.

The **plan file is the source of truth** (`SPEC.md` §1); `update` is **idempotent** (a fully-synced repo is a true no-op, §4.4) and reconciles onto an **already-bootstrapped** repo only — the inverse of `apply`'s first-deploy branch (no `.project/` + no `.milestone-config/` → 🔴 error-and-stop, Step 1).

## Announce first

Say this to the user before doing any work — pick the line that matches the resolution outcome:

> **Bootstrapped repo + plan file found:** Standing by while I reconcile your refreshed plan onto the repo — diffing it against your live docs and configs, then **patching** drifted configs (diff first), **adding** what's new, **proposing** — never overwriting — doc edits, and **flagging** — never deleting — anything absent from the refresh. I re-assert protection and CI non-destructively; already matching is a **true no-op**.

> **No plan file yet:** I don't have a refreshed plan to reconcile. I'll run `/milestone-bootstrapper:plan` first — it interviews you, detects the stack, and writes a refreshed plan — then reconcile that onto your repo.

> **Repo not yet bootstrapped:** 🔴 No `.project/` and no `.milestone-config/` — nothing to reconcile against. `update` re-deploys onto an **already-bootstrapped** repo; it doesn't do the first deploy. Run `/milestone-bootstrapper:apply` first, then re-run `update` when your plan changes.

## Procedure

### Step 0 — Read the bootstrapper context + check the `gh` precondition

**Resolve the project-docs path** — `feeder.json#projectDocs` when present, else `.project/` (`SPEC.md` §4.1); must agree with the plan file's `Project-docs path` field (Step 2), authoritative for the bootstrapped-repo check (Step 1). **`appRoots`** likewise comes from the plan file, baked into the §B globs (default `["."]`) — `update` never re-bakes; a changed value surfaces as ordinary **glob drift** in §B Configs.

**Check the `gh` precondition up front** (`BRIEF.md:82`) — remote reconcile (labels, branches, CI, protection) needs `gh` authenticated; **protection needs repo-admin**:

```bash
gh auth status >/dev/null 2>&1 && gh_ok=1 || gh_ok=0
```

```powershell
gh auth status *> $null; $ghOk = $LASTEXITCODE -eq 0
```

| `gh` state | What `update` does |
|---|---|
| Authenticated, sufficient scope | Reconcile every section normally. |
| Absent / insufficient scope | **Local** reconcile (doc proposals, config patches) still runs; **remote** reconcile is 🔴 **blocked-on-precondition** — name what to grant. |

### Step 1 — Verify the repo is already bootstrapped

Confirm prior-`apply` evidence — read-only, for **either** `<projectDocs>` **or** `.milestone-config/`:

```bash
docs="<projectDocs>"; cfg=".milestone-config"
[ -d "$docs" ] && [ -n "$(ls -A "$docs" 2>/dev/null)" ] && have_docs=1 || have_docs=0
[ -d "$cfg" ]  && [ -n "$(ls -A "$cfg"  2>/dev/null)" ] && have_cfg=1  || have_cfg=0
```

```powershell
$docs = "<projectDocs>"; $cfg = ".milestone-config"
$haveDocs = (Test-Path -LiteralPath $docs) -and ((Get-ChildItem -LiteralPath $docs -Force -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)
$haveCfg  = (Test-Path -LiteralPath $cfg)  -and ((Get-ChildItem -LiteralPath $cfg  -Force -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)
```

| Evidence | Action |
|---|---|
| **Neither present** | 🔴 **ERROR-AND-STOP — no writes.** Print: `🔴 update: this repo shows no evidence of a prior apply — update reconciles onto an ALREADY-bootstrapped repo and never does the first deploy. Run /milestone-bootstrapper:apply first.` (mirrors the feeder update's ERROR-AND-STOP, `milestone-feeder/skills/update/SKILL.md:122`). **End the run.** |
| **At least one present** | Bootstrapped — proceed to Step 2. A partial bootstrap is never an error; the refresh's `add`-class entries fill the gap. |

### Step 2 — Resolve / refresh the plan file for the project

Derive `<slug>` **deterministically** from the one-line project goal — same algorithm `plan`/`apply` use (`SPEC.md` §2.2): lowercase, hyphenate non-alphanumeric runs, strip leading/trailing hyphens, cap the length per `SPEC.md` §2.2 step 5. The same goal always resolves to `.milestone-bootstrapper/plan-<slug>.md`.

| Resolution | Action |
|---|---|
| **Found** | Read it; reconcile **exactly it** (Step 3) against the live repo. |
| **Absent** | **Run `plan` first** — it writes the refreshed plan at this path; then reconcile it. `update` delegates the refresh rather than re-interviewing (unlike `apply`, which stops on an absent plan). |

**Staleness.** A changed goal derives a different slug — no match, so the **Absent** row fires (`SPEC.md` §3); a matching slug is the plan to reconcile — resolved by slug, not a deploy receipt (a feeder concept).

### Step 3 — Read the plan-file contract (the fields `update` reconciles)

The refreshed plan file is the **load-bearing build artifact** — `update` reads and reconciles against it, regenerating nothing (`SPEC.md` §1, §8, §4). A required field absent or unparseable is a **malformed plan** — error-and-stop, named. Same contract `apply` parses, plus `update` keys on each entry's **Reconcile class** (§4.4).

| Plan-file field | Reads it for |
|---|---|
| **Slug / Status** | Identity Step 2 resolved the file by; `update` still re-surfaces 🔴 `[TBD]`. |
| **Project-docs path / App-roots** | Where §A docs live (MUST agree, Step 0); globs already baked. |
| **§A Project docs** (Doc · State · Reconcile · Captured) | Step 4 (1); default `human-owned`. |
| **§B Configs** (Key · State · Reconcile · Value) | Step 4 (2); `add`/`patch`, never `human-owned`. |
| **§B Labels / Branch model · protection · CI** | Step 4 (3)→(4)→(5)→(6); labels `add` create-if-missing. |

**Honor every entry's State, never collapsed** — see Non-negotiables (`SPEC.md` §4.3).

### Step 4 — Reconcile (per entry, by reconcile class — diff-first, propose human-owned, flag live-only)

`update`'s **defining step**. For every §A/§B entry, key on its **Reconcile class** (`SPEC.md` §4.4), **announce-then-write each action**. The reconcile is **diff-first** — show the live→plan diff before writing; a byte-identical target is untouched. Steps 4(3)–4(6) are remote: each is 🔴 **blocked-on-precondition** per Step 0 (protection also needs repo-admin).

> **Cross-platform invocation.** Bash/PowerShell twins are behaviorally equivalent, **not byte-identical in CLI** (bash `--flag` vs PowerShell PascalCase `param()`, e.g. `-Repo`, `-DryRun` as `[switch]`) — a bash flag passed to a `.ps1` leaves its param unbound.

#### The four reconcile classes (per `SPEC.md` §4.4)

| Reconcile class | `update` behavior |
|---|---|
| `add` | New since the last `apply`. **Create it** through the owning component (nothing live to clobber). |
| `patch` | Exists live, value **changed**. **Tool-owned**: show the diff, then PATCH. **Human-owned**: see below — propose, never patch in place. |
| `human-owned` | A human-editable project doc. **PROPOSE**; **never overwrite** — apply only on acceptance. |
| `no-op` | Already matches the captured value. **Do nothing**, report it. |

**Tool-owned vs human-owned governs PATCH vs PROPOSE** — configs are mechanics the tool owns; docs are intent the human owns (`project-docs/SPEC.md` §1). Exception: a doc anchor still at `[TBD]` is not yet human-owned, so writing it is an `add`.

#### Entry-level resumability (worklist + state file)

Before walking 4(1)–4(6), compute the **worklist** — §A/§B entries whose Reconcile class is `add`/`patch` (`human-owned`/`no-op` excluded). Persist each entry's status by `Target` (`SPEC.md` §4.2) to `.milestone-bootstrapper/update-state-<slug>.json` (gitignored, §2.1); a re-run skips `done` entries, resuming from the first not-done one. An unreadable/invalid state file is flagged 🔴, discarded, and recomputed from scratch. Full completion **deletes** the file (ephemeral, `apply`'s no-ledger stance); an empty worklist skips the walk — Step 6's NO-OP line fires. Labels/branches (4(3)/4(4)) derive `done` status by re-checking live state afterward. See `references/entry-resumability.md` for the twins.

#### Step 4 (1) — Project docs (§A) — PROPOSE drift, ADD new sections (reuses #7)

For each §A row, reconcile against the live `<projectDocs>/<doc>`:

- **`no-op`** (matches captured) → nothing, report no-op.
- **`add`** (anchor absent or still `[TBD]`) → write the captured content:

```bash
./scripts/write-project-docs.sh --template "<projectDocs>/<doc>" --anchor "<## anchor>" --state captured --content "<captured text>"
```

```powershell
./scripts/write-project-docs.ps1 -Template "<projectDocs>/<doc>" -Anchor "<## anchor>" -State captured -Content "<captured text>"
```

- **`human-owned`** (differs from the refresh) → **PROPOSE, do NOT write.** Print the diff, marked 🔴 *proposed — accept to apply.* Write only after acceptance.
- **`none`** → reported no-op; never fabricated, never deleted.
- **`[TBD]` 🔴** → re-surface to the human; pass `--state tbd`/`-State tbd` if (re)writing so the placeholder stays.

Routed by the **fixed field→doc→anchor map** (`docs/understanding-interview.md` §2).

#### Step 4 (2) — Configs (§B) — PATCH drift, ADD new keys, PRESERVE live-only via the UNION write (reuses #5 and #8)

The two config writers are **whole-file rewriters, not patchers**, rebuilding the object from `{}` using only the keys passed, with **no `--dry-run`** — `update` computes the live→plan diff itself, shown first. A key not passed back is **dropped**, so `update` invokes each writer with the **UNION of keys** (every live key, plus every plan addition) — dropping nothing. Write through `apply`'s direct-write writers, never `setup`. See `references/config-union-write.md` for the rationale, per-key nuances, and the CLI invocation.

#### Step 4 (3) — Labels (§B) — ADD missing (reuses #6)

Reconcile the label taxonomy idempotently — `--force` upsert creates a missing label, corrects drifted color/description, never duplicates (`scripts/provision-labels.sh` header). No flags on either twin:

```bash
./scripts/provision-labels.sh
```

```powershell
./scripts/provision-labels.ps1
```

A `none`-state row is a reported no-op; a label live but absent from the plan is the live-only case (Step 5).

#### Step 4 (4) — Branch model (§B) — ADD missing, never delete (reuses #10)

Reconcile the integration + protected branches (create-if-missing) and default-branch policy — **never deletes, force-pushes, or resets** (`scripts/provision-branches.sh` header):

```bash
./scripts/provision-branches.sh --repo "<repo>"
```

```powershell
./scripts/provision-branches.ps1 -Repo "<repo>"
```

#### Step 4 (5) — CI workflow (BEFORE protection) — ADD/PATCH non-destructively (reuses #11)

Re-assert `.github/workflows/ci.yml` running the recorded test/preflight commands on PRs into the integration branch. **CI is reconciled strictly before protection** — its job names are the required status-check contexts (`BRIEF.md:90`; `scripts/emit-ci-workflow.sh` CONTEXT-NAME STABILITY CONTRACT). Non-destructive: absent → created, byte-identical → no-op, **differs → not clobbered** (exit 3, flagged 🔴):

```bash
./scripts/emit-ci-workflow.sh --repo "<repo>"
```

```powershell
./scripts/emit-ci-workflow.ps1 -Repo "<repo>"
```

#### Step 4 (6) — Branch protection (AFTER CI) — re-assert non-destructively (reuses #12)

Re-assert the protected branch's server-side safety floor — the **only re-assertion `update` performs** (`BRIEF.md:65`): GETs existing protection first, keeps the **stronger** value per field (**merge-UP**), so a stronger-than-floor setting is preserved (`scripts/provision-protection.sh` header):

```bash
./scripts/provision-protection.sh --repo "<repo>"
```

```powershell
./scripts/provision-protection.ps1 -Repo "<repo>"
```

### Step 5 — The live-only case (present live, absent from the refreshed plan) — FLAG 🔴, NEVER delete

A target present **live** but **absent from the refreshed plan** — a doc anchor, config key, label, or branch — is **flagged 🔴 and never removed** (mirrors the feeder update's flag-don't-close stance, `milestone-feeder/skills/update/SKILL.md:141`). For a **config key** this is active: the writers rebuild the whole file (Step 4 (2)), so `update` passes it back in the union write.

| Live-only target | Detection | Why flagged, never deleted |
|---|---|---|
| `.project/` doc/anchor | Human content live; no §A row. | Human-owned intent — the human's call. |
| Config key | Live config has it; no §B row. | Destructive to strip — flag **and** pass back in the union write. |
| Label | `gh label list` shows it; no §B row. | Could orphan issues — never auto-delete. |
| Branch | `git`/`gh` shows it; no branch entry. | `update` never deletes a branch. |

See `references/live-only-worked-example.md` for a full worked example — a dropped `domainSkills` entry preserved alongside a live-only `conventions.md` section.

### Step 6 — Report (diff-list + flags + summary)

Write a concise reconcile report (table form):

- **PATCHED (tool-owned):** each drifted target applied after its diff was shown — N patched.
- **ADDED:** each new section/key/label/branch created — M added.
- **PROPOSED (human-owned) 🔴:** each drifted doc anchor's diff — applied only on acceptance. P proposed.
- **LIVE-ONLY (flagged) 🔴:** the Step 5 set — never removed. F flagged.
- **Blocked-on-precondition 🔴:** any remote step Step 0 gated on `gh`/repo-admin.
- **NO-OP:** nothing drifted/new/differing/live-only → the single line `update: repo already matches the refreshed plan — nothing to reconcile (no-op)`.

## Output style

Be concise — report status flatly, no wall-of-text. Present the precondition status, bootstrapped-repo check, per-class reconcile, and per-entry outcomes as **tables**, not inline prose. Show every PATCH/PROPOSE as a unified-style diff before any write. Mark anything needing a human with 🔴 — every re-surfaced `[TBD]`, proposed edit, live-only flag, and blocked-on-precondition step (`BRIEF.md:80`).

## Non-negotiables

- **Reconciles onto an ALREADY-bootstrapped repo — not-bootstrapped → ERROR-AND-STOP.** Verifies prior-`apply` evidence before any write (Step 1); absence is a 🔴 terminal stop to `apply`. `plan` refreshes the file if absent (Step 2); `update` regenerates nothing.
- **Diff-first; announce-then-write; the plan file is the source of truth.** Every live target's diff is shown before writing — never a silent clobber; a byte-identical target is untouched (`SPEC.md` §1).
- **Tool-owned PATCH vs human-owned PROPOSE.** `driver.json`/`feeder.json`, labels, protection, CI are PATCHed through `apply`'s writers. Filled `.project/` docs are PROPOSED, never silently rewritten (`project-docs/SPEC.md` §4.3).
- **Reuses `apply`'s (#13's) provisioning units by reference — no second definition.** Configs via `write-driver-config.*`/`write-feeder-config.*` (#8/#5), docs via `write-project-docs.*` (#7), labels/branches/CI/protection via `provision-labels.*`/`provision-branches.*`/`emit-ci-workflow.*`/`provision-protection.*` (#6/#10/#11/#12). `update` adds only reconcile/diff/propose/flag logic (`SPEC.md` §7).
- **Cross-platform invocation correctness.** Bash/PowerShell twins are behaviorally equivalent, not byte-identical in CLI (Step 4).
- **Non-destructive by construction.** Never delete a branch, config key, doc/anchor, or label; never overwrite a human doc; never remove a live-only target — flagged 🔴 instead (Step 5). Re-asserting protection is the one allowed re-assertion (merge-UP).
- **Idempotent — a fully-synced repo is a TRUE NO-OP.** Nothing drifted/new/differing/live-only → zero writes and a no-op line; a re-run is a no-op by construction (`SPEC.md` §4.4).
- **Three distinct states, never collapsed** — `captured` reconciles; `none` is a reported no-op; `[TBD]` 🔴 is re-surfaced and left unwritten, never fabricated (`SPEC.md` §4.3).
- **Cannot collapse an existing `feeder.json` back to `{}`.** The feeder writer never emits `{}` or deletes an existing file (issue #77) — resetting the last non-default key leaves it byte-unchanged, not emptied (`references/config-union-write.md`).
- **The `gh` precondition is surfaced, never silent.** Local reconcile runs regardless; remote reconcile (labels, branches, CI, protection — the last needing repo-admin) is 🔴 blocked-on-precondition when `gh` auth/scope is missing (`BRIEF.md:82`).
- **No flags. Authors no application code, opens no PRs.** The reconcile verb of the plan/apply/update trio — nothing to argument-parse (`BRIEF.md:64`).
