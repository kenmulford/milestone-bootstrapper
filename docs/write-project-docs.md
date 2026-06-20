# The project-docs writing layer

The deterministic placement step that takes the **already-resolved** project
understanding and writes it into the six `.project/` docs — replacing the `[TBD]`
placeholder under each template's stable `##` anchor. This is the back half of
**Job 1** (project-docs population, [BRIEF.md:28-41](../BRIEF.md)): the
understanding-interview engine (#4, [docs/understanding-interview.md](understanding-interview.md))
and the stack detector (#3, [scripts/detect-stack.sh](../scripts/detect-stack.sh))
produce the *content*; this layer puts it in the *right place*.

> [!IMPORTANT]
> **Scope — placement only.** This layer does **not** interview, does **not**
> detect a stack, and does **not** decide which value belongs where. The
> composition judgment — which captured answer goes under which anchor, and
> whether a field is `captured` / `none` / a genuine unknown — is done **upstream**
> by the `plan` / `apply` skills (#9/#13) running #3 + #4. This layer receives a
> resolved field → content map and performs the mechanical, idempotent placement.
> Keep the boundary clean: take the resolved map, replace the placeholder under the
> named anchor, stop.

---

## What runs it

Two cross-platform twins (the suite's cross-platform script convention —
[scripts/detect-stack.sh](../scripts/detect-stack.sh) +
[scripts/detect-stack.ps1](../scripts/detect-stack.ps1),
[scripts/write-feeder-config.sh](../scripts/write-feeder-config.sh) +
[.ps1](../scripts/write-feeder-config.ps1)):

| Script | Host |
|---|---|
| [scripts/write-project-docs.sh](../scripts/write-project-docs.sh) | bash |
| [scripts/write-project-docs.ps1](../scripts/write-project-docs.ps1) | PowerShell 7+ |

Both have identical flags, exit codes, and placement behavior, and emit
**byte-identical** populated docs (BOM-free UTF-8, LF, single trailing newline).

---

## The compose-from-#3-+-#4 contract

The caller (the `plan` / `apply` skill) builds the input map by composing two
upstream sources, then hands it to this writer per target doc:

1. **#4 interview answers** ([docs/understanding-interview.md §2](understanding-interview.md)) —
   the captured understanding, already classified into the three states (§3.2 of
   that doc): a real answer, a deliberate "None", or a genuine unknown.
2. **#3 stack detection** ([scripts/detect-stack.sh](../scripts/detect-stack.sh)) —
   the detected framework/version pin, the best-practice convention note, and the
   `domainSkills` candidate. Detection *seeds* the defaults the interview
   confirms; the resolved value is what reaches this writer.

This writer takes the **resolved** value and only does the placement. It never
re-derives a value, never re-runs the interview, and never re-detects the stack.

---

## Field → doc → anchor routing (FIXED)

The routing is **fixed and authoritative** — it is **not** re-specified here.
This writer only places content under the anchor the caller names; the caller
keys the map by the correct anchor. The single source of truth for the routing is:

- [docs/understanding-interview.md §2](understanding-interview.md) — the
  capture-field → `##` anchor map, taken verbatim from
  [BRIEF.md:32-39](../BRIEF.md) and the template `##` anchors.
- [SPEC.md §5](../SPEC.md) (project-docs population) and
  [SPEC.md §6](../SPEC.md) (suite-readiness).

For reference, the doc-level routing (the per-anchor detail lives in the sources
above — read them, do not re-derive from this summary):

| Captured material | Target doc | Anchors (the `##` headings in the template) |
|---|---|---|
| Goal & vision; architectural stance, layering, priorities, one-way doors, error & testing philosophy | `design-philosophy.md` | `Architectural stance` · `Layering & boundaries` · `What we optimize for` · `One-way doors` · `Error & failure philosophy` · `Testing philosophy` |
| Language + version, framework, SQL + ORM, major libraries, mandated packages | `library-manifest.md` | `Runtime & frameworks` · `Approved libraries (by purpose)` · `Adding a dependency (the gate)` · `Avoid / banned` |
| Data stores + test-data isolation, caching, async/messaging, external services, runtime/hosting | `environment.md` | `Environments` · `Data stores` · `Caching` · `Async & messaging` · `External services & integrations` · `Runtime & hosting` |
| Stack best-practice conventions + versioning policy | `conventions.md` | `Naming` · `File & folder layout` · `Test patterns` · `Canonical exemplars (mirror these)` · `Commits & PRs` · `Versioning` |
| Design tokens/components/layout/states (**UI projects only**) | `design-system.md` + `tokens.json` | `Design tokens` · `Component inventory` · `Layout & responsive rules` · `Required states` · `Accessibility baseline` · `Voice & microcopy` |

The anchor names are read from the live templates in
[project-docs/templates/](../project-docs/templates/). They are **citation
anchors** — downstream tools cite `.project/<file>.md#<section>` — so this writer
**never renames, rewords, or reorders a heading**, and **never invents a new
one** (append-only, [docs/understanding-interview.md §3.1](understanding-interview.md)).

---

## The mechanism — replace the placeholder under a stable heading

Each template heading carries a placeholder beneath it: a `> [TBD] — …`
blockquote, a row (or rows) of `[TBD]` table cells, or `[TBD]` bullets (the
`## Required states` block). The writer walks the file tracking the current `##`
heading; within the section of an anchor named in the input, it replaces the
**first contiguous run of `[TBD]`-bearing lines** with the resolved content.

Because the placeholder is matched **only under a current `##` anchor**, the
`[TBD]` tokens inside each template's leading `<!-- … -->` header comment (which
precede the first heading) are structurally out of reach and are **never**
touched.

### The three states — kept distinct, never collapsed

The state is supplied per anchor by the caller and drives placement
([docs/understanding-interview.md §3.2](understanding-interview.md),
[SPEC.md §4.3](../SPEC.md)):

| State | What it means | What the writer does |
|---|---|---|
| `captured` | A real recorded answer. | Replaces the placeholder block with the content. Plain text, no flag. |
| `none` | A deliberate "None / not applicable" — a *captured decision* that the thing does not exist (e.g. no caching, no async jobs). | Replaces the placeholder block with that answer. **No 🔴.** "None" is captured, not unknown — never collapse it into `[TBD]`. |
| `tbd` | A genuine unknown the interview could not resolve. | **Leaves** the `[TBD]` placeholder in place and appends the 🔴 marker. Never fabricates a value. |

An anchor present in the template but **not named** by any input entry is left
untouched (still `[TBD]`). Partial population is legitimate — an untouched
`[TBD]` reads as "not specified" (template header comment), so downstream tools
fall back to inferred repo convention rather than grounding on a placeholder.

---

## Input

A JSON map keyed by the exact `##` anchor text (without the leading `## `), each
value an object `{ "state": "captured"|"none"|"tbd", "content": "<text>" }`.
`content` may be multi-line — a full replacement table body or bullet list — and
replaces the whole placeholder block. For `tbd`, `content` is ignored.

```json
{
  "Data stores": {
    "state": "captured",
    "content": "> Postgres 16; separate prod/staging/test DBs; per-worker test DB."
  },
  "Caching": {
    "state": "none",
    "content": "> None — no cache layer."
  },
  "Async & messaging": {
    "state": "tbd",
    "content": ""
  }
}
```

A single anchor can also be placed without a file, for the simple case:

```sh
./scripts/write-project-docs.sh --template .project/environment.md \
    --anchor "Caching" --state none --content "> None — no cache layer."
```

```powershell
./scripts/write-project-docs.ps1 -Template .project/environment.md `
    -Anchor "Caching" -State none -Content "> None — no cache layer."
```

---

## Flags

| bash | PowerShell | Meaning |
|---|---|---|
| `--template <file>` | `-Template <file>` | The `.project/` doc to populate (edited in place). Required. |
| `--map <file>` | `-Map <file>` | The JSON anchor → `{ state, content }` map. Mutually exclusive with the single-anchor flags. |
| `--anchor <text>` | `-Anchor <text>` | Single-anchor mode: the exact `##` heading text. |
| `--state <s>` | `-State <s>` | Single-anchor mode: `captured` \| `none` \| `tbd` (default `captured`). |
| `--content <text>` | `-Content <text>` | Single-anchor mode: the replacement content. |

Env fallbacks (args win): `PROJECT_DOCS_TEMPLATE`, `PROJECT_DOCS_MAP`.

---

## Behavior & exit codes

- **Idempotent.** Re-running with the same map yields a byte-identical file; a
  pure no-op run leaves the file untouched. (Key-level diff/patch of human edits
  is the `update` skill's job, not this primitive writer's.)
- **Atomic & BOM-free.** Writes via a temp file (a failure never leaves a partial
  doc) as BOM-free UTF-8 with a single trailing newline.

| Exit | Meaning |
|---|---|
| `0` | Doc populated, or already up to date (true no-op). |
| `1` | Bad input / usage — missing flag, unreadable file, malformed map JSON, invalid state. |
| `2` | Write / serialize failure — unwritable path, temp-file failure. |
| `3` | **Unmatched anchor** — an input anchor is not a `##` heading in the template (a renamed/missing heading). A loud failure, never a silent skip; the file is left **unchanged**. |

The unmatched-anchor failure is deliberate: a heading the writer cannot find
means the template drifted from the routing, which would silently break the
citation the heading anchors. The writer refuses rather than guess — fix the
template heading or the input anchor and re-run.

---

## What it hands back

A populated `.project/` doc: real captured understanding under stable anchors,
deliberate "None" answers recorded as real answers, and only genuine unknowns
left as flagged `[TBD]` 🔴. The `plan` / `apply` / `update` skills (#9/#13/#14)
own the surface, the plan file, and the orchestration; this writer owns the one
deterministic placement step they call.
