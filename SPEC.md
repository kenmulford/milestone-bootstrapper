# milestone-bootstrapper — provisioning-plan-file format (spec)

The format of the **provisioning plan file**: the single reviewable artifact `plan`
writes and `apply` / `update` read back. The plan file is the **interface** between
`plan` (which writes it) and `apply` / `update` (which read it, and regenerate
nothing). The mental model — from the brief — is **the plan file is the spec; the
populated `.project/` and the suite-ready repo are the deployment**
([BRIEF.md:26](BRIEF.md)).

This document **defines the format only.** It does not implement `plan`'s population
logic, nor `apply` / `update`'s execution. It is the structural analog of the
feeder's plan-file contract ([`milestone-feeder/SPEC.md` §3.1](../milestone-feeder/SPEC.md));
where the feeder deploys a milestone + issues, the bootstrapper deploys project docs
+ suite configuration.

> **Naming.** Throughout: `apply` is the bootstrapper's first-deploy verb (the
> feeder's `create`); `update` is the reconcile verb. "The consumers" means
> `apply` and `update` — the two readers of the plan file.

---

## 1. The plan-file-as-interface

`plan` interviews the human, inspects the repo, detects the stack, and **emits one
artifact: the plan file.** It writes nothing to the repo's settings, remote, or
GitHub ([BRIEF.md:22](BRIEF.md)). Everything `plan` would record into `.project/` and
everything it would change to make the repo suite-ready is captured **in the plan
file** as a reviewable preview. The human reads the plan file, then:

- `apply` executes it on a fresh repo (writes the docs, configs, labels, branches,
  protection, CI), or
- `update` reconciles a refreshed plan onto an already-bootstrapped repo (diff-first,
  non-destructive).

The consumers **regenerate nothing.** They do not re-run the interview, re-detect the
stack, or re-derive any decision from the repo — every value they need is a parsed
field in the plan file (§4). This is the load-bearing property: the plan file is the
*complete, self-contained* spec of the deployment, so review happens once, against
one document, before any consequential write.

```
interview + repo inspection + stack detection
        │   (plan; writes nothing to settings/remote/GitHub — BRIEF.md:22)
        ▼
   ┌──────────────────────────────────┐
   │  provisioning plan file          │   the reviewable spec (this document)
   │  .milestone-bootstrapper/        │
   │    plan-<slug>.md                │
   └──────────────────────────────────┘
        │                         │
        │ apply (first deploy)    │ update (reconcile a refreshed plan)
        ▼                         ▼
  populated .project/        diff-then-patch existing docs/configs;
  + suite-ready repo         add new; propose human-owned; no-op when synced
   (the deployment)          (BRIEF.md:24)
```

---

## 2. Location & slug derivation

### 2.1 Scratch location — per-run, gitignored, tool-namespaced

`plan` writes the plan file to a **per-run scratch path** under the bootstrapper's own
namespace directory:

```
.milestone-bootstrapper/plan-<slug>.md
```

`.milestone-bootstrapper/` is the bootstrapper's analog of the feeder's
`.milestone-feeder/` and the driver's `.milestone-driver-*` — a **tool-namespaced,
per-clone runtime scratch directory**, named for the plugin. It **should be
gitignored**: the plan file is reviewed then deployed (via `apply`) or reconciled (via
`update`), never committed (no persistent bootstrapper config — [BRIEF.md:69](BRIEF.md)).
If the repo's `.gitignore` does not yet carry the `.milestone-bootstrapper/` pattern,
the consuming skills add it (this format spec records the requirement; it does not
edit `.gitignore`). The directory name is namespaced; the **pattern** — per-run,
gitignored, deterministic-slug filename — is the contract.

### 2.2 Slug derivation — deterministic, identical algorithm to the feeder

The `<slug>` is a **deterministic** kebab-case slug of the one-line project /
milestone goal, derived by the **same algorithm the feeder uses**
([`milestone-feeder/SPEC.md:65`](../milestone-feeder/SPEC.md),
[`milestone-feeder/skills/plan/SKILL.md:299`](../milestone-feeder/skills/plan/SKILL.md)):

1. Take the one-line project / milestone goal.
2. Lowercase it.
3. Replace every run of non-alphanumeric characters with a single hyphen.
4. Strip any leading / trailing hyphen.
5. Cap the length at a reasonable bound, trimming a trailing hyphen if the cut lands
   on one.

