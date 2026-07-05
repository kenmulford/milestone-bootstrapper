# Plan-file skeleton — the `SPEC.md` §8 rendered shape

Referenced from: `skills/plan/SKILL.md` Step 5 ("Assemble + write the plan file").

This is one faithful rendering of the `SPEC.md` §4 fields — the fields are the
contract, not this literal layout. Every §A / §B entry carries all four §4.2
per-entry fields (Target / Captured value / Reconcile class / State) — a
consumer that finds an entry missing any of the four fails malformed-plan
detection (`SPEC.md` §3, §4.2). Keep `none` and `[TBD]` 🔴 distinct on every
entry: `none` is a recorded decision ("we know — the answer is nothing");
`[TBD]` 🔴 is a flagged genuine unknown ("a human must decide"). Never collapse
one into the other (`SPEC.md` §4.3).

```markdown
# Provisioning plan — <one-line project goal>

- Slug: <kebab-case-slug>
- Source brief: <inline | file:<path>>          # the bootstrapper's brief is the project's own intent — no `epic #<n>` form
- Status: READY                                  # READY | FLAGGED (🔴 TBDs / precondition blocks remain)
- Project-docs path: <projectDocs, e.g. .project/>
- App-roots: ["."]                               # ["."] = repo root is the app root (default). Nested: ["siteroot/web","siteroot/api"] — globs below are baked root-absolute from these

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
| driver.json#nonNegotiables    | captured | add   | <hard-constraint capture; string[]>   # same provenance as domainSkills
| driver.json#versioning        | captured | patch | boolean — `false` = version-free; omitted = versioned   # driver key is BOOLEAN-only (writer emits only `false`)
| feeder.json#versioning        | captured | add   | `"semver"` \| `"none"`   # Tier-6 routing → the feeder's string-enum read-contract key
| driver.json#sourceGlobs       | captured | patch | <root-absolute globs>   # baked from appRoots; ["."] no-op → e.g. ["skills/**"]; nested → ["siteroot/web/**","siteroot/api/**"]
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
