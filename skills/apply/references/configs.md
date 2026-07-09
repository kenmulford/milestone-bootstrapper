# apply — Step 3, step (2): Configs — CLI reference

Invoked from [`../SKILL.md`](../SKILL.md) Step 3, step (2). Write the two config slices. They are **order-independent relative to each other** — `feeder.json` (#5) and `driver.json` (#8) neither depend on the other, so either may run first within step (2) (issue Design; [BRIEF.md:47](../../../BRIEF.md)). Both writers are non-interactive direct writers (Option A) — **never** the interactive `setup` interviews (`scripts/write-driver-config.sh` header: "deliberately does NOT invoke `milestone-driver:setup` … invoking it from `apply` would re-interview the user mid-run").

Pass each writer the **resolved values from the §B Configs rows** (the writer re-derives nothing; detection happened in `plan`):

```bash
# bash — feeder.json slice (#5): the feeder-owned keys projectDocs / versioning.
# Omit --project-docs when at the bundled default; omit --versioning when the
# Tier-6 answer was skipped (versioning has NO default).
./scripts/write-feeder-config.sh --repo "<repo>" [--project-docs "<path>"] [--versioning "<semver|none>"]

# bash — driver.json slice (#8): the three Core keys are REQUIRED; optionals are
# omitted when the plan did not record them (never written as null/empty). The
# branch names recorded in §B (branch model) ARE driver.json#integrationBranch /
# #protectedBranch — write them here so steps (4)-(6) can read them back.
./scripts/write-driver-config.sh --repo "<repo>" \
  --integration-branch "<integration>" --protected-branch "<protected>" \
  --source-globs '<json string[]>' \
  [--project-docs "<path>"] \
  [--domain-skills '<json string[]>'] [--non-negotiables '<json string[]>'] [--versioning false] [--ui-surface-globs '<json>'] \
  [--stack '<enum>'] [--stack-version-file '<path>'] \
  [--unit-test-cmd "<cmd>"] [--preflight-cmd "<cmd>"] [--e2e-env '<json>']
```

```powershell
# PowerShell 7+ — the behaviorally-equivalent twins (PascalCase -Flag params).
./scripts/write-feeder-config.ps1 -Repo "<repo>" [-ProjectDocs "<path>"] [-Versioning "<semver|none>"]
./scripts/write-driver-config.ps1 -Repo "<repo>" -IntegrationBranch "<integration>" -ProtectedBranch "<protected>" -SourceGlobs '<json string[]>' [-ProjectDocs "<path>"] [-DomainSkills '<json>'] [-NonNegotiables '<json>'] [-Versioning false] [-UiSurfaceGlobs '<json>'] [-Stack '<enum>'] [-StackVersionFile '<path>'] [-UnitTestCmd "<cmd>"] [-PreflightCmd "<cmd>"] [-E2eEnv '<json>']
```

- **`--project-docs` / `-ProjectDocs`** → pass the SAME Step-0-resolved project-docs value to BOTH writers, so `feeder.json#projectDocs` and `driver.json#projectDocs` cannot diverge. `apply` passes the resolved value uniformly; the writer itself omits the key when it equals the default `.project/` (omit-when-default lives in the writer, not in `apply`).
- **`sourceGlobs` / `uiSurfaceGlobs` are passed VERBATIM** → the §B values are already **root-absolute** (the app-root prefix was baked at plan time — `SPEC.md` §4.1, §6.1; the `"."` prefix was a no-op, so a single-root plan's globs are unprefixed). `apply` hands them to `--source-globs` / `--ui-surface-globs` exactly as recorded — it does **not** re-prefix, re-derive, or know the app-roots. The writers persist them opaquely (their headers: re-derive nothing), which is why **no `appRoots` key is ever written** to `driver.json`.
- **`versioning`** (DUAL-WRITE — one Tier-6 answer, two writers, two DISTINCT keys) → the single recorded versioning answer is passed to BOTH the driver and the feeder writer, mapped per its type:
  - **DRIVER** (`driver.json#versioning`, boolean) → `--versioning false` / `-Versioning false` **only when the plan recorded non-versioned**; omit otherwise (absent-means-versioned — the driver writer emits only `false`).
  - **FEEDER** (`feeder.json#versioning`, string enum) → `--versioning semver` / `-Versioning semver` when **versioned**; `--versioning none` when **non-versioned**; **omit** when the Tier-6 answer was skipped/[TBD] (the feeder key has no default — absent = infer-or-ask, `milestone-feeder/docs/profile-schema.md:52`; never write a placeholder).
- **`stack` / `stackVersionFile`** → pass `--stack` / `-Stack` (the resolved enum) and `--stack-version-file` / `-StackVersionFile` (the version-file PATH) **only when the §B Configs row recorded them**; omit when absent (the writer omits `stack` for `none`/empty and `stackVersionFile` when not passed — `scripts/write-driver-config.sh` stack validation). Same optional-pass-through shape as `--domain-skills` / `--versioning`.
- **`nonNegotiables`** → pass `--non-negotiables` / `-NonNegotiables` (the recorded JSON string[]) **only when the §B Configs row `driver.json#nonNegotiables` recorded it**; omit when absent (the writer omits it when not passed). Same optional-pass-through shape as `--domain-skills`.
- Both writers are idempotent: a re-run whose assembled object is byte-identical to the existing file leaves it untouched (true no-op; `scripts/write-feeder-config.sh` Behavior). For the feeder slice specifically, an all-default assembled object (`{}`) is **not emitted at all** — the writer leaves `feeder.json` **absent** rather than writing `{}`, so `milestone-feeder`'s absent-only first-run `setup` fires (issue #77).
- **Why configs come before the branch/CI/protection tail:** `provision-branches`, `emit-ci-workflow`, and `provision-protection` all **read the branch names from `.milestone-config/driver.json`** (their headers: "Branch names are SOURCED, never chosen"; "CONSUMES the values #8 already resolved"). If the config step has not landed, those steps hit a precondition failure. The safe order places configs at step (2) so the tail's prerequisite exists.