**The same brief always resolves to the same path; a changed brief derives a
different slug.** That divergence is the **staleness signal**: when `apply` / `update`
resolve a slug whose file does not exist, the brief changed since the last `plan`, so
they re-plan rather than apply a stale spec (§3, error/failure state).

---

## 3. Identity, staleness, and failure detection

The plan file carries **only repo-local / brief-local identifiers** — doc paths,
branch names, label names, config keys, the slug. It carries **no GitHub-assigned
identity** (no milestone number, no issue number, no PR number), because none of that
exists at `plan` time and `plan` writes nothing to GitHub ([BRIEF.md:22](BRIEF.md)).
Identity **is the deterministic slug**, not a GitHub number.

This is the deliberate divergence from the feeder, whose plan file carries a *deploy
receipt* (the GitHub milestone number `create` writes back). The bootstrapper has **no
deploy-receipt analog**: its deployment targets are the local filesystem
(`.project/`, `.milestone-config/`) and repo-scoped GitHub settings (branches,
protection, labels, the CI workflow) addressed **by name**, all of which are stable,
human-readable, repo-local identifiers. There is no server-assigned number to carry
back. `apply` / `update` resolve every target by its repo-local name.

A consumer rejects a plan it cannot safely apply via two detectable failure modes:

| Failure | Detection | Consumer response |
|---|---|---|
| **Stale brief** | The resolved `<slug>` has no matching `plan-<slug>.md` (the brief changed since `plan`, so the slug diverged — §2.2). | Re-plan (run `plan` against the current brief), then apply the fresh file. |
| **Malformed plan** | A required field (§4) is absent or unparseable. | Error-and-stop with the missing field named — never silently apply a partial spec. |

A **source-brief reference** field (§4) lets a consumer match the plan back to its
originating brief, so a slug collision or a hand-edited file is detectable rather than
silently mis-applied.

---

## 4. Fields a consumer parses (the contract)

Every field `apply` / `update` read, enumerated unambiguously. A consumer parses these
to execute the deployment **without re-deriving anything** from the repo or the
interview. Fields are grouped: **plan-level identity** (§4.1), then the two job
sections (§5, §6) whose **per-entry** fields are defined here in §4.2.

### 4.1 Plan-level fields

| Field | Type | Why `apply` / `update` need it |
|---|---|---|
| **One-line project / milestone goal** | string | The header / human label of the plan. The slug (below) is derived from it. |
| **Slug** | kebab-case string | The plan's **identity** (§2.2, §3). The consumer resolves the plan file by it; a mismatch is the staleness signal. Repo-local — no GitHub number. |
| **Source-brief reference** | `inline` \| `file:<path>` | Matches the plan back to its originating brief (§3) — the brief↔plan match and any report routing. (No `epic #<n>` form: the bootstrapper's brief is the project's own intent, not a GitHub epic.) |
| **Plan-level verdict / status line** | enum | `READY` (all sections resolved or recorded "none") \| `FLAGGED` (one or more 🔴 `[TBD]` fields remain — §4.3). A consumer surfaces this; `apply` may proceed but must re-surface every 🔴 entry for the human first. |
| **Target project-docs path** | string | Where the project docs are written — the consumer's `projectDocs` location (default `.project/`). Resolved once at plan time so `apply` / `update` write to the same place. |
| **App-roots** (`appRoots`) | array of repo-relative path strings | The repo-relative directories the project's apps live under (e.g. `["siteroot/web", "siteroot/api"]`), for repos whose apps are **nested** while configs + `.project/` stay at the project root. **Default `["."]`** — the repo root *is* the app root (today's single-root behavior). Resolved once at plan time so `apply` / `update` agree. Two load-bearing consumptions: (a) `plan` runs the stack detector **once per app-root** and **unions** the detected signals into the single scaffolded `.project/` docs + `nonNegotiables` (§5; mixed-stack monorepos); (b) `plan` **bakes each app-root as a prefix into that root's emitted `sourceGlobs` / `uiSurfaceGlobs` at scaffold time** (§6.1), so the persisted globs are ordinary **root-absolute** strings (`siteroot/web/**`) the driver/feeder match from the repo root — **no consumed-schema change** (below). A `"."` app-root prefix is a **NO-OP**: `["."]` + `skills/**` → `skills/**` (never `./skills/**`), so a default/single-root plan is **byte-identical** to one with no `appRoots` field at all. |

### 4.2 Per-change-entry fields

**Every** change entry in §5 (project-docs population) and §6 (suite-readiness) carries
the following, so `update` can reconcile each entry independently and non-destructively:

