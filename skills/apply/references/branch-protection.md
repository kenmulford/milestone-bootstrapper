# apply — Step 3, step (6): Branch protection — CLI reference

Invoked from [`../SKILL.md`](../SKILL.md) Step 3, step (6) — run AFTER CI. Step (6) **iterates protection targets**; it is still one step in the fixed six-step order, not a seventh (issue #93 decision f).

## The targets

| Target | Floor | Run when | `enforce_admins` |
|---|---|---|---|
| `protectedBranch` (release) | `release` — the default | **Always.** | `true` — release-grade; admins cannot bypass. |
| `integrationBranch` | `integration` | **Only** when `driver.json` carries `integrationProtection: "floor"`. | `false` — admins may override. |

Run the release target first, then the integration target when it applies. Both read the same CI contexts, so both must run after step (5).

### Target 1 — the protected branch (always)

```bash
# bash — --floor release is the DEFAULT; passing it explicitly is equivalent.
./scripts/provision-protection.sh --repo "<repo>"
```

```powershell
# PowerShell 7+ (PascalCase -Flag params; -DryRun is a [switch]).
./scripts/provision-protection.ps1 -Repo "<repo>"
```

### Target 2 — the integration branch (only when opted in)

```bash
# bash — run ONLY when driver.json has integrationProtection: "floor".
./scripts/provision-protection.sh --repo "<repo>" --floor integration
```

```powershell
./scripts/provision-protection.ps1 -Repo "<repo>" -Floor integration
```

- **Double gate — `apply` skips it AND the script self-gates.** `apply` skips the invocation when the key is absent or `"none"`; if it is invoked anyway, the script re-reads `integrationProtection` itself and exits **0** with a "not opted in" line having changed nothing. Neither gate alone can protect a branch the user did not opt into, and neither can be bypassed by the other misfiring.
- **Why a weaker floor here.** The integration branch is the one `milestone-driver` opens a PR into per issue and auto-merges on green. `enforce_admins: true` there deadlocks it — a transient or broken required check wedges the branch and no admin can override, so not even a baseline PR can land (issue #93). The gate is still real: PR required + required status checks.
- **🔴 REFUSE — exit 1, nothing changed.** If the integration branch **already** carries `enforce_admins: true` (a human previously applied the release floor there), the script refuses: it changes nothing, exits 1, names the deadlock, and prints the exact `gh api -X DELETE repos/<slug>/branches/<integration>/protection/enforce_admins` to clear it. It also names the **non-destructive** way out: set `integrationProtection: "none"` in `driver.json` to leave that protection in place and stop asserting the floor there — so the user who hardened the branch **deliberately** is never left with weakening production protection as the only advertised escape from a permanently-halting run. There is **no** `--force` / `-Force` and no other downgrade path — clearing existing protection is the one destructive act and a human performs it knowingly. `apply` **halts** on this like any other step failure (the halt/name/report path), and the refusal fires **before** the merge, so a `--dry-run` preview surfaces it too.

## Both targets

- Reads its target branch from `driver.json` (step 2) — `protectedBranch` at the release floor, `integrationBranch` at the integration floor — and the required-status-check contexts from the `.github/workflows/ci.yml` emitted at step (5); that file must already exist, which is why this step is **last**.
- Asserts the floor (no direct push, PR required, CI checks required, `enforce_admins` per floor, no force-push/deletions), **merging UP**: it GETs existing protection first and keeps the stronger value per field, so re-asserting is a safe idempotent no-op and a stronger-than-floor setting is preserved, never reconciled down (`scripts/provision-protection.sh` header). The integration floor is create-only or reconcile-UP for the same reason — it never downgrades, it refuses.
- **Remote step needing repo-admin** — 🔴 blocked-on-precondition when Step 0 flagged `gh` or the token lacks repo-admin (the script probes admin permission before any write and hard-stops with a clear message on insufficient scope).
- **Read-back + one retry.** The script's existing post-PUT read-back (GETs the protection and confirms PR-required/`enforce_admins`/status-check contexts) retries the PUT exactly once and re-verifies before halting, instead of halting immediately on the first mismatch — bounding the same eventual-consistency risk the other three steps guard against. The `enforce_admins` assertion checks the value **the running floor wrote** (`true` at release, `false` at integration), not a fixed `true`.
