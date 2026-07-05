---
name: update
description: This skill should be used when the user invokes "/milestone-bootstrapper:update", or asks to "reconcile my refreshed plan", "my project changed — sync the bootstrap", "we adopted Redis / switched the ORM — update the docs and config", or "re-apply the plan onto the already-bootstrapped repo". Reconciles a refreshed provisioning plan onto a repo that `apply` already bootstrapped — diff-first and non-destructive. The human re-runs `plan` to refresh the plan file (this skill runs `plan` first if there isn't one), then `update` diffs the refreshed plan against the live `.project/` docs and `.milestone-config/` configs: it PATCHes drifted tool-owned configs to match (showing the diff first), ADDs what's new (a newly-adopted framework's `conventions.md` section + the driver's `domainSkills` entry), PROPOSES — never overwrites — edits to human-owned project docs, and FLAGS for your decision — never deletes — anything present live but absent from the refreshed plan. A fully-synced repo is a true no-op. Never destructive. No flags. Authors no code; opens no PRs.
---

# update — reconcile a refreshed plan onto an already-bootstrapped repo (diff-first, propose human-owned, non-destructive)

Refresh the provisioning plan file `plan` wrote for this project (by the same deterministic slug), then **reconcile that refreshed plan onto the live repo**: diff each entry's refreshed captured value against the live state, **PATCH** the tool-owned configs that drifted (showing the diff before writing), **ADD** the units new since the last `apply` (a newly-adopted framework's `conventions.md` section, its `driver.json#domainSkills` entry, a new label), **PROPOSE — never overwrite** — edits to human-owned `.project/` docs, **FLAG 🔴 for the human's decision — never delete** — any target present live but absent from the refreshed plan, and re-assert protection / CI non-destructively. This is the bootstrapper's reconcile verb: where `apply` *deploys* the plan onto a fresh repo (`skills/apply/SKILL.md`), `update` *re-deploys* a refreshed plan onto one that already exists. The **architecture-changed path is first-class** — "we adopted Redis", "switched the ORM", "the layering changed" — the human re-runs `plan` to capture the new understanding, then `update` reconciles the delta onto the live docs and configs.

`update` is **diff-first and non-destructive.** The **plan file is the source of truth** (`SPEC.md` §1): a live target is patched only when it differs from the refreshed plan, and the diff is shown before any write — never a silent clobber. It is **idempotent by construction** — a fully-synced repo (nothing drifted, nothing new, nothing live-only) is a **true no-op plan** (every entry `no-op`, `SPEC.md` §4.4) and `update` writes nothing and says so. It **NEVER deletes** — no branch, no config key, no doc, no label; **NEVER overwrites a human-edited doc** (project docs are human-owned — propose, never rewrite — `project-docs/SPEC.md` §4.3); and **NEVER removes a live-only target** — a doc/config/label/branch present live but absent from the refreshed plan is **flagged 🔴 for the human, never removed** (park, don't guess; mirrors the feeder update's flag-don't-close stance, `milestone-feeder/skills/update/SKILL.md:141`). Re-asserting branch protection to match the plan is the **only** re-assertion allowed (idempotent merge-UP, `scripts/provision-protection.sh` header).

`update` reconciles onto an **already-bootstrapped** repo and is the **inverse of `apply`'s first-deploy branch**: a repo with **no evidence of a prior `apply`** (no `.project/` and no `.milestone-config/`) is a 🔴 error-and-stop directing the user to run `apply` first — exactly parallel to the feeder update's milestone-not-found ERROR-AND-STOP (`milestone-feeder/skills/update/SKILL.md:122`). It **reuses `apply`'s (#13's) provisioning units by reference — no second definition**: the tool-owned configs go through `apply`'s direct-write writers (`scripts/write-driver-config.*`, `scripts/write-feeder-config.*`), the new project-docs sections through the project-docs writer (`scripts/write-project-docs.*`), and the suite-readiness entries (labels / branch model / CI / protection) through the same idempotent provisioning scripts (`scripts/provision-labels.*`, `scripts/provision-branches.*`, `scripts/emit-ci-workflow.*`, `scripts/provision-protection.*`). The only logic `update` adds beyond `apply` is the **reconcile / diff / propose / flag** step. **No flags** — `update` *is* the reconcile verb of the plan/apply/update trio; there is nothing to argument-parse (`BRIEF.md:64`: "Verbs `plan` / `apply` / `update`, no flags"). It authors no application code and opens no PRs.

## Announce first

Say this to the user before doing any work — pick the line that matches the resolution outcome:

> **Bootstrapped repo + plan file found:** Standing by while I reconcile your refreshed plan onto the repo. I'll diff the refreshed plan against your live `.project/` docs and `.milestone-config/` configs — then **patch** the tool-owned configs that drifted (showing you the diff first), **add** anything new (a newly-adopted framework's `conventions.md` section and its `domainSkills` entry), **propose — never overwrite** — edits to your human-owned project docs, and **flag for your decision — never delete** — anything present in your repo but absent from the refreshed plan. I re-assert protection and CI non-destructively. If your repo already matches the plan, this is a **true no-op** — I'll say so and write nothing.

> **No plan file yet:** I don't have a refreshed provisioning plan to reconcile. I'll run `/milestone-bootstrapper:plan` first — it interviews you, detects the stack, inspects the live repo, and writes a refreshed plan file — then I'll reconcile that refreshed plan onto your repo.