| Per-entry field | Type | Why `apply` / `update` need it |
|---|---|---|
| **Target** | repo-local identifier | *What* the entry changes: a doc path (`.project/conventions.md`), a config key (`driver.json#domainSkills`), a label name, a branch name, a protection rule, the CI workflow path. Always repo-local (§3). |
| **Captured value** | the recorded content / payload | The cited understanding (for docs), the key's value (for configs), the rule (for protection), etc. — what gets written. `apply` writes it verbatim; `update` diffs against the live target. |
| **Reconcile class** | `add` \| `patch` \| `human-owned` \| `no-op` | How `update` reconciles this entry (§4.4). The load-bearing field for the non-destructive reconcile. |
| **State** | `captured` \| `none` \| `[TBD] 🔴` | Distinguishes a recorded decision from a recorded "not applicable" from a genuine, flagged unknown (§4.3). |

A consumer that finds a §5 / §6 entry **missing** any of these four fields fails
malformed-plan detection (§3) for that entry.

### 4.3 State: `captured` vs `none` vs `[TBD] 🔴` (recorded, never fabricated)

The format keeps **three distinct states** for every entry, never collapsing them
([BRIEF.md:30](BRIEF.md), [BRIEF.md:66](BRIEF.md)):

| State | Meaning | Example |
|---|---|---|
| `captured` | A real recorded decision with a value. | `caching: Redis, key-prefix invalidation` |
| `none` | A recorded **"None" / "not yet" / "not applicable"** — a *decision*, not an absence. The entry is present and explicit. | `caching: none`; a backend-only repo's `design-system.md`: `none / not applicable` |
| `[TBD] 🔴` | A **genuine unknown**, carried explicitly and **flagged for a human** (🔴, the suite's mark-for-human convention — [BRIEF.md:80](BRIEF.md)). Never silently dropped, never fabricated. | a version-file location the interview could not resolve (§6.1) |

A plan covering a repo with, e.g., **no design system** carries that section as an
explicit `none` / `not applicable` entry — **not absent.** Absence of an expected
section is a malformed plan (§3), not a "no". A `[TBD] 🔴` is distinct from `none`: one
is "we don't know yet, a human must decide"; the other is "we know, and the answer is
nothing."

### 4.4 Reconcile class — `update`'s non-destructive semantics

`update` reconciles a **refreshed** plan onto an **already-bootstrapped** repo. The
per-entry **reconcile class** tells it how, per [BRIEF.md:24](BRIEF.md),
[BRIEF.md:65](BRIEF.md):

| Reconcile class | `update` behavior |
|---|---|
| `add` | The target does not exist on the repo yet (new since the last `apply` — e.g. a newly-adopted framework's `domainSkills` entry, a new label). **Create it.** |
| `patch` | The target exists but the captured value changed. **Show the diff first, then patch** ([BRIEF.md:24](BRIEF.md)). |
| `human-owned` | A human-editable target (a project doc the team maintains). **Propose** the change; **never overwrite** ([BRIEF.md:24](BRIEF.md), [BRIEF.md:65](BRIEF.md)). Marked so `update` proposes rather than clobbers. |
| `no-op` | The target already matches the captured value. **Do nothing.** |

A **fully-synced repo** (nothing changed since the last deploy) is representable as a
plan where **every entry is `no-op`** — a true no-op plan ([BRIEF.md:24](BRIEF.md)).
That is the recorded, detectable "nothing to do" state, not an empty or absent file.

`apply` (first deploy on a fresh repo) ignores the reconcile class for write ordering —
it writes every entry — but the class is still recorded so the *same* plan file drives
both verbs. The reconcile class is what `update` keys on; `apply` keys on the safe
write order (§7).

---

## 5. Section A — project-docs population (Job 1, the core)

One entry **per standing doc** the bootstrapper populates, carrying the captured,
cited understanding ([BRIEF.md:28-41](BRIEF.md)). Each entry carries the §4.2 per-entry
fields (target / captured value / reconcile class / state). Project docs are
**human-owned** ([`project-docs/SPEC.md` §4.3](project-docs/SPEC.md)), so on `update`
their default reconcile class is **`human-owned`** (propose, never overwrite) — except
a first `apply` onto an empty / placeholder doc, which writes the captured content.

| Entry (target) | Captures | Default `update` reconcile class |
|---|---|---|
| `design-philosophy.md` | Goal & vision; architectural stance, layering, boundaries ([BRIEF.md:32-33](BRIEF.md)). | `human-owned` |
| `library-manifest.md` | The stack — language + version, framework, SQL flavor + ORM, major libraries; mandated packages; the framework/version pin ([BRIEF.md:34-37](BRIEF.md)). | `human-owned` |
| `environment.md` | Data stores + topology (separate vs shared prod/test/staging), the test-data isolation strategy, caching (tech + invalidation, or `none`), async/messaging, external services ([BRIEF.md:36](BRIEF.md)). | `human-owned` |
| `conventions.md` | The best-practice conventions that **follow** from each stack choice (e.g. Pydantic models, DI pattern, async I/O, router layout for FastAPI); naming, layout, test patterns; the versioning policy + bump cadence ([BRIEF.md:35,38](BRIEF.md)). | `human-owned` |
| `design-system.md` | Tokens, components, layout, required states — **UI projects only**; `none` for backend-only repos ([BRIEF.md:39](BRIEF.md)). | `human-owned` |
| `tokens.json` | Machine-readable design tokens — **UI projects only**; `none` for backend-only repos ([BRIEF.md:39](BRIEF.md)). | `human-owned` |

**Captured value = the real, cited understanding** — not a scaffolded placeholder
([BRIEF.md:41,66](BRIEF.md)). Population, not scaffolding, is the whole consistency
mechanism. A doc whose understanding the interview could not resolve carries its entry
as `[TBD] 🔴` (§4.3), never as fabricated content. A doc that does not apply (e.g.
`design-system.md` for a backend-only repo) carries `none` (§4.3) — present and
explicit, per the project-docs **absent-means-skip** rule
([`project-docs/SPEC.md` §4.2](project-docs/SPEC.md)).

> The **best-practice-adherence** capture is load-bearing: the conventions that follow
> from a stack choice land in `conventions.md` + `library-manifest.md` **and** flow
> into the driver's `domainSkills` (§6.1), so the implementer cites authoritative
> idioms rather than improvising ([BRIEF.md:35](BRIEF.md)). The plan file is where that
> linkage is recorded and reviewed before it is written.

---

## 6. Section B — suite-readiness (Job 2, supporting)

The repo plumbing that makes `milestone-feeder` and `milestone-driver` run with no
further setup ([BRIEF.md:43-51](BRIEF.md)). Each sub-section's entries carry the §4.2
per-entry fields. Only **non-default** config keys are recorded — minimal, consumer-
driven, same discipline as the configs themselves.

### 6.1 Configs — `driver.json` / `feeder.json` non-default keys

One entry per **non-default** key the bootstrapper would write. Config files are
**machine-owned** (tool setup, not human-maintained — [`project-docs/SPEC.md` §1](project-docs/SPEC.md)),
so their default `update` reconcile class is `add` (key absent) or `patch` (key
changed), never `human-owned`.

| Config key (target) | Captures | Source |
|---|---|---|
| `driver.json#integrationBranch` | The integration branch name. | branch model (§6.3) |
| `driver.json#protectedBranch` | The protected branch name. | branch model (§6.3) |
| `driver.json#sourceGlobs` | The code paths the driver's hooks guard. **Recorded root-absolute** — each glob already carries its app-root prefix (§4.1 `appRoots`), so a nested-app repo emits `siteroot/web/**`, a single-root repo emits `skills/**` (the `"."` prefix is a no-op). | repo layout × `appRoots` (§4.1) |
| `driver.json#uiSurfaceGlobs` | UI surface paths (UI projects only; else `none`). **Recorded root-absolute** — same app-root prefixing as `sourceGlobs`. | repo layout / stack capture × `appRoots` (§4.1) |
| `driver.json#unitTestCmd` / `preflightCmd` | Detected test / preflight commands. | stack detection |
| `driver.json#e2eEnv` | E2E environment keys (or `none`). | environment capture |
| `driver.json#domainSkills` | Stack-specific skills wired from the best-practice capture (§5) — so the implementer cites idioms ([BRIEF.md:35,47](BRIEF.md)). | stack capture |
| `driver.json#versioning` | The versioning policy (`semver` \| `false`/none) from the interview ([BRIEF.md:38,47](BRIEF.md)). | versioning policy |
| `driver.json#stack` | The runtime family the emitter scaffolds setup for — one of `node` \| `python` \| `dotnet` \| `maui` \| `rust` \| `plugin` \| `none`. Omitted when `none` (no scaffold). | stack detection |
| `driver.json#stackVersionFile` | The detected version-file path (e.g. `.nvmrc`, `.python-version`, `global.json`), when one resolved. | stack detection |
| `feeder.json#projectDocs` | The project-docs location, when non-default. | §4.1 target path |
| `feeder.json#reviewer` | The self-check reviewer, when non-default. | suite wiring |

Defaults are **omitted** (a key at its default is not written — the configs stay
minimal). An entry is recorded only when the captured value diverges from the consumer
tool's default.

> **`appRoots` adds NO consumed-config key.** The app-root prefixing (§4.1) is baked
> into the `sourceGlobs` / `uiSurfaceGlobs` **values** at scaffold time, so the persisted
> globs are ordinary root-absolute strings the driver/feeder already match from the repo
> root. There is **no `appRoots` key in `driver.json` / `feeder.json`** — it lives only
> in the plan-file contract (§4.1). The consumers (`milestone-driver`,
> `milestone-feeder`) need no change and parse no new key; this is a bootstrapper-only
> feature.

### 6.2 Version-file / bump-target — flagged when non-plugin

A dedicated entry carrying the **version-file location / bump target** — *where* the
project's version lives (`pyproject.toml`, `package.json`, `*.csproj`, a `VERSION`
file) — so the driver's per-PR version bump has a target ([BRIEF.md:38](BRIEF.md)).

This resolves the **recorded brief caveat** ([BRIEF.md:38](BRIEF.md)): the driver's
bump target is `.claude-plugin/plugin.json` **today**; a **non-plugin** repo's version
file may need the driver's target generalized. So this entry is carried as a
flagged-for-human `[TBD] 🔴` (§4.3) **when the repo is non-plugin and no version file
resolved** — representing the caveat explicitly rather than silently dropping it. For a
plugin repo it is `captured` (`.claude-plugin/plugin.json`); for a `versioning: none`
project it is `none`. The three states keep the caveat legible and reviewable.

### 6.3 Label taxonomy, branch model, branch protection, CI workflow

| Sub-section (entries) | Captured value | Default `update` reconcile class | Notes |
|---|---|---|---|
| **Label taxonomy** | One entry per label to create-if-missing: the driver's (`needs design`, `needs decision`, `blocked`, `needs review`, `judgment call`, `in progress`) and the feeder's (`ui`, `logic`, `risk:light`, `risk:heavy`) ([BRIEF.md:48](BRIEF.md)). Identified **by name** (repo-local). | `add` (create-if-missing; never delete) | Idempotent create-if-missing. |
| **Branch model** | One entry per branch (integration, protected) to create-if-missing; the default-branch policy ([BRIEF.md:49](BRIEF.md)). Identified **by name**. | `add` | Never delete a branch ([BRIEF.md:65](BRIEF.md)). |
| **Branch protection** | The protected-branch rules: no direct push, PR required, CI status check required, optional review ([BRIEF.md:50](BRIEF.md)). Targeted **by branch name**. | `patch` | Re-asserting protection to match the plan is allowed ([BRIEF.md:65](BRIEF.md)). |
| **CI workflow** | The GitHub Actions workflow (target path under `.github/workflows/`) running the detected `unitTestCmd` / `preflightCmd` on PRs into the integration branch, registered as the required status check ([BRIEF.md:51](BRIEF.md)). | `add` (file absent) / `patch` (drifted) | The protection's required check depends on this workflow's name. |

Every target here is a **repo-local / brief-local identifier** — a label name, a branch
name, a workflow path — never a GitHub-assigned number (§3).

---

## 7. Write order (recorded for `apply`)

The plan file records the **safe write order** so `apply` deploys consequential
changes after their prerequisites ([BRIEF.md:90](BRIEF.md)). Low-risk writes first,
then the dependent chain:

1. **Project docs** (§5) — lowest risk.
2. **Configs** (§6.1, §6.2) — `domainSkills` here depends on the §5 best-practice
   capture having been recorded.
3. **Labels** (§6.3).
4. **Branch model → branch protection → CI workflow** (§6.3) — in this order:
   protection's required status check depends on the CI workflow existing.

`apply` follows this order for a fresh deploy; `update` reconciles per-entry by
reconcile class (§4.4) rather than re-running the full ordered write.

---

## 8. Worked skeleton (illustrative — not the parser)

A minimal, illustrative shape of a plan file. The **fields** (§4) are the contract;
this Markdown layout is one faithful rendering of them.

```markdown
# Provisioning plan — <one-line project goal>

- Slug: <kebab-case-slug>
- Source brief: file:BRIEF.md
- Status: READY            # READY | FLAGGED (🔴 TBDs remain)
- Project-docs path: .project/
- App-roots: ["."]         # ["."] = repo root is the app root (default, single-root). Nested: ["siteroot/web","siteroot/api"]

## A. Project docs
| Doc | State | Reconcile | Captured understanding |
|-----|-------|-----------|------------------------|
| design-philosophy.md | captured    | human-owned | <cited stance / layering> |
| library-manifest.md  | captured    | human-owned | <stack + versions, cited> |
| environment.md       | captured    | human-owned | <stores, test isolation, caching=none> |
| conventions.md       | captured    | human-owned | <stack idioms + versioning policy> |
| design-system.md     | none        | human-owned | not applicable (backend-only) |
| tokens.json          | none        | human-owned | not applicable (backend-only) |

## B. Suite-readiness
### Configs (non-default keys)
| Key | State | Reconcile | Value |
|-----|-------|-----------|-------|
| driver.json#domainSkills | captured | add   | ["<stack-skill>"] |
| driver.json#versioning   | captured | patch | semver |
| driver.json#sourceGlobs  | captured | patch | ["src/**", "tests/**"] |   # root-absolute; ["."] no-op. Nested: ["siteroot/web/**","siteroot/api/**"] |

### Version-file / bump target
| Target | State | Reconcile | Value |
|--------|-------|-----------|-------|
| version file | [TBD] 🔴 | human-owned | non-plugin repo; driver bump target needs generalizing (BRIEF.md:38) |

### Labels (create-if-missing)
| Label | State | Reconcile |
|-------|-------|-----------|
| needs design | captured | add |
| risk:heavy   | captured | add |
| …            | …        | …   |

### Branch model · protection · CI
| Target | State | Reconcile | Value |
|--------|-------|-----------|-------|
| branch: develop                  | captured | add   | integration branch |
| branch: main                     | captured | no-op | already protected branch |
| protection: main                 | captured | patch | PR required; CI check required; no direct push |
| .github/workflows/ci.yml         | captured | add   | runs <unitTestCmd> on PRs into develop |

## Write order
1. project docs  2. configs  3. labels  4. branch → protection → CI
```

---

## 9. Locked decisions

- **The plan file is the interface; `plan` writes it, `apply` / `update` read it and
  regenerate nothing** — the structural mirror of the feeder's §3.1 contract.
- **Identity is the deterministic slug, not a GitHub number** — the bootstrapper writes
  nothing to GitHub at `plan` time ([BRIEF.md:22](BRIEF.md)) and addresses every deploy
  target by a repo-local name, so there is **no deploy-receipt analog**.
- **Three distinct states — `captured` / `none` / `[TBD] 🔴`** — a recorded "none" is a
  decision, not an absence; a genuine unknown is flagged for a human, never fabricated
  ([BRIEF.md:30,66](BRIEF.md)).
- **Per-entry reconcile class drives `update`** — `add` / `patch` / `human-owned` /
  `no-op`; a fully-synced repo is an all-`no-op` plan; project docs default to
  `human-owned` (propose, never overwrite) ([BRIEF.md:24,65](BRIEF.md)).
- **Namespace dir `.milestone-bootstrapper/`, gitignored, per-run** — the bootstrapper's
  analog of `.milestone-feeder/` and `.milestone-driver-*`; no persistent config
  ([BRIEF.md:69](BRIEF.md)).
- **Version-file / bump target is a first-class, flag-able entry** — carried as
  `[TBD] 🔴` when the repo is non-plugin and no version file resolves, making the
  recorded brief caveat representable ([BRIEF.md:38](BRIEF.md)).
- **Minimal, consumer-driven configs** — only non-default keys are recorded.
- **`appRoots` is a plan-file-only field for nested-app layouts** — default `["."]`
  (single-root, byte-unchanged). `plan` detects per app-root and unions the signals
  into one `.project/`, and bakes each app-root as a prefix into that root's
  `sourceGlobs` / `uiSurfaceGlobs` so the persisted globs are root-absolute. The
  `"."` prefix is a no-op. It adds **no** key to `driver.json` / `feeder.json` and
  **no** machine artifact under `.project/`; configs + `.project/` stay at the project
  root. Bootstrapper-only — the consumers need no change (§4.1, §6.1).
