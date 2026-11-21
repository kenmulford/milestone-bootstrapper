# apply — Step 3, step (5): CI workflow — CLI reference

Invoked from [`../SKILL.md`](../SKILL.md) Step 3, step (5) — run before protection. Emit `.github/workflows/ci.yml` running the recorded test/preflight commands on PRs into the integration and protected branches:

```bash
# bash
"${CLAUDE_PLUGIN_ROOT}/scripts/emit-ci-workflow.sh" --repo "<repo>"
```

```powershell
# PowerShell 7+ (PascalCase -Flag param).
& "${CLAUDE_PLUGIN_ROOT}/scripts/emit-ci-workflow.ps1" -Repo "<repo>"
```

- Consumes `integrationBranch` / `unitTestCmd` / `preflightCmd` from the `driver.json` written at step (2) — re-detects nothing. It emits one named job per gate; the job `name:` values (`unit-tests`, `preflight`) are the required-status-check contexts step (6) registers (`scripts/emit-ci-workflow.sh` CONTEXT-NAME STABILITY CONTRACT). **This is why CI precedes protection** — the contexts must exist before protection requires them.
- An absent command still gets its job (so the context exists) with a `[TBD]`-flagged step surfaced 🔴; a command is never fabricated (`scripts/emit-ci-workflow.sh` Behavior).
- Idempotent: an absent file is created, a byte-identical file is a no-op, a file that differs is **not clobbered** (exit 3 — human edits preserved, surfaced 🔴 rather than overwritten; neither `apply` nor `update` rewrites it). To take the generated file, review the diff with `emit-ci-workflow --check`, then delete `ci.yml` and re-run; local edits to it are lost. `emit-ci-workflow --check` is the read-only comparison: it writes nothing, exits 0 when `ci.yml` matches the generated file and 3 when it is absent or differs, and prints the diff. Protection requires `unit-tests`/`preflight` only on exit 0.
- **Read-back + one retry.** This step makes no `gh`/API call — its "read-back" is a local re-read of the just-written file compared against the emitted content, catching a truncated/corrupt write despite a successful move. A mismatch retries the write once (same atomic temp-file path) and re-compares; a still-diverging file after that halts (exit 2). The no-op and diverged-existing-file cases above are unaffected — this only guards the file this run actually wrote.
