# apply — Step 3, step (6): Branch protection — CLI reference

Invoked from [`../SKILL.md`](../SKILL.md) Step 3, step (6) — run AFTER CI. Assert the protected branch's server-side safety floor:

```bash
# bash
./scripts/provision-protection.sh --repo "<repo>"
```

```powershell
# PowerShell 7+ (PascalCase -Flag params; -DryRun is a [switch]).
./scripts/provision-protection.ps1 -Repo "<repo>"
```

- Reads `protectedBranch` from `driver.json` (step 2) and the required-status-check contexts from the `.github/workflows/ci.yml` emitted at step (5) — that file must already exist, which is why this step is **last**.
- Asserts the floor (no direct push, PR required, CI checks required, `enforce_admins`, no force-push/deletions), **merging UP**: it GETs existing protection first and keeps the stronger value per field, so re-asserting is a safe idempotent no-op and a stronger-than-floor setting is preserved, never reconciled down (`scripts/provision-protection.sh` header).
- **Remote step needing repo-admin** — 🔴 blocked-on-precondition when Step 0 flagged `gh` or the token lacks repo-admin (the script probes admin permission before any write and hard-stops with a clear message on insufficient scope).
