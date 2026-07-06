# apply — Step 3, step (4): Branch model — CLI reference

Invoked from [`../SKILL.md`](../SKILL.md) Step 3, step (4). Create the integration + protected branches if missing and set the default-branch policy:

```bash
# bash
./scripts/provision-branches.sh --repo "<repo>"
```

```powershell
# PowerShell 7+ (PascalCase -Flag params; -DryRun is a [switch]).
./scripts/provision-branches.ps1 -Repo "<repo>"
```

- Reads `integrationBranch` / `protectedBranch` from the `driver.json` written at step (2). Creates the protected branch (the base), branches integration off it, points the default branch at protected. **Never deletes, force-pushes, or resets** (`scripts/provision-branches.sh` header) — a re-run on an already-correct repo changes nothing.
- **Remote step** — 🔴 blocked-on-precondition when Step 0 flagged `gh` (branch creation + default-branch change need write/repo-admin scope).
- **Read-back + one retry.** When this run actually wrote something, the script reads back both branches (`gh api repos/<repo>/branches/<branch>`) and the default branch (`gh api repos/<repo>` `.default_branch`) against what it just asserted. A mismatch retries the write exactly once and re-verifies; a still-diverged fact after that halts (exit 2), naming which check diverged. A run that wrote nothing (already correct) skips the read-back — nothing new to verify.
