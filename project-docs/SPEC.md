# project-docs — build-ready spec

A project's **standing docs**: a small set of committed documents capturing its *design intent*, read by every tool in the suite. Where `.milestone-config/` holds *mechanics*, the project docs hold *intent*.

Part of the [dev-tools](../dev-tools/SUITE-PLAN.md) suite. Status: spec — templates included in this repo ([templates/](templates/)).

> **Naming note.** Earlier drafts called this the "substrate" / "project constitution." It is renamed **project docs** to match the human-facing surface the rest of the suite adopted — `milestone-feeder` reads them via its `projectDocs` config key (default `.project/`) and calls them your project's "standing docs."

---

## 1. Purpose & boundary

Make explicit the context the suite's tools otherwise infer from neighboring code, so each tool grounds its reasoning on one canonical, citable source instead of re-deriving it.

| | `.milestone-config/` | `.project/` (project docs) |
|---|---|---|
| Holds | mechanics: branches, test commands, globs | intent: philosophy, design system, libraries, conventions |
| Form | JSON, machine-parsed by hooks/skills | Markdown (+ `tokens.json`), authored by humans |
| Owner | tool setup | the human team |
| Read by | hooks + skill mechanics | reasoning steps in feeder / triage / implementer / reviewers |

Not a place for secrets, mechanics, or per-run state.

---

## 2. Location & file set

Consuming repo, default `.project/` (the feeder's `projectDocs` key points here; default `.project/`).

| File | Captures | Primary consumers | Absent → effect |
|---|---|---|---|
| `design-philosophy.md` | Architectural stance, layering, priorities, one-way doors | feeder, triage, implementer, coherence-reviewer | fall back to inferred convention; no philosophy grounding |
| `design-system.md` (+ `tokens.json`) | Visual system, components, layout, required states, a11y | design-reviewer, coherence-reviewer, wireframing | no design-lens grounding (skip) |
| `library-manifest.md` | Approved/mandated libraries + the new-dependency gate | implementer (new-dep gate), coherence-reviewer | gate has no allowlist; can't flag redundant libs |
| `conventions.md` | Naming, layout, test patterns, canonical exemplars | implementer, coherence-reviewer, feeder | reviewers/implementer rely on inferred convention only |
| `environment.md` | Runtime/prod environment model: data stores + test-DB isolation, caching, async, external services | feeder, triage, implementer, driver (test/E2E setup) | data/test/cache decisions are invented per issue and drift |

**Absent-means-skip throughout** — a repo includes only the docs it needs (a backend-only repo omits `design-system.md`). Same consumer-driven minimalism as the driver profile.

---

## 3. Form factor & distribution

- Canonical **templates** live in this repo's [`templates/`](templates/).
- Scaffolded into a consuming repo's `.project/` by **milestone-bootstrapper** (copied with `[TBD]` placeholders).
- Maintained by a **thin docs skill** (future): `init` (scaffold), `refresh` (reconcile new template sections into an existing `.project/` without clobbering filled content), `propose` (emit a suggested edit when a tool detects drift).
- Likely a **minimal plugin** (templates + the thin skill), not a runtime engine. **Decision:** ship templates first; add the skill when a second consumer needs it.

---

## 4. The three contracts (load-bearing)

### 4.1 Read & cite
Tools cite a project doc as `.project/<doc>.md#<section>` the way the implementer cites `file:line`. **Section headings are stable citation anchors** — templates ship fixed headings; renaming one breaks citations, so the docs evolve by *appending* sections, not renaming them.

### 4.2 Filled vs TBD
Templates ship `[TBD]` placeholders. A section (or whole doc) still marked `[TBD]` is treated as **not specified** — tools fall back to inferred repo convention and never ground a decision on a placeholder. This makes partial adoption safe: a half-filled set helps where it's filled and is invisible where it isn't.

### 4.3 Propose, don't rewrite
Tools **read** the docs and **propose** updates (e.g. the coherence-reviewer spotting a new repeated convention surfaces it for `conventions.md`); they **never silently edit** them. The human owns the docs; a proposal is applied only on human acceptance. Mirrors the suite's "flag it for the human, don't guess" stance.

---

## 5. Locked decisions

- **Term is "project docs," not "substrate"** — matches the feeder surface (`projectDocs`, "standing docs").
- **Separate file per concern** (not one `PROJECT.md`) — distinct consumers, distinct maintenance cadence, cleaner citations.
- **Prose docs + an optional machine-readable `tokens.json`** for design tokens.
- **Default location `.project/`**, configurable via the consuming tool's `projectDocs` key.
- **Absent-means-skip; `[TBD]`-means-absent.**
- **Human-owned; tools propose, never rewrite.**

---

## 6. The documents (the anchors are the contract)

Full content in [`templates/`](templates/). Stable section sets:

- **design-philosophy.md** — Architectural stance · Layering & boundaries · What we optimize for · One-way doors · Error & failure philosophy · Testing philosophy
- **design-system.md** — Design tokens · Component inventory · Layout & responsive rules · Required states · Accessibility baseline · Voice & microcopy
- **library-manifest.md** — Runtime & frameworks · Approved libraries (by purpose) · Adding a dependency (the gate) · Avoid / banned
- **conventions.md** — Naming · File & folder layout · Test patterns · Canonical exemplars · Commits & PRs
- **environment.md** — Environments · Data stores (+ test-DB isolation) · Caching · Async & messaging · External services · Runtime & hosting · Deployment targets

---

## 7. Lifecycle

```
scaffold (bootstrapper)  →  human fills [TBD]  →  tools read & cite
        ▲                                              │
        └──────── human accepts ◀── tools propose ◀────┘
refresh reconciles new template sections into a filled .project/  (idempotent)
```

---

## 8. Plugin contents (if/when it graduates to a plugin)

| Component | Purpose |
|---|---|
| `templates/` | The document set (this repo). |
| `skills/init` · `skills/refresh` · `skills/propose` | The thin maintenance skill (future). |

No hooks, no agents required — it's read-the-docs plus light maintenance.

---

## 9. Build order

1. **Templates** (done in this repo) — usable immediately, by hand or via the bootstrapper.
2. **Wire consumers** — the feeder **already** reads `projectDocs` (default `.project/`), and the driver's `.milestone-config/` resolution shipped in **driver v1.9.0**, so the config plumbing exists. Remaining: add explicit project-docs citations to triage/implementer and to the coherence-reviewer.
3. **The thin docs skill** (`init`/`refresh`/`propose`) once a second repo adopts the docs.

---

## 10. Open questions

- `refresh` reconciliation: how to merge new template sections into a filled `.project/` without clobbering human content.
- `tokens.json` schema breadth — start minimal, expand per consumer.
- Should `design-philosophy.md`'s "one-way doors" auto-feed the driver's `needs decision` label when an issue touches one?
- Naming: resolved — stays `project-docs` (unprefixed shared layer); the `milestone-` prefix is for engines only.