> **Repo not yet bootstrapped:** 🔴 This repo shows no evidence of a prior `apply` — there's no `.project/` and no `.milestone-config/` to reconcile against. `update` re-deploys a refreshed plan onto an **already-bootstrapped** repo; it doesn't do the first deploy. Run `/milestone-bootstrapper:apply` first, then re-run `update` when your plan changes.

## Procedure

### Step 0 — Read the bootstrapper context + check the `gh` precondition

**Resolve the project-docs path.** Read `.milestone-config/feeder.json#projectDocs` when present, else default `.project/` (`SPEC.md` §4.1). The refreshed plan file also records this once as its `Project-docs path` field (Step 2); the two MUST agree — use the plan file's recorded value as authoritative (resolved at plan time so `apply` / `update` write to the same place, `SPEC.md` §4.1). This same path is the project-docs side of the bootstrapped-repo check (Step 1).

**`appRoots` comes from the refreshed plan file — `update` re-derives nothing from it.** The refreshed plan's `App-roots` field (`SPEC.md` §4.1, default `["."]`) already shaped its §A union and baked its §B globs at plan time (`plan` did the per-root detection and prefixing when it refreshed the file). `update` **reads** `appRoots` from that plan file (AC2) but does **not** re-detect per root, re-bake any glob, or write an `appRoots` key — the §B `sourceGlobs` / `uiSurfaceGlobs` it reconciles are already **root-absolute** strings, reconciled verbatim through the union write (Step 4 (2)). `.project/` and `.milestone-config/` stay at the **project root** regardless of `appRoots`. If a refreshed plan changes `appRoots` (apps moved / a root was added), that surfaces as ordinary **glob drift** in the §B Configs diff — `update` shows the live→plan glob diff and patches it like any other config change; there is no separate `appRoots` reconcile path because there is no `appRoots` key to reconcile.

**Check the `gh` precondition up front — surface it, never let it fail silently** (`BRIEF.md:82`). The remote reconcile (labels, branches, CI registration, protection) needs `gh` authenticated, and **branch protection needs repo-admin scope**. Probe `gh` auth read-only:

```bash
# bash — read-only precondition probe; captures status without changing anything.
gh auth status >/dev/null 2>&1 && gh_ok=1 || gh_ok=0
```

```powershell
# PowerShell 7+ — same read-only probe.
gh auth status *> $null; $ghOk = $LASTEXITCODE -eq 0
```

| `gh` state | What `update` does |
|---|---|
| Authenticated with sufficient scope | Reconcile every section normally. |
| Absent / not authenticated / insufficient scope | The **local** reconcile (project-doc proposals, config patches) still runs — it touches no remote. The **remote** reconcile (labels, branch model, CI registration, branch protection) is **🔴 blocked-on-precondition**: surface a clear message naming what to grant (`gh auth login`; repo-admin for protection) and do **not** attempt those writes. A blocked step is **reported 🔴, never silently skipped** (`BRIEF.md:82`; the component scripts also self-check and exit non-zero with a named precondition before touching anything). |

The precondition gates only the *remote-dependent* entries' deployability — it never blocks the project-docs proposals or the local config patches.

### Step 1 — Verify the repo is already bootstrapped (the inverse of `apply`'s first-deploy branch)

