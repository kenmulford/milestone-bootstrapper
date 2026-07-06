# apply — Step 3, step (3): Labels — CLI reference

Invoked from [`../SKILL.md`](../SKILL.md) Step 3, step (3). Provision the label taxonomy (the eleven-label taxonomy — `SPEC.md` §6.3) idempotently:

```bash
# bash
./scripts/provision-labels.sh
```

```powershell
# PowerShell 7+
./scripts/provision-labels.ps1
```

- `--force` upsert: creates a missing label, corrects a drifted color/description, never duplicates on re-run (`scripts/provision-labels.sh` header).
- **Remote step** — if Step 0 flagged the `gh` precondition, this is **🔴 blocked-on-precondition** (the script self-checks `gh` and exits non-zero with a named precondition before touching any label).
- A `none`-state label row (the plan recorded no labels to add) is a reported no-op — `apply` does not abort.
- **Read-back + one retry.** After the upsert, the script reads back `gh label list` and compares every label's name/color/description against the taxonomy just asserted. A mismatch (GitHub's eventual consistency can accept a write that hasn't durably landed) retries the upsert exactly once and re-verifies; a still-diverged label after that halts (exit 2), naming the label. A clean run adds exactly one extra `gh label list` call.
