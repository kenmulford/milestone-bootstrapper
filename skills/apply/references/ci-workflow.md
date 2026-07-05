# apply — Step 3, step (5): CI workflow — CLI reference

Invoked from [`../SKILL.md`](../SKILL.md) Step 3, step (5) — run BEFORE protection. Emit `.github/workflows/ci.yml` running the recorded test/preflight commands on PRs into the integration branch:

```bash
# bash
./scripts/emit-ci-workflow.sh --repo "<repo>"
```

```powershell
# PowerShell 7+ (PascalCase -Flag param).
./scripts/emit-ci-workflow.ps1 -Repo "<repo>"
```

- Consumes `integrationBranch` / `unitTestCmd` / `preflightCmd` from the `driver.json` written at step (2) — re-detects nothing. It emits one named job per gate; the job `name:` values (`unit-tests`, `preflight`) ARE the required-status-check contexts step (6) registers (`scripts/emit-ci-workflow.sh` CONTEXT-NAME STABILITY CONTRACT). **This is why CI precedes protection** — the contexts must exist before protection requires them.
- An absent command still gets its job (so the context exists) with a `[TBD]`-flagged step surfaced 🔴; a command is never fabricated (`scripts/emit-ci-workflow.sh` Behavior).
- Idempotent: an absent file is created, a byte-identical file is a no-op, a file that **differs** is **not clobbered** (exit 3 — human edits preserved; reconciling a changed plan is `update`'s job, surfaced 🔴 rather than overwritten).
