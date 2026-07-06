# apply — Step 3, step (1): Project docs — CLI reference

Invoked from [`../SKILL.md`](../SKILL.md) Step 3, step (1) — the lowest-risk write. For each **§A** row, populate its doc by invoking the project-docs writer (`scripts/write-project-docs.sh`, #7). The writer is the per-`##`-anchor placement primitive; `apply` keys the recorded captured understanding by anchor using the **fixed field→doc→anchor map** (`docs/understanding-interview.md` §2; `docs/write-project-docs.md` "Field → doc → anchor routing (FIXED)" — read it, do not re-derive it), builds the per-anchor JSON map, and calls the writer once per target doc:

```bash
# bash — populate one doc from the recorded per-anchor map. <map> is the JSON
# the caller composed from the §A captured understanding keyed by the FIXED anchor
# map; each value is { "state": "captured"|"none"|"tbd", "content": "<text>" }.
./scripts/write-project-docs.sh --template "<projectDocs>/<doc>" --map "<map.json>"
```

```powershell
# PowerShell 7+ — the behaviorally-equivalent twin (PascalCase -Flag params).
./scripts/write-project-docs.ps1 -Template "<projectDocs>/<doc>" -Map "<map.json>"
```

- A row whose **State is `none`** records the recorded "None" answer under its anchor (`--state none` → no 🔴); a doc that is wholly not-applicable (e.g. `design-system.md` / `tokens.json` for a backend-only repo) is a no-op reported as a no-op.
- A row whose **State is `[TBD]` 🔴** passes `--state tbd` for that anchor — the writer leaves the `[TBD]` placeholder and the entry stays flagged. Never fabricate the content.
- The writer is idempotent and append-only: it places content under the named anchor, never renames/reorders/invents a heading, and a re-run that finds the doc already populated changes nothing (`scripts/write-project-docs.sh` header).
