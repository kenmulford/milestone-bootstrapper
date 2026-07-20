# Config union write — the full rationale, per-key nuances, and CLI invocation

Referenced from `skills/update/SKILL.md` Step 4 (2). This covers the mechanics of reconciling `driver.json` / `feeder.json` through `apply`'s writers — read this before driving either writer on a drifted or new config key.

## Why the union write is mandatory (two consequences)

The two config writers (`scripts/write-driver-config.*` / `scripts/write-feeder-config.*`) are **whole-file rewriters, not patchers**: each builds the config object from `{}` using **only** the keys you pass on the CLI, then atomically replaces the entire file — it reads the existing file's bytes **only** for the byte-equality no-op check, never to merge in the existing keys (`scripts/write-driver-config.sh` Behavior: "the config object is rebuilt from the recorded entries each run"; the `.ps1` twins build `$obj = [ordered]@{}` from the params alone). Two consequences drive how `update` must orchestrate them — get either wrong and `update` silently deletes live config:

1. **They have NO `--dry-run` / `-DryRun`** (unlike `provision-branches.*` / `provision-protection.*`). They are **write-only primitives** — they cannot preview. So `update` must compute the diff **itself, out-of-band**, before it calls the writer. Do **not** claim the writer previews the change; it does not.
2. **A key you do not pass is DROPPED from the rewritten file.** Passing "only the changed keys" would rebuild `driver.json` from just those keys and **delete every other live key** — directly violating Step 5's live-only guarantee. The writer preserves a key **only because `update` passes it back in.** One feeder-slice nuance follows from issue #77: on an all-default assembled object (`{}`), the feeder writer writes **nothing** and is **non-destructive** — it never deletes an existing file. So a repo with **no** `feeder.json` stays absent (the #77 first-run-`setup` case), while an **existing** `feeder.json` is left **byte-unchanged** — not emptied to `{}`, not deleted. A consequence for `update`: because the writer will neither emit `{}` nor delete, `update` **cannot** use this writer to collapse an existing `feeder.json` back to `{}` — resetting the last non-default feeder key to its default leaves the prior file in place. That is a deliberate, out-of-scope consequence of the #77 non-destructive contract, not a regression this skill works around. None of this changes `update`'s union discipline (still pass live ∪ plan-changes).

## The three-step union procedure

`update` drives these writers **non-destructively by passing the UNION of keys** — every live key plus every plan change — so the whole-file rewrite reproduces everything and drops nothing:

1. **Read the live config first.** Read `.milestone-config/driver.json` (and `feeder.json`) and capture **all** current keys and values — this is the live set the rewrite must reproduce.
2. **Compute and SHOW the live→plan diff before writing.** `update` diffs the live file against the **assembled target object** (the union from step 3) and prints the changed hunks (a `git diff`-style unified hunk of the JSON, changed keys only). The writers cannot do this — `update` computes it out-of-band. Show this diff **before** the write; a target with no changed keys is left untouched (this feeds the no-op).
3. **Invoke the writer with the UNION of keys** so the whole-file rewrite preserves everything. For each live key: pass its **plan value** if the plan changes it (`patch`), else its **live value** unchanged. Then pass each **plan addition** (`add`) the live file lacks. The rebuilt file = **live ∪ plan-changes** — every live key survives because it was passed back in; changed keys take the plan's value; new keys are added. Nothing is dropped.

The writers stay idempotent under this discipline: when the assembled union equals the live file, the writer sees a byte-identical object and leaves the file untouched — a **true no-op** for a fully-synced config (so a fully-synced repo writes nothing here). Write through `apply`'s direct-write writers — **never** the interactive `setup` interviews (`scripts/write-driver-config.sh` header: invoking `setup` would re-interview the user mid-run).

## Exact CLI invocation

```bash
# bash — feeder.json slice (#5). Pass the UNION: every live key (live value if the
# plan doesn't change it, plan value if it does) PLUS plan additions — so the
# whole-file rewrite reproduces every live key and drops none.
./scripts/write-feeder-config.sh --repo "<repo>" [--project-docs "<path>"]

# bash — driver.json slice (#8). Same UNION rule. The three Core keys are always
# written; every OTHER live key is passed back with its live value unless the plan
# changes it; plan additions are added. An optional NEVER carried live and never
# added by the plan stays omitted (never written as null).
./scripts/write-driver-config.sh --repo "<repo>" \
  --integration-branch "<integration>" --protected-branch "<protected>" \
  --source-globs '<json string[]>' \
  [--domain-skills '<json string[]>'] [--non-negotiables '<json string[]>'] [--versioning false] [--ui-surface-globs '<json>'] \
  [--stack '<enum>'] [--stack-version-file '<path>'] [--integration-protection '<none|floor>'] \
  [--unit-test-cmd "<cmd>"] [--preflight-cmd "<cmd>"] [--e2e-env '<json>']
```