`update` reconciles onto a repo `apply` already bootstrapped. Before resolving the plan, confirm prior-`apply` evidence exists. Read-only check for **both**: the project-docs directory (Step 0's resolved `<projectDocs>`, default `.project/`) **and** the config directory (`.milestone-config/`).

```bash
# bash — bootstrapped iff the project-docs dir OR the config dir exists with content.
docs="<projectDocs>"; cfg=".milestone-config"
[ -d "$docs" ] && [ -n "$(ls -A "$docs" 2>/dev/null)" ] && have_docs=1 || have_docs=0
[ -d "$cfg" ]  && [ -n "$(ls -A "$cfg"  2>/dev/null)" ] && have_cfg=1  || have_cfg=0
```

```powershell
# PowerShell 7+ — same read-only check.
$docs = "<projectDocs>"; $cfg = ".milestone-config"
$haveDocs = (Test-Path -LiteralPath $docs) -and ((Get-ChildItem -LiteralPath $docs -Force -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)
$haveCfg  = (Test-Path -LiteralPath $cfg)  -and ((Get-ChildItem -LiteralPath $cfg  -Force -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)
```

| Evidence | Action |
|---|---|
| **Neither `<projectDocs>/` nor `.milestone-config/` present** | 🔴 **ERROR-AND-STOP — perform no writes.** Print: `🔴 update: this repo shows no evidence of a prior apply (no <projectDocs>/ and no .milestone-config/) — update reconciles onto an ALREADY-bootstrapped repo and never does the first deploy. Run /milestone-bootstrapper:apply first.` This is the terminal inverse of `apply`'s first-deploy branch (issue AC-5; mirrors the feeder update's milestone-not-found ERROR-AND-STOP, `milestone-feeder/skills/update/SKILL.md:122`). **End the run.** |
| **At least one present** | Bootstrapped — proceed to Step 2. (A repo with one but not the other is a partial bootstrap; `update` reconciles what exists and the refreshed plan's `add`-class entries fill the gap — never an error.) |

### Step 2 — Resolve / refresh the plan file for the project

Derive `<slug>` **deterministically** from the one-line project goal, using the **same algorithm `plan` / `apply` use** (`skills/plan/SKILL.md` Step 5; `skills/apply/SKILL.md` Step 1; `SPEC.md` §2.2): lowercase the goal, replace every run of non-alphanumeric characters with a single hyphen, strip leading/trailing hyphens, cap the length per `SPEC.md` §2.2 step 5 (trim a trailing hyphen if the cut lands on one). The same goal always resolves to the same path:

```
.milestone-bootstrapper/plan-<slug>.md
```

Resolve the refreshed plan file at that path:

| Resolution | Action |
|---|---|
| **Found** | Read it; reconcile **exactly it** (Step 3) against the live repo. Proceed to Step 3. |
| **Absent** | **Run `plan` first** against the project — the full interview + detection + inspection, which **writes** the refreshed plan file at this same path (`skills/plan/SKILL.md` Step 5). Then read the freshly-written plan file and reconcile it (Step 3). This is the two-step trigger: `update` does not re-interview by itself; it delegates the refresh to `plan`, then reconciles. (Distinct from `apply`, which **stops** on an absent plan — `apply` is a first-deploy and a missing plan there means nothing was ever planned; `update` reconciles a *refreshed* plan, so refreshing it via `plan` is exactly the intended flow.) |

**Staleness (a changed goal earns a fresh plan).** The slug is a function of the project goal, so a **changed** goal derives a **different** slug → no match at the path above → the **Absent** row fires and `update` re-plans, then reconciles the fresh file (`SPEC.md` §3, Stale brief). A matching slug means the recorded plan is the one to reconcile. **Resolve by slug, not by a deploy receipt** — the bootstrapper has no deploy-receipt analog (its targets are repo-local names — `.project/` docs, config keys, label/branch names — addressed by name, `SPEC.md` §3). Resolve-by-receipt-then-title is a feeder concept; here identity is the slug.

### Step 3 — Read the plan-file contract (the fields `update` reconciles)

The refreshed plan file is the **load-bearing build artifact** — `update` reads it and reconciles the live repo against it, regenerating nothing (`SPEC.md` §1). Parse the fields by name (the format is `skills/plan/SKILL.md` Step 5 / `SPEC.md` §8; the field requirements are `SPEC.md` §4). A required field that is absent or unparseable is a **malformed plan** — error-and-stop with the missing field named, never reconcile a partial spec (`SPEC.md` §3). This is the **same plan-file contract `apply` parses** (`skills/apply/SKILL.md` Step 2) — `update` reads the same fields and additionally keys on each entry's **Reconcile class** (§4.4), which is the field `update` is built around.

| Plan-file field | What `update` reads it for |
|---|---|
| **Slug** (`SPEC.md` §4.1) | The plan's identity — Step 2 resolved the file by it. |
| **Status** (`READY` \| `FLAGGED`, `SPEC.md` §4.1, §4.3) | A consumer surfaces this; `update` may proceed but **re-surfaces every 🔴 `[TBD]` entry to the human first**. |
| **Project-docs path** (`SPEC.md` §4.1) | Where §A docs live (Step 0 — the two MUST agree). |
| **App-roots** (`appRoots`, `SPEC.md` §4.1) | Read from the refreshed plan (AC2) — context only. It already shaped the §A union and baked the §B globs at plan time; `update` re-derives nothing, writes no `appRoots` key, and reconciles the already-root-absolute §B globs verbatim. A changed `appRoots` surfaces as ordinary §B glob drift (Step 0). |
| **§A. Project docs** — one row per doc: Doc · State · Reconcile · Captured understanding (`SPEC.md` §4.2, §5) | The doc entries — reconciled at Step 4 (1). Project docs default to reconcile class **`human-owned`** → propose, never overwrite. |
| **§B. Configs** — `driver.json#…` / `feeder.json#…` non-default keys: Key · State · Reconcile · Value (`SPEC.md` §4.2, §6.1) | The tool-owned config values — reconciled at Step 4 (2). Reconcile class `add` (key absent) / `patch` (value changed) — never `human-owned`. |
| **§B. Labels** — one row per label: Label · State · Reconcile (`SPEC.md` §6.3) | The label taxonomy — reconciled at Step 4 (3). `add` create-if-missing. |
| **§B. Branch model · protection · CI** — Target · State · Reconcile · Value (`SPEC.md` §6.3) | The branch names, the protection rule, the CI commands — reconciled at Step 4 (4)→(5)→(6). |

**Read every entry's State and honor it, never collapsed** (`SPEC.md` §4.3): `captured` is a recorded decision (reconcile it); `none` is a recorded "not applicable" (a no-op for that entry, reported — never a fabricated default); `[TBD]` 🔴 is a flagged genuine unknown (re-surface to the human; leave the doc placeholder via `--state tbd` / leave the config key unwritten — never fabricate). `update` re-derives none of these — it reads the recorded values and reconciles them.

### Step 4 — Reconcile (per entry, by reconcile class — diff-first, propose human-owned, flag live-only)

This is `update`'s **defining step**. For **every** §A / §B entry, key on its **Reconcile class** (`SPEC.md` §4.4) and apply the matching branch below, **announce-then-write each action**. The reconcile is **diff-first** — for any target that exists live, compute the live→plan diff and **show it before writing** (changed hunks only); a byte-identical target is left untouched (this feeds the no-op). Reuse `apply`'s provisioning units by reference for the writes — `update` adds only the diff / propose / flag logic.

> **Cross-platform invocation note (read each script's CLI surface, don't assume).** Every component ships as cross-platform twins — invoke the `.sh` on bash, the `.ps1` on PowerShell 7+. The twins do the same work but **their CLI surfaces differ by language convention**: the bash scripts parse `--flag` long options (and `--dry-run`), while the PowerShell scripts expose **PascalCase `param()` parameters** — `-Repo`, `-IntegrationBranch`, `-ProtectedBranch`, `-SourceGlobs`, `-DomainSkills`, `-Template`, `-Map`, `-Anchor`, `-State`, `-Content`, and `-DryRun` as a `[switch]`. They are **behaviorally equivalent, NOT byte-identical in CLI** — passing a bash-style `--flag` token to a `.ps1` leaves its `param()` unbound and the script fails its required-key guard. Each invocation below gives both spellings; match the `param()` block exactly. Resolve `<projectDocs>` and `<repo>` from Step 0.

#### The four reconcile classes (per `SPEC.md` §4.4)

| Reconcile class | `update` behavior |
|---|---|
| `add` | The target is new since the last `apply` (a newly-adopted framework's `conventions.md` section, its `domainSkills` entry, a new label). **Create it** through the owning component (a fresh write is non-destructive — there is nothing live to clobber). |
| `patch` | The target exists live and the captured value **changed**. For a **tool-owned** target: **show the live→plan diff, then PATCH** through the writer. For a **human-owned** target: see the `human-owned` row — a drifted human doc is **proposed, never patched in place**. |
| `human-owned` | A human-editable project doc. **PROPOSE the change** (print the proposed edit / diff); **never overwrite** the live doc. The change is applied **only on the human's acceptance** (`project-docs/SPEC.md` §4.3; mirrors the suite's propose-don't-rewrite stance). |
| `no-op` | The target already matches the captured value. **Do nothing**, report it as a no-op. |

#### The tool-owned vs human-owned split (governs PATCH vs PROPOSE)

The two rules are not in tension — **configs are mechanics the tool owns; project docs are intent the human owns** (`project-docs/SPEC.md` §1 ownership table; issue Design):

- **Tool-owned → PATCH to match the plan.** `.milestone-config/driver.json` / `feeder.json`, labels, branch protection, the CI workflow — the tool owns these. A drifted tool-owned target is shown as a diff, then patched through `apply`'s writer / provisioning script. For the two config writers specifically, "patch" is achieved by a **union whole-file rewrite** (Step 4 (2)): the writers rebuild the entire file from the keys passed, so `update` passes the live set merged with the plan's changes — the result patches the drifted keys while preserving every other live key. A re-asserted value that already matches is a true no-op (the writers are idempotent — a byte-identical assembled object leaves the file untouched, `scripts/write-feeder-config.sh` Behavior).
- **Human-owned → PROPOSE, never overwrite.** A filled `.project/` doc (not `[TBD]`) is human-owned — `update` emits a **proposed** edit for the human to accept and **does not silently rewrite it** (`project-docs/SPEC.md` §4.3; issue AC). Exception: a doc anchor still at its `[TBD]` placeholder is *not* yet human-owned content, so writing the refreshed captured value there is an `add` (filling a placeholder, not overwriting human content — `project-docs/SPEC.md` §4.2 `[TBD]`-means-absent).

#### Step 4 (1) — Project docs (§A) — PROPOSE drift, ADD new sections (reuses #7)

For each §A row, reconcile its doc against the live `<projectDocs>/<doc>`:

- **`no-op`** (live anchor content matches the captured understanding) → do nothing, report no-op.
- **`add`** (the anchor is absent or still `[TBD]` — e.g. a newly-adopted framework's new `conventions.md` section) → **write the captured content** under the named anchor through the project-docs writer (filling a placeholder is non-destructive):

```bash
# bash — write one anchor's captured content (the ADD branch: anchor empty/[TBD]).
./scripts/write-project-docs.sh --template "<projectDocs>/<doc>" --anchor "<## anchor>" --state captured --content "<captured text>"
```

```powershell
# PowerShell 7+ — behaviorally-equivalent twin (PascalCase -Flag params).
./scripts/write-project-docs.ps1 -Template "<projectDocs>/<doc>" -Anchor "<## anchor>" -State captured -Content "<captured text>"
```

- **`human-owned`** (the anchor holds human-filled content that **differs** from the refreshed plan) → **PROPOSE, do NOT write.** Print the proposed edit as a live→plan diff (changed hunks only) under the doc + anchor, marked 🔴 *proposed — accept to apply; `update` will not overwrite your doc.* Apply it through the writer **only after** the human accepts. The writer is append-under-anchor and idempotent — but `update` does not call it for a drifted human doc until acceptance.
- **`none`** (the doc/anchor is recorded not-applicable — e.g. `design-system.md` for a backend-only repo) → reported no-op; never fabricated, never deleted.
- **`[TBD]` 🔴** → re-surface to the human; pass `--state tbd` / `-State tbd` if (re)writing the anchor so the writer leaves the `[TBD]` placeholder. Never fabricate content.

The writer routes each captured answer to its doc + anchor by the **fixed field→doc→anchor map** (`docs/understanding-interview.md` §2; `docs/write-project-docs.md` "Field → doc → anchor routing (FIXED)") — `update` keys by anchor exactly as `apply` does; it does not re-derive the map.

#### Step 4 (2) — Configs (§B) — PATCH drift, ADD new keys, PRESERVE live-only by writing the UNION (reuses #5 and #8)

The tool-owned config slices. The two config writers are **whole-file rewriters, not patchers**: each builds the config object from `{}` using **only** the keys you pass on the CLI, then atomically replaces the entire file — it reads the existing file's bytes **only** for the byte-equality no-op check, never to merge in the existing keys (`scripts/write-driver-config.sh` Behavior: "the config object is rebuilt from the recorded entries each run"; the `.ps1` twins build `$obj = [ordered]@{}` from the params alone). Two consequences drive how `update` must orchestrate them — get either wrong and `update` silently deletes live config:

1. **They have NO `--dry-run` / `-DryRun`** (unlike `provision-branches.*` / `provision-protection.*`). They are **write-only primitives** — they cannot preview. So `update` must compute the diff **itself, out-of-band**, before it calls the writer. Do **not** claim the writer previews the change; it does not.
2. **A key you do not pass is DROPPED from the rewritten file.** Passing "only the changed keys" would rebuild `driver.json` from just those keys and **delete every other live key** — directly violating Step 5's live-only guarantee. The writer preserves a key **only because `update` passes it back in.** One feeder-slice nuance follows from issue #77: on an all-default assembled object (`{}`), the feeder writer writes **nothing** and is **non-destructive** — it never deletes an existing file. So a repo with **no** `feeder.json` stays absent (the #77 first-run-`setup` case), while an **existing** `feeder.json` is left **byte-unchanged** — not emptied to `{}`, not deleted. A consequence for `update`: because the writer will neither emit `{}` nor delete, `update` **cannot** use this writer to collapse an existing `feeder.json` back to `{}` — resetting the last non-default feeder key to its default leaves the prior file in place. That is a deliberate, out-of-scope consequence of the #77 non-destructive contract, not a regression this skill works around. None of this changes `update`'s union discipline (still pass live ∪ plan-changes).

So `update` drives these writers **non-destructively by passing the UNION of keys** — every live key plus every plan change — so the whole-file rewrite reproduces everything and drops nothing:

1. **Read the live config first.** Read `.milestone-config/driver.json` (and `feeder.json`) and capture **all** current keys and values — this is the live set the rewrite must reproduce.
2. **Compute and SHOW the live→plan diff before writing.** `update` diffs the live file against the **assembled target object** (the union from step 3) and prints the changed hunks (a `git diff`-style unified hunk of the JSON, changed keys only). The writers cannot do this — `update` computes it out-of-band. Show this diff **before** the write; a target with no changed keys is left untouched (this feeds the no-op).
3. **Invoke the writer with the UNION of keys** so the whole-file rewrite preserves everything. For each live key: pass its **plan value** if the plan changes it (`patch`), else its **live value** unchanged. Then pass each **plan addition** (`add`) the live file lacks. The rebuilt file = **live ∪ plan-changes** — every live key survives because it was passed back in; changed keys take the plan's value; new keys are added. Nothing is dropped.

The writers stay idempotent under this discipline: when the assembled union equals the live file, the writer sees a byte-identical object and leaves the file untouched — a **true no-op** for a fully-synced config (so a fully-synced repo writes nothing here). Write through `apply`'s direct-write writers — **never** the interactive `setup` interviews (`scripts/write-driver-config.sh` header: invoking `setup` would re-interview the user mid-run):

```bash
# bash — feeder.json slice (#5). Pass the UNION: every live key (live value if the
# plan doesn't change it, plan value if it does) PLUS plan additions — so the
# whole-file rewrite reproduces every live key and drops none.
./scripts/write-feeder-config.sh --repo "<repo>" [--project-docs "<path>"] [--reviewer "<val>"]

# bash — driver.json slice (#8). Same UNION rule. The three Core keys are always
# written; every OTHER live key is passed back with its live value unless the plan
# changes it; plan additions are added. An optional NEVER carried live and never
# added by the plan stays omitted (never written as null).
./scripts/write-driver-config.sh --repo "<repo>" \
  --integration-branch "<integration>" --protected-branch "<protected>" \
  --source-globs '<json string[]>' \
  [--domain-skills '<json string[]>'] [--non-negotiables '<json string[]>'] [--versioning false] [--ui-surface-globs '<json>'] \
  [--stack '<enum>'] [--stack-version-file '<path>'] \
  [--unit-test-cmd "<cmd>"] [--preflight-cmd "<cmd>"] [--e2e-env '<json>']
```

```powershell
# PowerShell 7+ — behaviorally-equivalent twins (PascalCase -Flag params). Same UNION rule.
./scripts/write-feeder-config.ps1 -Repo "<repo>" [-ProjectDocs "<path>"] [-Reviewer "<val>"]
./scripts/write-driver-config.ps1 -Repo "<repo>" -IntegrationBranch "<integration>" -ProtectedBranch "<protected>" -SourceGlobs '<json string[]>' [-DomainSkills '<json>'] [-NonNegotiables '<json>'] [-Versioning false] [-UiSurfaceGlobs '<json>'] [-Stack '<enum>'] [-StackVersionFile '<path>'] [-UnitTestCmd "<cmd>"] [-PreflightCmd "<cmd>"] [-E2eEnv '<json>']
```

- **`domainSkills` empty / `none`** → omit `--domain-skills` / `-DomainSkills` **only when no live `domainSkills` exists**; the key stays absent (never written as `[]`) — a recorded "none", never a fabricated skill (`SPEC.md` §4.3). If `domainSkills` **is** live and the plan merely doesn't change it, pass the **live value** back (the union rule) so it survives the rewrite.
- **`nonNegotiables`** → same UNION rule as `domainSkills`. Pass `--non-negotiables` / `-NonNegotiables` with the **plan value** when the plan changes it, else the **live value** carried back so the whole-file rewrite preserves it; omit **only when neither the plan nor the live config carries it** (never written as `[]` — a recorded "none", never fabricated). A live-only `nonNegotiables` the plan no longer carries is the live-only case — flagged 🔴 for the human AND passed through in the union write so the rewrite preserves it.
- **`versioning`** → pass `--versioning false` / `-Versioning false` when the plan records `versioning: false` **or** the live config already has `versioning: false` and the plan doesn't change it (union); omit only when neither carries it.
- **`stack` / `stackVersionFile`** → same UNION rule as `domainSkills`. Pass `--stack` / `-Stack` and `--stack-version-file` / `-StackVersionFile` with the **plan value** when the plan changes them, else the **live value** carried back so the whole-file rewrite preserves them; omit a key **only when neither the plan nor the live config carries it** (an absent key stays absent — never written as empty; the version-file is a PATH, never a resolved version). A live-only `stack`/`stackVersionFile` the plan no longer carries is the live-only case — flagged 🔴 for the human AND passed through in the union write so the rewrite preserves it.
- **The union write is what makes these writers non-destructive.** Because each writer rebuilds the whole file from the keys passed, `update` must pass every live key back in — a key the plan no longer carries is the **live-only** case (Step 5): it is **flagged 🔴 for the human AND passed through in the union write** so the rewrite preserves it. It is **never stripped** — the writer drops it only if `update` fails to pass it, which `update` never does.

#### Step 4 (3) — Labels (§B) — ADD missing (reuses #6)

Reconcile the label taxonomy idempotently — the `--force` upsert creates a missing label and corrects a drifted color/description, never duplicating on re-run (`scripts/provision-labels.sh` header). The script takes **no flags** (both twins):

```bash
# bash
./scripts/provision-labels.sh
```

```powershell
# PowerShell 7+ (no params).
./scripts/provision-labels.ps1
```

**Remote step** — 🔴 blocked-on-precondition when Step 0 flagged `gh`. A `none`-state label row is a reported no-op. A label present live but absent from the refreshed plan is the **live-only** case below — flagged, never deleted.

#### Step 4 (4) — Branch model (§B) — ADD missing, never delete (reuses #10)

Reconcile the integration + protected branches (create-if-missing) and the default-branch policy. The script **never deletes, force-pushes, or resets** (`scripts/provision-branches.sh` header) — a re-run on an already-correct repo changes nothing:

```bash
# bash
./scripts/provision-branches.sh --repo "<repo>"
```

```powershell
# PowerShell 7+ (PascalCase -Flag param; -DryRun is a [switch]).
./scripts/provision-branches.ps1 -Repo "<repo>"
```

**Remote step** — 🔴 blocked-on-precondition when Step 0 flagged `gh`.

#### Step 4 (5) — CI workflow (BEFORE protection) — ADD / PATCH non-destructively (reuses #11)

Re-assert `.github/workflows/ci.yml` running the recorded test/preflight commands on PRs into the integration branch. **CI is reconciled strictly before protection** — protection registers the CI job names (`unit-tests` / `preflight`) as the required status-check contexts, and those contexts must already exist (`BRIEF.md:90`; `scripts/emit-ci-workflow.sh` CONTEXT-NAME STABILITY CONTRACT). The emitter is idempotent and **non-destructive on divergence**: an absent file is created, a byte-identical file is a no-op, a file that **differs** is **not clobbered** (exit 3 — human edits preserved). On exit 3, `update` **shows the live→plan diff and flags it 🔴** rather than overwriting — reconciling a diverged CI file the human edited is exactly the propose-don't-clobber stance:

```bash
# bash
./scripts/emit-ci-workflow.sh --repo "<repo>"
```

```powershell
# PowerShell 7+ (PascalCase -Flag param).
./scripts/emit-ci-workflow.ps1 -Repo "<repo>"
```

**Remote step** — 🔴 blocked-on-precondition when Step 0 flagged `gh`.

#### Step 4 (6) — Branch protection (AFTER CI) — re-assert non-destructively (reuses #12)

Re-assert the protected branch's server-side safety floor. This is the **only re-assertion `update` performs**, and it is **non-destructive by construction**: the script GETs existing protection first and keeps the **stronger** value per field (**merge-UP**), so re-asserting is a safe idempotent no-op and a stronger-than-floor setting is preserved, never reconciled down (`scripts/provision-protection.sh` header; `BRIEF.md:65`: re-asserting protection to match the plan is the one allowed re-assertion):

```bash
# bash
./scripts/provision-protection.sh --repo "<repo>"
```

```powershell
# PowerShell 7+ (PascalCase -Flag params; -DryRun is a [switch]).
./scripts/provision-protection.ps1 -Repo "<repo>"
```

**Remote step needing repo-admin** — 🔴 blocked-on-precondition when Step 0 flagged `gh` or the token lacks repo-admin.

### Step 5 — The live-only case (present live, absent from the refreshed plan) — FLAG 🔴, NEVER delete

A target present **LIVE** but **absent from the refreshed plan** — a doc anchor, a config key, a label, or a branch the live repo has but the refreshed plan does not carry — is **flagged 🔴 for the human's decision and NEVER removed, deleted, or stripped** (issue AC — non-destructive guarantee; `BRIEF.md:65`; park-don't-guess, the direct analog of the feeder update's flag-the-extra-live-issue-don't-close stance, `milestone-feeder/skills/update/SKILL.md:141`). `update` removes nothing for these — it reports each in the summary, marked 🔴 *present in your repo, absent from the refreshed plan — flagged for your decision; `update` will not remove it. Removing it is your call.* For a **doc / label / branch**, "never remove" means `update` performs no write at all. For a **config key**, "never remove" is active, not passive: because the two config writers rebuild the whole file (Step 4 (2)), `update` must **pass the live-only key back in the union write** so the rewrite preserves it — skipping it would let the rewrite drop it. The key is flagged for the human **and** carried through; it is never stripped.

How `update` detects the live-only set, per target type (read-only, no write):

| Live-only target | Detection (read-only) | Why flagged, never deleted |
|---|---|---|
| **A `.project/` doc / anchor** present live, absent from §A | Live anchor has human content; no §A row carries it. | Human-owned intent — removing it is the human's call. |
| **A `driver.json` / `feeder.json` key** present live, absent from §B Configs | Live config has the key; no §B Configs row carries it. | Stripping a config key the human may rely on is destructive — flag it **and pass it back in the union write** (Step 4 (2)) so the whole-file rewrite preserves it. |
| **A label** present live, absent from §B Labels | `gh label list` shows it; no §B Labels row carries it. | Deleting a label could orphan issues — never auto-delete. |
| **A branch** present live, absent from §B Branch model | `git`/`gh` shows the branch; no branch entry carries it. | `update` never deletes a branch (`BRIEF.md:65`). |

> **Worked example — live-only flag, preserved through the union write (the triage Advisory's un-exercised path, made first-class).**
> The team **dropped a stack** between bootstraps: the last `apply` wired `driver.json#domainSkills = ["fastapi-skills", "pytest-skills"]` and a live `.project/conventions.md#Test patterns` section describing pytest fixtures. The refreshed plan (after re-running `plan`) reflects a migration **off** pytest — its §B Configs now records `domainSkills = ["fastapi-skills"]` and its §A `conventions.md` no longer carries the pytest test-patterns content. (Say the same run also patches another driver.json key — e.g. `versioning` — so the writer *does* run.)
> Because `write-driver-config` rewrites the whole file from the keys passed, `update` does **not** simply skip the key — that would let the rewrite drop it. Instead `update` keeps `pytest-skills` alive by **passing the live `domainSkills = ["fastapi-skills", "pytest-skills"]` value back in the union write** (alongside the patched `versioning`), so the rewritten file still carries it. It does **NOT** delete the live `conventions.md#Test patterns` section (project docs are propose-only, never rewritten). Then it reports:
> ```
> 🔴 Live-only (flagged for your decision — update preserved these in place, did not remove them):
>   - driver.json#domainSkills: "pytest-skills" present live, absent from the refreshed plan — passed back in the union write, so it survives; flagged for you to decide.
>   - .project/conventions.md#Test patterns: human-authored content present live, absent from the refreshed plan — not rewritten.
> These were in your repo but not in the refreshed plan. Remove them yourself if intended — update never deletes.
> ```
> The human decides whether the drop is real (then removes them by hand) or a plan omission (then re-runs `plan` to re-capture them). `update` parks the decision; the live-only key **survives the rewrite precisely because `update` passes it back in** — it is flagged for the human, never deleted, and never silently clobbered by the whole-file rewrite.

### Step 6 — Report (diff-list + flags + summary)

Write a concise reconcile report (table form):

- **PATCHED (tool-owned):** each config / CI / protection target whose drift was shown as a diff then applied — N patched.
- **ADDED:** each new section / key / label / branch created — M added.
- **PROPOSED (human-owned) 🔴:** each drifted `.project/` doc anchor, with its proposed live→plan diff — applied only on the human's acceptance. P proposed.
- **LIVE-ONLY (flagged) 🔴:** the Step 5 set — present live, absent from the plan; never removed. F flagged.
- **Blocked-on-precondition 🔴:** any remote step Step 0 gated on `gh` / repo-admin.
- **NO-OP:** when nothing drifted, nothing is new, no human-owned doc differs, and nothing is live-only → the single no-op line: `update: repo already matches the refreshed plan — nothing to reconcile (no-op)`. Re-running `update` immediately after a successful run is a no-op by construction (the writers are idempotent; the diffs are now empty).

## Output style

Be concise — report status and outcomes flatly, no wall-of-text. Present the precondition status, the bootstrapped-repo check, the per-class reconcile, the diffs, and the per-entry outcomes as **tables**, not inline prose. Show every PATCH/PROPOSE as a unified-style diff (changed hunks only) before any write. Mark anything needing a human with 🔴 — every re-surfaced `[TBD]`, every proposed human-owned-doc edit, every live-only flag, and every blocked-on-precondition step. (Mirrors the suite's shared output style — `BRIEF.md:80`; `skills/apply/SKILL.md` Output style; the feeder update's output style, `milestone-feeder/skills/update/SKILL.md:180`.)

## Non-negotiables

- **Reconciles a refreshed plan onto an ALREADY-bootstrapped repo — not-bootstrapped → ERROR-AND-STOP.** `update` verifies prior-`apply` evidence (a populated `<projectDocs>/` or `.milestone-config/`) before any write; their absence is a 🔴 terminal stop directing the user to `apply` — the inverse of `apply`'s first-deploy branch (issue AC-5; mirrors the feeder update's milestone-not-found ERROR-AND-STOP, `milestone-feeder/skills/update/SKILL.md:122`). The human re-runs `plan` to refresh the plan file (Step 2 runs it if absent); `update` reconciles that file and regenerates nothing.
- **Diff-first; announce-then-write; the plan file is the source of truth.** For every target that exists live, `update` shows the live→plan diff (changed hunks only) **before** writing — never a silent clobber. A byte-identical target is left untouched (this feeds the no-op). To change a target, change the project / plan, not the live repo (`SPEC.md` §1; mirrors the feeder update's diff-then-patch, `milestone-feeder/skills/update/SKILL.md:139`).
- **Tool-owned PATCH vs human-owned PROPOSE.** Tool-owned artifacts (`driver.json`, `feeder.json`, labels, branch protection, CI workflow) are **PATCHed** to match the plan through `apply`'s writers / provisioning scripts. Human-owned `.project/` docs (filled, not `[TBD]`) are **PROPOSED, never silently rewritten** — applied only on the human's acceptance. Configs are mechanics the tool owns; project docs are intent the human owns (`project-docs/SPEC.md` §1, §4.3; `SPEC.md` §4.4).
- **Reuses `apply`'s (#13's) provisioning units by reference — no second definition.** The config patches go through `scripts/write-driver-config.*` / `write-feeder-config.*` (#8/#5), the new doc sections through `scripts/write-project-docs.*` (#7), and labels / branch model / CI / protection through `scripts/provision-labels.*` / `provision-branches.*` / `emit-ci-workflow.*` / `provision-protection.*` (#6/#10/#11/#12). The only logic `update` adds is the reconcile / diff / propose / flag step (issue Design; `SPEC.md` §7).
- **Cross-platform invocation correctness — match each `param()` block.** The bash twins parse `--flag` long options (and `--dry-run`); the PowerShell twins expose **PascalCase `param()` parameters** (`-Repo`, `-IntegrationBranch`, `-Template`, `-Map`, `-Anchor`, `-State`, `-Content`, `-DryRun` as a `[switch]`). The twins are **behaviorally equivalent, NOT byte-identical in CLI** — a bash `--flag` passed to a `.ps1` leaves its param unbound and the script fails its required-key guard. Each invocation gives both spellings; match the script's `param()` block exactly.
- **Non-destructive by construction — NEVER delete, NEVER overwrite a human doc, NEVER remove a live-only target.** No branch deleted, no config key stripped, no doc/anchor deleted, no human-edited doc clobbered. A target present live but absent from the refreshed plan is **flagged 🔴 for the human, never removed** (Step 5). Re-asserting branch protection to match the plan is the **only** re-assertion allowed — and it is itself non-destructive (merge-UP, `scripts/provision-protection.sh` header; `BRIEF.md:65`; mirrors the feeder update's flag-don't-close, `milestone-feeder/skills/update/SKILL.md:141`).
- **Idempotent — a fully-synced repo is a TRUE NO-OP.** Nothing drifted, nothing new, no human-owned doc differs, nothing live-only → zero writes and a stated no-op line. Re-running `update` immediately after a successful run is a no-op by construction (the writers are idempotent; the diffs are empty) — `SPEC.md` §4.4 (an all-`no-op` plan); mirrors the feeder update's no-op contract, `milestone-feeder/skills/update/SKILL.md:142` and its IDEMPOTENCY section.
- **Three distinct states, never collapsed** — `captured` reconciles; `none` is a reported no-op (omit the key / record the "None" answer / skip — never a fabricated default); `[TBD]` 🔴 is re-surfaced to the human and left unwritten/placeholder, never fabricated (`SPEC.md` §4.3).
- **The `gh` precondition is surfaced, never silent.** The local reconcile (doc proposals, config patches) runs regardless; the remote reconcile (labels, branch model, CI registration, branch protection — the last needing repo-admin) is 🔴 blocked-on-precondition when `gh` auth/scope is missing, reported before the attempt, never failed silently mid-run (`BRIEF.md:82`).
- **No flags. Authors no application code, opens no PRs.** `update` is the reconcile verb of the plan/apply/update trio — nothing to argument-parse (`BRIEF.md:64`). The writes it performs are the proposed/accepted project-doc edits, the `.milestone-config/*` config patches, and the non-destructive GitHub suite-readiness re-assertions — performed by the component scripts, never by a dispatched agent. `update` edits no application source file and opens no PR.
