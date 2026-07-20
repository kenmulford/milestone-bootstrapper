# The understanding-interview engine

The reusable procedure that captures what Claude must know about a project and
records it into the project docs (`.project/`). This is **Job 1** of the
bootstrapper — the understanding layer that every later tool grounds in
([BRIEF.md:28-41](../BRIEF.md)).

This document is the **engine**, not a user-facing command and not the
orchestration. It is invoked *by* the `plan` skill (#9) and reconciled *by* the
`apply` / `update` skills (#13/#14). They own the surface, the plan file, and the
writes; this engine owns the interview and the recording discipline that fills
the doc sections.

> [!IMPORTANT]
> **Scope.** This engine captures understanding and records it into the
> `.project/` doc sections — nothing else. It does **not** write
> `.milestone-config/*` configs, set `domainSkills` / `versioning` keys,
> provision labels / branches / CI, compose with stack **detection** output
> (#7), or run any `plan` / `apply` / `update` orchestration (#9/#13/#14). Those
> tools *consume* this engine's output. Keep the boundary clean: ask, record the
> answer under the right `##` anchor, stop.

---

## 1. The interview pattern

Mirror the driver setup's Phase-2 tier-by-tier confirmation
([milestone-driver setup SKILL.md:50-67](../../milestone-driver/skills/setup/SKILL.md),
non-negotiables :235-237). The shape is identical; only the captured material
differs (project understanding here, profile keys there).

Present capture fields **grouped by concern**, one field or logical group at a
time. For every field:

| Step | Rule |
|---|---|
| **Label** | State a plain-language label for what is being captured. |
| **Default** | Show a detected default **or** an illustrative example — **never a blank prompt**. (Non-negotiable: [SKILL.md:235](../../milestone-driver/skills/setup/SKILL.md).) |
| **Choice** | Accept · edit · skip. Never leave a field set without an explicit choice. |
| **Skip consequence** | On any skippable field, state the consequence on the same line — what stays `[TBD]` 🔴 and which downstream lens loses grounding. (Non-negotiable: [SKILL.md:236](../../milestone-driver/skills/setup/SKILL.md).) |
| **Atomicity** | Never write a partial result. Either a tier's fields are resolved (captured / "none" / explicitly skipped to `[TBD]` 🔴) or nothing for that tier is written. (Non-negotiable: [SKILL.md:237](../../milestone-driver/skills/setup/SKILL.md).) |

The detected default is *soft-coupled* to stack detection (#7/#3): when detection
is available, seed the default from it; when it is not, fall back to an
illustrative example. Either way the prompt is never blank — that is the
load-bearing rule, not the source of the default.

### Tier order (group by concern)

| Tier | Captures | Target doc(s) |
|---|---|---|
| **1 · Goal & vision** | What the project is for; what it optimizes for. | `design-philosophy.md` |
| **2 · Architecture** | Architectural stance, layering, boundaries. | `design-philosophy.md` |
| **3 · Technology stack** | Language + version, framework, SQL flavor + ORM, major libraries. | `library-manifest.md` + `environment.md` |
| **4 · Environment model** | Data stores + test-data isolation, caching, async/messaging, external services, deployment targets. | `environment.md` |
| **5 · Mandated packages** | Libraries/tooling required by purpose (distinct from what detection finds). | `library-manifest.md` |
| **6 · Versioning policy** | SemVer yes/no, version-file location, bump cadence. | `conventions.md` |
| **7 · Design system** *(UI projects only)* | Tokens, components, layout, required states, a11y, voice. | `design-system.md` + `tokens.json` |
| **8 · Configuration & secrets** | Config & secret key norms: connection strings, auth/JWT, third-party API keys, notification targets, CORS origins, per-env app config, build outputs — names · buckets · shapes · env · required?, **never values**. | `config-catalog.md` |

Skip Tier 7 entirely for a repo with no UI surface — an all-`[TBD]`
`design-system.md` is the correct "no design-lens grounding" signal
(`design-system.md` header comment), so leaving it untouched is *recording*, not
omission.

### Suite-readiness gate questions (recorded to §B, not to a `.project/` anchor)

A small number of capture fields answer a **suite-readiness** question rather
than a project-understanding one: their answer lands in the plan file's §B
(`SPEC.md` §6), not under a `.project/` `##` anchor. Tier 6's versioning answer
already works this way (it dual-writes `driver.json#versioning` /
`feeder.json#versioning` alongside its `conventions.md` anchor). Ask these with
the **same §1 pattern** — label, non-blank default, accept/edit/skip, skip
consequence on the same line — and the **same §3.2 three states**. They add no
`##` anchor, so the fixed §2 map below is unchanged.

| Field | Question (ask verbatim) | Records to | Default to show | Skip → |
|---|---|---|---|---|
| Integration-branch gate | **"Gate the integration branch with CI checks? (PR + required checks; admins can still override for baselines and transient CI breaks)"** | `driver.json#integrationProtection` — `"floor"` when yes; the key is **omitted** for a recorded "none" | `none` (today's behavior — the integration branch is unprotected) | `none` |

- **Three states, never collapsed** (§3.2): a **yes** is `captured` → `floor`; a
  deliberate **"no" / "not yet"** is a recorded `none` (**no 🔴**) → the key is
  omitted; a genuine unknown the human cannot resolve stays `[TBD]` 🔴 and the
  key is left unwritten, never guessed to `floor`.
- **Skip consequence (state it verbatim on the prompt line):** *the integration
  branch stays unprotected and the driver's PRs merge ungated.* Note this field
  skips to a recorded **`none`**, not to `[TBD]` 🔴 — `none` is the documented
  default for this key (`SPEC.md` §6.1), so "not answered" and "answered no" land
  on the same, safe, today's-behavior outcome. That is the one deliberate
  departure from §3.3 for this field, and it is why the consequence must be
  stated: skipping is a real choice here, not a deferral.
- **Why the gate is deliberately weaker than the protected branch's.** The
  integration branch is the one `milestone-driver` opens a PR into per issue and
  auto-merges on green. A release-grade `enforce_admins: true` there deadlocks
  it — a transient or broken required check wedges the branch and no admin can
  override, so nothing lands (bootstrapper #93). The floor this answer provisions
  keeps PR + required checks and leaves admins able to override.

---

## 2. The capture-field → section map (fixed)

This map is **fixed** — taken verbatim from [BRIEF.md:32-39](../BRIEF.md) and the
template `##` anchors. The engine does **not** choose where an answer goes; it
records each captured field under the stable anchor named here. Each anchor was
read from `project-docs/templates/` and is a citation target — never rename one
(§3).

The six doc templates expose **36** `##` anchors total
(`design-philosophy.md` 6 · `library-manifest.md` 4 · `environment.md` 7 ·
`conventions.md` 6 · `design-system.md` 6 · `config-catalog.md` 7). Every anchor
below appears exactly once.

### `design-philosophy.md` (6 anchors) — Tiers 1-2

| Capture field | `##` anchor |
|---|---|
| Goal & vision: what kind of system, what it optimizes for | `## Architectural stance` |
| Architecture: layers and allowed dependency directions | `## Layering & boundaries` |
| Goal & vision: ranked priorities and explicit non-goals | `## What we optimize for` |
| Architecture: irreversible decisions needing human sign-off | `## One-way doors` |
| Architecture: fail-open/closed, error policy, logging | `## Error & failure philosophy` |
| Goal & vision: what is tested, at what level, "verified" bar | `## Testing philosophy` |

### `library-manifest.md` (4 anchors) — Tiers 3, 5

| Capture field | `##` anchor |
|---|---|
| Stack: platform/runtime + primary frameworks **with versions** | `## Runtime & frameworks` |
| Stack + mandated packages: one approved choice per purpose (table) | `## Approved libraries (by purpose)` |
| Mandated packages: where dependency proposals go (the PAUSE gate) | `## Adding a dependency (the gate)` |
| Mandated packages: libraries explicitly not to use, and why | `## Avoid / banned` |

### `environment.md` (7 anchors) — Tiers 3-4

| Capture field | `##` anchor |
|---|---|
| Environment: which environments exist and how they differ | `## Environments` |
| Environment: data stores, topology, **test-data isolation** (biggest drift source) | `## Data stores` |
| Environment: caching tech + invalidation, or **"none"** | `## Caching` |
| Environment: background jobs / queues / streams, or "none" | `## Async & messaging` |
| Environment: third-party services (auth, payments, email, storage, APIs) | `## External services & integrations` |
| Stack/environment: where it runs, runtime/version targets | `## Runtime & hosting` |
| Environment: where the app deploys — hosting vendor/platform/target (record, don't provision) | `## Deployment targets` |

### `conventions.md` (6 anchors) — Tier 6 (+ stack-derived conventions)

| Capture field | `##` anchor |
|---|---|
| Stack-derived: file/type/function/test/branch naming | `## Naming` |
| Stack-derived: where things go, the shape of a feature | `## File & folder layout` |
| Stack-derived: where tests live, naming, fixtures, a good test | `## Test patterns` |
| Stack-derived: reference implementations to mirror (table, `path:line`) | `## Canonical exemplars (mirror these)` |
| Stack-derived: commit message format + PR expectations | `## Commits & PRs` |
| Versioning policy: SemVer y/n, version-file location, bump cadence | `## Versioning` |

### `design-system.md` (6 anchors) — Tier 7 (UI projects only)

| Capture field | `##` anchor |
|---|---|
| Design tokens: color/type/spacing/radius intent (source of truth `tokens.json`) | `## Design tokens` |
| Canonical components and where they live (table) | `## Component inventory` |
| Grid, breakpoints, spacing rhythm, density | `## Layout & responsive rules` |
| Empty / Loading / Error / Disabled states (bullet list) | `## Required states` |
| Contrast, focus, target size, semantics standard | `## Accessibility baseline` |
| Tone for labels, errors, empty states | `## Voice & microcopy` |

`tokens.json` is the machine-readable companion to `## Design tokens`: record
real values over its `[TBD]` cells with the same discipline; an untouched `[TBD]`
token reads as unspecified (file header comment).

### `config-catalog.md` (7 anchors) — Tier 8

| Capture field | `##` anchor |
|---|---|
| Config: DB/service connection strings **incl. the local-dev DB engine** (LocalDB / Docker SQL / dev cloud) — the F5-dev target is the most-missed | `## Connection strings` |
| Config: auth/JWT key set — the **full set (Key · Issuer · Audience)**, not only the signing key | `## Auth / JWT` |
| Config: third-party API keys (payments, storage, external APIs) — key name + source bucket, never the value | `## Third-party API keys` |
| Config: notification targets **incl. the sender/from address**, not only the recipient | `## Notification targets` |
| Config: the **complete** CORS origin list across environments (localhost + apex + www + api) | `## CORS origins` |
| Config: per-environment app config (`apiUrl`, feature flags, etc.) | `## App config (per-environment)` |
| Config: build outputs / publish dirs / artifact paths | `## Build outputs` |

> **Best-practice adherence is load-bearing** ([BRIEF.md:35](../BRIEF.md)).
> Capturing a framework name is not enough — record the conventions that *follow*
> from it (e.g. FastAPI → Pydantic models, DI pattern, async I/O, router layout)
> into the `conventions.md` anchors above and pin the framework + version under
> `## Runtime & frameworks`. Wiring the driver's `domainSkills` from that capture
> is a **config write owned by #7**, not this engine — record the understanding
> here; the config step consumes it.

---

## 3. Recording discipline

Three rules govern how a captured answer lands in a doc. They are the whole
consistency mechanism — get them exactly right.

### 3.1 Replace the placeholder under a stable heading — never rename the heading

Each `##` heading carries a placeholder beneath it: a `> [TBD] — …` blockquote, a
table row of `[TBD]` cells, or (in `## Required states`) `[TBD]` bullets. Record
the answer by **replacing the placeholder content under the heading**.

**Never rename, reword, or reorder a `##` heading.** Headings are citation
anchors — downstream tools cite `.project/<file>.md#<section>`, so a renamed
heading silently breaks every citation
([project-docs templates header comments](../project-docs/templates/design-philosophy.md);
SPEC.md §4.1). Add a *new* section only by appending, never by renaming an
existing one.

### 3.2 The three states — `captured` vs `none` vs `[TBD]` 🔴 (never collapse them)

There are three distinct, recorded states. They are **not** interchangeable
([SPEC.md §4.3, lines 163-176](../SPEC.md); [BRIEF.md:30](../BRIEF.md)).

| State | What it means | How it is recorded |
|---|---|---|
| **`captured`** | The user supplied a real answer. | The answer replaces the placeholder. Plain text, no 🔴. |
| **`none`** | The user said **"None" / "not yet" / "not applicable"** — a *real, deliberate* answer that a thing does not exist (e.g. "no caching", "no async jobs"). | Record the word **"None"** (or the user's exact phrasing) as the answer. **No 🔴.** It is a captured decision, not an unknown. |
| **`[TBD]` 🔴** | A **genuine unknown** the interview could not resolve and the user could not supply. | Leave the `[TBD]` placeholder in place and flag it 🔴. Never fabricate a value to fill it. |

> [!WARNING]
> **Never collapse `none` into `[TBD]`.** A recorded "None" for caching is the
> safe, drift-preventing answer — it tells every downstream issue "there is no
> cache, do not invent one." A `[TBD]` means "unknown — a human must decide."
> Mapping a user's "None" to `[TBD]` (or vice-versa) corrupts the project's
> understanding. "None" is *captured*; `[TBD]` is *open*.

A `[TBD]` section is always the **safe representation of "not specified"**
([SPEC.md §4.3](../SPEC.md); [BRIEF.md:30,66](../BRIEF.md)): downstream tools
treat a `[TBD]` anchor as "not specified" and fall back to inferred repo
convention rather than grounding on a placeholder (template header comments). So
a genuine unknown left as flagged `[TBD]` is correct and safe — never a reason to
guess.

### 3.3 Skip → `[TBD]` 🔴 with its consequence

A skipped field becomes a flagged `[TBD]` 🔴, and the skip prompt must have
already stated the consequence (§1). Skipping is legitimate; it is *not* the same
as recording "none" — skip = "unknown, deferred to a human", none = "the user
answered that it does not exist."

**One documented exception — the suite-readiness gate `integrationProtection`**
(§1): that field skips to a recorded **`none`**, not to `[TBD]` 🔴, because `none`
is its documented default (`SPEC.md` §6.1), so "not answered" and "answered no"
land on the same safe outcome. Do not flag it 🔴 for being unanswered — record
`none`. It is the only field that departs from the rule above; every other
skipped field follows §3.3 unchanged.

---

## 4. Output style

Honor the suite's shared output style
([BRIEF.md:80](../BRIEF.md); [milestone-driver setup SKILL.md:231](../../milestone-driver/skills/setup/SKILL.md)):

- **Concise and tabular.** Report captures as tables, not walls of prose.
- **🔴 on every flagged `[TBD]`.** Any anchor left as a genuine unknown is marked
  for a human.
- **🔴 on the versioning-target caveat.** When versioning is captured for a
  **non-plugin repo** and the version file is unresolved, flag it: the driver's
  bump target is `.claude-plugin/plugin.json` today, so a non-plugin version file
  may need the driver's target generalized ([BRIEF.md:38](../BRIEF.md);
  [SPEC.md §4.3 / version-file row](../SPEC.md)). Record this as a `[TBD]` 🔴, not
  a silent assumption.

---

## 5. Done — what this engine hands back

A set of **populated** `.project/` doc sections: real captured understanding
under stable anchors, deliberate "None" answers recorded as real answers, and
only genuine unknowns left as flagged `[TBD]` 🔴 ([BRIEF.md:41,66](../BRIEF.md)).
The engine writes no configs, provisions nothing, and runs no orchestration —
`plan` / `apply` / `update` (#9/#13/#14) and the config writer (#7) consume this
output from here.
