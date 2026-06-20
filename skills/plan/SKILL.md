---
name: plan
description: This skill should be used when the user invokes "/milestone-bootstrapper:plan", or asks to "plan the bootstrap", "preview the project setup", or "turn this repo into a reviewable provisioning plan". Interviews the human about the project's understanding (goal, architecture, stack, conventions, environment, versioning), inspects the repo, detects the stack, and writes a single reviewable provisioning plan file describing everything it would record into the project docs and change in the repo's suite-readiness — and writes nothing remote. Read-only on the repo and on GitHub: its entire output is one local scratch plan file. No flags. Authors no code; opens no PRs.
---

# plan — interview + inspect + detect → reviewable provisioning plan file

Read the bootstrapper's own profile, check the `gh` precondition, run the understanding interview, detect the stack, inspect the repo (adopt-or-init), compose the answers + detected signals through the doc/config mapping, and write a single reviewable **provisioning plan file**. The bootstrapper's first verb: it previews everything `apply` would later write — and writes nothing else.

This skill is the preview step of the bootstrapper pipeline. It captures the project's durable understanding (Job 1 — the core) and the suite-readiness change set (Job 2 — supporting), and records both into one reviewable plan file in the **exact format `SPEC.md` defines** (the plan-file-as-interface). It **composes** the already-built components and performs **none of their writes itself**:

- the **understanding interview** (`docs/understanding-interview.md`, #4) — tier-by-tier capture of goal / architecture / stack / environment / mandated-packages / versioning, and the design system for UI projects;
- **stack detection** (`scripts/detect-stack.sh`, #3) — detect the stack → its best-practice convention note, framework/version pin, and `domainSkills` candidate;
- the **doc/config mapping** (`docs/write-project-docs.md`, #7) — compose detection + interview answers into the per-anchor doc-population entries and the non-default config keys.

The load-bearing invariant: **`plan` writes the plan file (local scratch) and NOTHING else** — no project-docs population, no `.milestone-config/*` write, no labels, no branches, no branch protection, no CI, no GitHub state of any kind ([BRIEF.md:22](../../BRIEF.md)). The plan file **records** the planned changes; `apply` / `update` (#13/#14) are the only verbs that execute them. Preview-by-default exists because these are consequential, long-lived decisions that deserve a human read before any write.

The plan-file format is owned by `SPEC.md`, not redefined here — `plan` emits the plan in that format and references it. The skill mirrors the sibling feeder `plan` skill's shape ([`milestone-feeder/skills/plan/SKILL.md:1-18`](../../../milestone-feeder/skills/plan/SKILL.md), `:258-262`): a frontmatter `name`/`description`, an "Announce first" line, a numbered "Procedure" of read-only-then-write-one-scratch-file steps, an output style, and a non-negotiables block — transposed to the bootstrapper's surface (settings + docs, not issues).

## Announce first

Say this to the user before doing any work:

> Standing by while I interview you about the project, detect the stack, inspect the repo, and turn it all into a reviewable provisioning plan. This is read-only — I'll write a single plan file to local scratch and change nothing in your repo, your settings, or on GitHub. Review the plan, then run `/milestone-bootstrapper:apply` to deploy it.

## Procedure

### Step 0 — Read the bootstrapper profile + check the `gh` precondition

**Read the existing config (best-effort, read-only).** Read `.milestone-config/driver.json` and `.milestone-config/feeder.json` if present — they are **not** required to exist (a fresh repo has neither). These reads serve two purposes: (a) seeding any already-set key as the interview's detected default, and (b) the adopt-or-init delta at Step 3. Reading them is a read; it writes nothing.

Resolve the **target project-docs path** — where the project docs are written — from `feeder.json#projectDocs` when set, else the default `.project/` (`SPEC.md` §4.1). This is the single resolution; record it once so the plan file's `Target project-docs path` field and every §A entry agree.

**Check the `gh` precondition up front — surface it, never let it fail silently** ([BRIEF.md:82](../../BRIEF.md); the same precondition discipline the suite holds). Probe `gh` auth/scope read-only:

```bash
# bash — read-only precondition probe; captures status without changing anything.
gh auth status >/dev/null 2>&1 && gh_ok=1 || gh_ok=0
```

```powershell
# PowerShell 7+ — same read-only probe.
gh auth status *> $null; $ghOk = $LASTEXITCODE -eq 0
```

| `gh` state | What `plan` does |
|---|---|
| Authenticated with sufficient scope | Proceed normally; the remote-dependent plan entries (branch protection, CI registration) are recorded as ordinary planned changes. |
| Absent / not authenticated / insufficient scope | **Surface a clear precondition message** — never a silent failure. `plan` writes nothing remote, so it **still emits the plan file**, but marks the remote-dependent entries (branch protection, CI registration) as **🔴 blocked-on-precondition** rather than aborting. It MUST NOT claim those steps will succeed. |

The precondition only gates the *remote-dependent* suite-readiness entries' deployability — it never blocks the interview, the detection, the project-docs population set, or the plan-file write. Branch protection needs repo-admin scope; record that requirement on the flagged entries so the human knows what to grant before `apply`.

### Step 1 — Run the understanding interview (#4)

Run the understanding interview exactly as `docs/understanding-interview.md` defines it — that engine owns the surface, the tier order, and the recording discipline; this step **invokes** it and consumes its output. Follow it tier-by-tier (`docs/understanding-interview.md` §1, Tier order):

| Tier | Captures | Target doc(s) |
|---|---|---|
| 1 · Goal & vision | What the project is for; what it optimizes for | `design-philosophy.md` |
| 2 · Architecture | Architectural stance, layering, boundaries | `design-philosophy.md` |
| 3 · Technology stack | Language + version, framework, SQL flavor + ORM, major libraries | `library-manifest.md` + `environment.md` |
| 4 · Environment model | Data stores + test-data isolation, caching, async/messaging, external services | `environment.md` |
| 5 · Mandated packages | Libraries/tooling required by purpose (distinct from detection) | `library-manifest.md` |
| 6 · Versioning policy | SemVer y/n, version-file location, bump cadence | `conventions.md` |
| 7 · Design system *(UI projects only)* | Tokens, components, layout, required states, a11y, voice | `design-system.md` + `tokens.json` |

Honor the engine's recording discipline (`docs/understanding-interview.md` §1, §3) verbatim:

- **Never a blank prompt.** Seed each field's default from Step 2's detection when available, else show an illustrative example (`docs/understanding-interview.md` §1, Default rule). Detection is *soft-coupled* — run Step 2 first (or interleave it) so the stack-derived fields carry a detected seed.
- **Three distinct states, never collapsed** (`docs/understanding-interview.md` §3.2; `SPEC.md` §4.3): a real answer is `captured`; an explicit "None" / "not yet" / "not applicable" is recorded as the literal value `none` (a captured decision, **not** a gap, **not** `[TBD]`); a genuine unknown the interview cannot resolve and the user cannot supply is left `[TBD]` and flagged 🔴 — **never fabricated, never silently defaulted**.
- **Skip → `[TBD]` 🔴 with its consequence stated** (`docs/understanding-interview.md` §3.3): a skipped field becomes a flagged `[TBD]`; the skip prompt must have already stated what stays unknown and which downstream lens loses grounding.
- **Skip Tier 7 entirely for a repo with no UI surface** — `design-system.md` / `tokens.json` are recorded as `none` / not-applicable, which is the correct "no design-lens grounding" signal, not an omission (`docs/understanding-interview.md` Tier order note; `SPEC.md` §5).

This step **captures** the understanding; it records nothing to any doc. The captured field → `##` anchor map is owned by `docs/understanding-interview.md` §2 — do not re-derive it here; carry each answer forward keyed by its anchor for Step 4.

### Step 2 — Detect the stack (#3)

Run the stack detector read-only and consume its TSV output — it reports findings and writes nothing (`scripts/detect-stack.sh` header: "It REPORTS findings; it never writes docs or config"):

```bash
# bash — read-only stack detection against the repo root.
./scripts/detect-stack.sh .
```

```powershell
# PowerShell 7+ — the cross-platform twin (identical findings).
./scripts/detect-stack.ps1 .
```

The detector emits TSV: a header then one finding per stack — columns `stack  signal  convention  manifestPin  domainSkills  flag`. Consume each finding as the **seed** for the interview's stack-derived defaults and for the plan's recorded entries:

- `convention` → seeds the best-practice convention note (→ `conventions.md` anchors).
- `manifestPin` → seeds the framework + version pin (→ `library-manifest.md#Runtime & frameworks`).
- `domainSkills` → the `driver.json#domainSkills` candidate (a JSON-array literal, or **empty** for an unmapped stack — the detector omits rather than fabricates; an empty field stays a recorded "none", never an invented skill).
- `flag` = the literal `human` → carry that finding into the plan as a `[TBD]` 🔴 (e.g. no recognizable stack signal, an ambiguous primary stack, an unresolved framework). Detection's flagged unknowns are the genuine unknowns — they stay `[TBD]` 🔴, never guessed.

Detection **seeds** the defaults the interview confirms; the **resolved** value (what the human accepted/edited at Step 1) is what reaches the plan. Where detection and the interview disagree, the interview answer wins (the human confirmed it).

### Step 3 — Inspect the repo (adopt-or-init: a read-only delta)

Determine whether this is a **fresh** repo (bootstrap from empty) or an **existing** repo (plan only the delta). This is a **read** against current state — it makes no write to compute the delta ([BRIEF.md:67](../../BRIEF.md); `SPEC.md` §4.4):

| Signal read (read-only) | Tells the plan |
|---|---|
| `<projectDocs>/` docs present? (per-doc, per-anchor — a `[TBD]` anchor counts as **not present**) | Which §A doc entries are "would populate" vs "already present (no change)". |
| `.milestone-config/driver.json` / `feeder.json` keys present? (read at Step 0) | Which §B config keys are "would add" vs "already present (no change)" vs "would change" (value differs). |
| Existing branches / labels / branch protection / CI workflow — read **only where the Step 0 precondition allows** a read-only `gh` / `git` query | Which §B suite-readiness entries are "would create" vs "already present". When the precondition blocks the read, record the entry's reconcile state as unknown-pending-precondition and flag it 🔴 rather than guessing it absent. |

Map each entry's current-vs-planned state onto the `SPEC.md` §4.4 **reconcile class**:

- **fresh repo** (no `<projectDocs>/`, no `.milestone-config/*` keys): every entry is a create/populate — §A docs are `human-owned` (first `apply` writes the captured content onto an empty/placeholder doc), §B config keys / labels / branches / CI are `add`, protection is `patch`. The plan states the repo is being bootstrapped from empty.
- **existing repo**: distinguish `no-op` (target already matches the captured value) from `add` (target absent) from `patch` (target exists, value differs) from `human-owned` (a human-maintained doc — propose, never overwrite). The human sees only the delta; a fully-synced repo resolves to an all-`no-op` plan (`SPEC.md` §4.4).

`plan` reads existing state to compute this and still **writes nothing**.

### Step 4 — Compose the entries through the doc/config mapping (#7)

Compose Step 1's interview answers + Step 2's detected signals into the plan's two job sections, using the mapping `docs/write-project-docs.md` defines (the compose-from-#3-+-#4 contract). `plan` **records** the composed entries into the plan file; it does **not** call the writer — running the writer is `apply`'s job, not `plan`'s.

**Section A — project-docs population (Job 1, the core)** — one entry per standing doc (`SPEC.md` §5). Key each captured answer by its `##` anchor (the fixed map at `docs/understanding-interview.md` §2 — do not re-derive it). Each entry carries the four §4.2 per-entry fields: **Target** (the doc path), **Captured value** (the real, cited understanding — never a scaffolded placeholder), **Reconcile class** (default `human-owned` for project docs — propose, never overwrite — except a first `apply` onto an empty/placeholder doc), **State** (`captured` / `none` / `[TBD]` 🔴). A doc whose understanding the interview could not resolve carries `[TBD]` 🔴; a doc that does not apply (e.g. `design-system.md` for a backend-only repo) carries `none` (`SPEC.md` §5).

**Section B — suite-readiness (Job 2, supporting)** — record **only non-default keys / create-if-missing entries** (`SPEC.md` §6 — minimal, consumer-driven; a key at its default is omitted):

| Sub-section | Entries recorded | Source |
|---|---|---|
| Configs (`driver.json` / `feeder.json` non-default keys) | `integrationBranch` / `protectedBranch` (branch model), `sourceGlobs`, `uiSurfaceGlobs` (or `none`), `unitTestCmd` / `preflightCmd` (detected), `e2eEnv` (or `none`), **`domainSkills`** (from the §2 detection candidate / §A best-practice capture), **`versioning`** (from Tier 6), `feeder.json#projectDocs` / `reviewer` when non-default. Configs are machine-owned → reconcile class `add` (key absent) or `patch` (value changed), never `human-owned` (`SPEC.md` §6.1). | Steps 1–2 |
| Version-file / bump target | One entry for *where* the version lives. `captured` (`.claude-plugin/plugin.json`) for a plugin repo; `none` for a `versioning: none` project; **`[TBD]` 🔴 when the repo is non-plugin and no version file resolved** — the recorded brief caveat (the driver's bump target is `.claude-plugin/plugin.json` today; a non-plugin version file may need it generalized — [BRIEF.md:38](../../BRIEF.md); `SPEC.md` §6.2), carried explicitly rather than silently dropped. | Tier 6 |
| Label taxonomy | One create-if-missing entry per label — the driver's (`needs design`, `needs decision`, `blocked`, `needs review`, `judgment call`, `in progress`) and the feeder's (`ui`, `logic`, `risk:light`, `risk:heavy`). Identified by name; reconcile class `add` (`SPEC.md` §6.3). | fixed taxonomy |
| Branch model | One entry per branch (integration, protected) to create-if-missing + the default-branch policy. By name; `add`; never delete (`SPEC.md` §6.3). | branch model |
| Branch protection | The protected-branch rules: no direct push, PR required, CI status check required, optional review. Targeted by branch name; `patch`. **🔴 blocked-on-precondition when Step 0 flagged `gh`.** | branch model |
| CI workflow | The GitHub Actions workflow path under `.github/workflows/` running the detected `unitTestCmd` / `preflightCmd` on PRs into the integration branch, registered as the required status check; `add` (absent) / `patch` (drifted). **🔴 blocked-on-precondition when Step 0 flagged `gh`.** | stack detection |

Apply each entry's reconcile class + state from the Step 3 adopt-or-init delta. Record the **safe write order** (`SPEC.md` §7) in the plan so `apply` deploys consequential changes after their prerequisites: 1) project docs, 2) configs, 3) labels, 4) branch model → branch protection → CI workflow.

### Step 5 — Assemble + write the plan file

Derive the **deterministic slug** from the one-line project / milestone goal (the same algorithm the feeder uses — `SPEC.md` §2.2): lowercase the goal, replace every run of non-alphanumeric characters with a single hyphen, strip leading/trailing hyphens, cap the length at a reasonable bound (trim a trailing hyphen if the cut lands on one). The same goal always resolves to the same path; re-running `plan` against the same goal resolves to the **same path** and overwrites it with equivalent content — no second divergent file.

Set the **plan-level status line** (`SPEC.md` §4.1): `READY` when every section is resolved or recorded `none`; `FLAGGED` when one or more 🔴 `[TBD]` fields (or 🔴 blocked-on-precondition entries) remain.

Write the reviewable plan file to the per-run scratch path (`SPEC.md` §2.1):

```
.milestone-bootstrapper/plan-<slug>.md
```

`.milestone-bootstrapper/` is the tool-namespaced, per-clone scratch directory — it **should be gitignored** (per-run scratch, reviewed then deployed, never committed; the suite's `.gitignore` already carries `.milestone-feeder/` and `.milestone-driver-*` — `.milestone-bootstrapper/` is the analog). `plan` writes the file there **regardless** of whether `.gitignore` yet carries the pattern; this skill does not edit `.gitignore` (the consuming `apply` / `update` skills own that). Write the file as **BOM-free UTF-8 with LF line endings and a single trailing newline** (the suite's script convention).

Write the file in the **`SPEC.md` §8 shape** — the fields (§4) are the contract; this layout is one faithful rendering of them:

```markdown
# Provisioning plan — <one-line project goal>

- Slug: <kebab-case-slug>
- Source brief: <inline | file:<path>>          # the bootstrapper's brief is the project's own intent — no `epic #<n>` form
- Status: READY                                  # READY | FLAGGED (🔴 TBDs / precondition blocks remain)
- Project-docs path: <projectDocs, e.g. .project/>

## A. Project docs
| Doc | State | Reconcile | Captured understanding |
|-----|-------|-----------|------------------------|
| design-philosophy.md | captured    | human-owned | <cited stance / layering / what we optimize for / one-way doors / error & testing philosophy> |
| library-manifest.md  | captured    | human-owned | <stack + versions, cited; mandated packages; the dependency gate; avoid/banned> |
| environment.md       | captured    | human-owned | <stores + test-data isolation; caching=none; async; external services; runtime/hosting> |
| conventions.md       | captured    | human-owned | <stack best-practice idioms + naming/layout/test patterns + versioning policy> |
| design-system.md     | none        | human-owned | not applicable (backend-only)        # or captured, for a UI project
| tokens.json          | none        | human-owned | not applicable (backend-only)        # or captured, for a UI project

## B. Suite-readiness
### Configs (non-default keys)
| Key | State | Reconcile | Value |
|-----|-------|-----------|-------|
| driver.json#integrationBranch | captured | add   | <branch>            # recorded only when non-default
| driver.json#domainSkills      | captured | add   | <from detection / best-practice capture>
| driver.json#versioning        | captured | patch | <semver | false>
| driver.json#sourceGlobs       | captured | patch | <globs>
| feeder.json#projectDocs       | captured | add   | <path>              # only when non-default

### Version-file / bump target
| Target | State | Reconcile | Value |
|--------|-------|-----------|-------|
| version file | captured | human-owned | .claude-plugin/plugin.json   # or [TBD] 🔴 for a non-plugin repo with no resolved version file (BRIEF.md:38); or none for versioning:none

### Labels (create-if-missing)
| Label | State | Reconcile |
|-------|-------|-----------|
| needs design | captured | add |
| risk:heavy   | captured | add |
| …            | …        | …   |

### Branch model · protection · CI
| Target | State | Reconcile | Value |
|--------|-------|-----------|-------|
| branch: <integration>            | captured  | add   | integration branch |
| branch: <protected>              | captured  | no-op | already the protected branch |
| protection: <protected>          | captured  | patch | PR required; CI check required; no direct push   # 🔴 blocked-on-precondition when gh failed Step 0
| .github/workflows/ci.yml         | captured  | add   | runs <unitTestCmd> on PRs into <integration>     # 🔴 blocked-on-precondition when gh failed Step 0

## Write order
1. project docs  2. configs  3. labels  4. branch → protection → CI

## Grounding & flags
- <each captured understanding> — grounded in <interview tier / detected signal / .project/<doc>.md#<section>>
- Adopt-or-init: <"fresh repo — bootstrapped from empty" | "existing repo — only the delta is planned">
- 🔴 <each [TBD] genuine unknown and its consequence>; <each blocked-on-precondition entry and the scope it needs>   # "none" when nothing is flagged

---
This plan file is the build artifact — review it, then run `/milestone-bootstrapper:apply` to deploy it (it writes the project docs, the configs, the labels, the branch model, the protection, and the CI in the recorded write order). `update` reconciles a refreshed plan onto an already-bootstrapped repo, diff-first and non-destructive. `plan` wrote no project-docs, no config, no label, no branch, no protection, no CI, and no GitHub state of any kind.
```

Every §A / §B entry carries all four §4.2 per-entry fields (Target / Captured value / Reconcile class / State) — a consumer that finds an entry missing any of the four fails malformed-plan detection (`SPEC.md` §3, §4.2). Keep `none` and `[TBD]` 🔴 distinct on every entry: `none` is a recorded decision ("we know — the answer is nothing"); `[TBD]` 🔴 is a flagged genuine unknown ("a human must decide"). Never collapse one into the other (`SPEC.md` §4.3).

The plan file is local scratch. **Nothing is written to `.project/`, `.milestone-config/*`, branches, branch protection, labels, or CI; no milestone, issue, label, comment, branch, or protection rule is created on GitHub.** The `apply` skill is the only thing that executes the plan; `update` reconciles a refreshed one.

## Output style

Be concise — report status and outcomes flatly, no wall-of-text. Present the precondition status, the captures, the adopt-or-init delta, and the change preview as **tables**, not inline prose. Mark anything that needs a human with 🔴 — every flagged `[TBD]` and every blocked-on-precondition entry. A genuine unknown stays `[TBD]` 🔴; it is never fabricated to make the plan look complete. (Mirrors the suite's shared output style — [BRIEF.md:80](../../BRIEF.md); `docs/understanding-interview.md` §4.)

## Non-negotiables

- **`plan` writes the plan file (local scratch) and NOTHING else.** No project-docs population, no `.milestone-config/*` write, no labels, no branches, no branch protection, no CI, no GitHub state of any kind ([BRIEF.md:22](../../BRIEF.md); `SPEC.md` §1). After a `plan` run, the repo's `.project/`, `driver.json`, `feeder.json`, branches, protection, labels, and CI workflows are byte-for-byte unchanged; the only new artifact is the plan file. The plan **records** the planned changes; `apply` / `update` are the only verbs that execute them.
- **It composes the other steps; it performs none of their writes.** `plan` runs the interview (#4), the detector (#3, read-only), and the doc/config mapping (#7) into the `SPEC.md` plan-file format — it does not write a doc, set a config key, or run the project-docs writer. The plan-file format is owned by `SPEC.md`, not redefined here.
- **Three distinct states, never collapsed** — `captured` / `none` / `[TBD]` 🔴. "None" / "not yet" is a recorded value (a captured decision, not a gap, not `[TBD]`). A genuine unknown is left `[TBD]` and flagged 🔴 — **never fabricated, never silently defaulted** (`SPEC.md` §4.3; [BRIEF.md:30,66](../../BRIEF.md)).
- **Adopt-or-init is a read-only diff** — a fresh repo plans full provisioning (all create/populate); an existing repo plans only the delta (`no-op` / `add` / `patch` / `human-owned`). `plan` reads existing state to compute this and still writes nothing.
- **The `gh` precondition is surfaced, never silent** — on failure `plan` emits a clear message and marks the remote-dependent entries (branch protection, CI registration) 🔴 blocked-on-precondition; it MAY still emit the plan, but MUST NOT claim those steps will succeed ([BRIEF.md:82](../../BRIEF.md)).
- **Deterministic slug; re-run overwrites, never diverges** — the same goal resolves to the same `.milestone-bootstrapper/plan-<slug>.md` path; re-running overwrites it with equivalent content (`SPEC.md` §2.2).
- **Authors no code, opens no PRs, never touches branches.** Reads code and repo state to ground decisions; never edits a source file, creates a branch, or opens a PR.