```powershell
# PowerShell 7+ — behaviorally-equivalent twins (PascalCase -Flag params). Same UNION rule.
./scripts/write-feeder-config.ps1 -Repo "<repo>" [-ProjectDocs "<path>"]
./scripts/write-driver-config.ps1 -Repo "<repo>" -IntegrationBranch "<integration>" -ProtectedBranch "<protected>" -SourceGlobs '<json string[]>' [-DomainSkills '<json>'] [-NonNegotiables '<json>'] [-Versioning false] [-UiSurfaceGlobs '<json>'] [-Stack '<enum>'] [-StackVersionFile '<path>'] [-IntegrationProtection '<none|floor>'] [-UnitTestCmd "<cmd>"] [-PreflightCmd "<cmd>"] [-E2eEnv '<json>']
```

## Per-key nuances

- **`domainSkills` empty / `none`** → omit `--domain-skills` / `-DomainSkills` **only when no live `domainSkills` exists**; the key stays absent (never written as `[]`) — a recorded "none", never a fabricated skill (`SPEC.md` §4.3). If `domainSkills` **is** live and the plan merely doesn't change it, pass the **live value** back (the union rule) so it survives the rewrite.
- **`nonNegotiables`** → same UNION rule as `domainSkills`. Pass `--non-negotiables` / `-NonNegotiables` with the **plan value** when the plan changes it, else the **live value** carried back so the whole-file rewrite preserves it; omit **only when neither the plan nor the live config carries it** (never written as `[]` — a recorded "none", never fabricated). A live-only `nonNegotiables` the plan no longer carries is the live-only case — flagged 🔴 for the human AND passed through in the union write so the rewrite preserves it.
- **`versioning`** → pass `--versioning false` / `-Versioning false` when the plan records `versioning: false` **or** the live config already has `versioning: false` and the plan doesn't change it (union); omit only when neither carries it.
- **`integrationProtection`** → pass `--integration-protection floor` / `-IntegrationProtection floor` when the plan records `integrationProtection: "floor"` **or** the live config already has it and the plan doesn't change it (union); omit only when neither carries it (absent = the `none` default — the integration branch stays unprotected). **Omitting it on a repo that HAS it live is a silent downgrade**: the whole-file rewrite drops the key, the next `apply`/`update` sees no opt-in, and the integration branch quietly loses its floor. The writers accept only `none` | `floor`; `none` is written as an omission, never as the string.
- **`stack` / `stackVersionFile`** → same UNION rule as `domainSkills`. Pass `--stack` / `-Stack` and `--stack-version-file` / `-StackVersionFile` with the **plan value** when the plan changes them, else the **live value** carried back so the whole-file rewrite preserves them; omit a key **only when neither the plan nor the live config carries it** (an absent key stays absent — never written as empty; the version-file is a PATH, never a resolved version). A live-only `stack`/`stackVersionFile` the plan no longer carries is the live-only case — flagged 🔴 for the human AND passed through in the union write so the rewrite preserves it.
- **`reviewer` (retired) — the ONE exception to the union rule.** `write-feeder-config.*` no longer accepts `--reviewer` / `-Reviewer` — the feeder retired this own-key (self-check gate removed; an unrecognized key is ignored gracefully by the feeder itself), so the writer now errors on the unknown flag. Do **not** pass a live `reviewer` value back. A `feeder.json` written before this fix that still carries `reviewer` **loses it** on the next `update` union write — this is safe and deliberate (the key is already inert downstream), not a live-only case to flag 🔴.
- **The union write is what makes these writers non-destructive.** Because each writer rebuilds the whole file from the keys passed, `update` must pass every live key back in — a key the plan no longer carries is the **live-only** case (Step 5): it is **flagged 🔴 for the human AND passed through in the union write** so the rewrite preserves it. It is **never stripped** — the writer drops it only if `update` fails to pass it, which `update` never does. **Exception:** `reviewer`, above — the writer itself no longer accepts it, so there is nothing to pass.
