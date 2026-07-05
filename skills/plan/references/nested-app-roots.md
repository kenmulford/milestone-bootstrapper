# Nested / multi-app-root elaboration

Referenced from: `skills/plan/SKILL.md` Step 0, Step 2, and Step 4. Consolidates
the three scattered mentions of the `appRoots` mechanism into one place. Each
of the three steps keeps a one-sentence default-path statement inline and
points here for the full nested-root procedure.

`appRoots` is the repo-relative directories the project's apps live under
(`SPEC.md` §4.1). **Default `["."]`** — the repo root *is* the app root
(today's single-root behavior, byte-identical). A repo whose apps are
**nested** while configs + `.project/` stay at the project root (e.g.
`siteroot/web`, `siteroot/api`) carries those paths instead.

## Step 0 — resolving `appRoots`

Resolve `appRoots` the same way as the project-docs path: a single,
once-resolved plan-level field (`SPEC.md` §4.1). Step 0 sets only the
**default seed** `["."]`; the actual app-roots are **discovered from the
layout inspection at the top of Step 2 and confirmed with the human there —
before the per-root detector consumes them** (so a nested repo's detector loop
iterates the real candidate roots, not the bare default). Record `appRoots`
once so the plan file's `App-roots` field, the per-root detection (Step 2),
and the baked globs (Step 4) all agree.

`appRoots` is a **plan-file-only** field: it is **not** written into
`driver.json` / `feeder.json` and **not** persisted under `.project/`
(`SPEC.md` §4.1, §6.1) — it shapes the detection loop and the emitted glob
*values*, nothing more.

## Step 2 — per-root detection loop

Once `appRoots` is resolved from the layout inspection (repo-root signals →
`["."]`; signals nested under `siteroot/web`, `siteroot/api`, etc. → those
paths, confirmed with the human), run the stack detector read-only, once per
resolved app-root, and union the findings. The detector reports per-root and
writes nothing (`scripts/detect-stack.sh` header: "It REPORTS findings; it
never writes docs or config"); it already accepts a **`[REPO_DIR]`
positional** (`scripts/detect-stack.sh` Usage; `scripts/detect-stack.ps1`
`-RepoDir`), so the per-app-root loop is **orchestrated here**, not by
changing the detector:

```bash
# bash — read-only stack detection, once per app-root. appRoots default ["."]
# runs the detector exactly once against the repo root (today's behavior, unchanged).
for root in "${appRoots[@]}"; do        # e.g. (".") or ("siteroot/web" "siteroot/api")
  ./scripts/detect-stack.sh "$root"     # the detector's [REPO_DIR] positional
done
```

```powershell
# PowerShell 7+ — the cross-platform twin (identical findings, -RepoDir positional).
foreach ($root in $appRoots) {          # e.g. @('.') or @('siteroot/web','siteroot/api')
  ./scripts/detect-stack.ps1 $root
}
```

**Union the per-root findings into one detection set.** The detector reports
per-root; `plan` merges (unions) the findings across app-roots into the single
scaffolded `.project/` docs + `nonNegotiables` — a mixed-stack monorepo (e.g. a
Node `siteroot/web` + a .NET `siteroot/api`) carries **both** stacks'
conventions / manifest pins / `domainSkills` candidates, deduped (`SPEC.md`
§4.1 `appRoots`, §5). The union is the recorded stack capture; `domainSkills`
is the deduped union of every root's mapped skills. A `flag = human` from
**any** root (no signal, ambiguous primary, unresolved framework) carries into
the plan as a `[TBD]` 🔴 for that root — flagged unknowns are never guessed.
For the **default `["."]`** the loop runs exactly once against the repo root
and the union is that single finding set — **byte-identical to today's
single-detector run**.

## Step 4 — baking app-roots into the emitted globs

Before recording `sourceGlobs` / `uiSurfaceGlobs`, **prefix each app-root onto
that root's globs** so every persisted glob is **root-absolute** (`SPEC.md`
§4.1 `appRoots`, §6.1). For each `appRoots` entry `R` and each base glob `G`
that root contributes, derive the emitted glob in this **fixed order —
normalize, then no-op test, then join**:

1. **Normalize `R` first.** Strip any single trailing slash (`siteroot/web/` → `siteroot/web`).
2. **No-op test on the normalized `R`.** Treat `"."`, `"./"`, and `""` (empty) as the **same no-op sentinel** — after step 1 they all normalize to `"."` or `""`. A no-op sentinel emits `G` **unchanged** (never `./G`, never a leading or doubled separator).
3. **Join only a real nested root.** Any `R` that is **not** the no-op sentinel (e.g. `siteroot/web`) emits `R/G` — a single `/` separator between the normalized root and the base glob.

The persisted glob set is the **union** of every app-root's emitted globs:

| `appRoots` | base glob | emitted (recorded) glob |
|---|---|---|
| `["."]` / `["./"]` / `[""]` (default / single-root) | `skills/**` | `skills/**`  ← **no-op sentinel; NEVER `./skills/**` or `//skills/**`** |
| `["siteroot/web"]` (or `["siteroot/web/"]`) | `src/**` | `siteroot/web/src/**`  ← **single separator** |
| `["siteroot/web", "siteroot/api"]` | `src/**` (web), `**/*.cs` (api) | `siteroot/web/src/**`, `siteroot/api/**/*.cs` (union) |

Because normalization runs **before** the no-op test, every spelling of "the
repo root" (`"."`, `"./"`, `""`) collapses to the same no-op sentinel and emits
the base glob unchanged — there is no trailing-slash form that escapes the
no-op into a `./skills/**` join. The baking happens **here, where `plan`
assembles the glob values** — the persisted globs are ordinary strings; the
config writers (`scripts/write-{driver,feeder}-config.*`) take them verbatim
and **re-derive nothing** (their headers: opaque persisters), so they need
**no `appRoots` key**. `uiSurfaceGlobs` is baked the same way (or stays `none`
for a non-UI repo). Because the no-op sentinel emits the base glob unchanged,
a **default / single-root** plan records the **exact globs it would have
without any `appRoots` field** — the no-regression guarantee (`SPEC.md`
§4.1).
