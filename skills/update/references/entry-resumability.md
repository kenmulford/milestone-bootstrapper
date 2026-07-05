# Entry-level resumability — worklist, state-file, and live-recheck twins

Referenced from `skills/update/SKILL.md` Step 4. This covers the mechanics of the
per-entry resume layer that sits in front of Step 4's existing per-class reconcile
logic — the worklist scope, the state-file schema and read/write/validate twins, the
live-recheck twins for the two bulk scripts (labels, branches), and the resume/
completion behavior. It changes nothing about *what* Step 4 (1)–(6) reconciles or how
— only which entries get walked/narrated on a given run, and whether an already-`done`
entry is skipped.

## Scope — the worklist is a strict subset of §A/§B

The worklist is exactly the §A/§B entries whose **Reconcile class** (`SPEC.md` §4.4;
`skills/update/SKILL.md` "The four reconcile classes") is `add` or `patch`. `human-owned`
entries (a drifted project doc — always freshly proposed for acceptance, never
auto-completed) and `no-op` entries (already zero-work) are excluded from **both** the
state file and the per-entry narrative. Step 3 has already parsed the plan file into
these per-entry rows (`Target` · `State` · `Reconcile` · `Captured value`, `SPEC.md`
§4.2) before Step 4 runs — building the worklist is filtering that already-parsed set
to `add`/`patch`, not re-parsing anything.

An **empty worklist** (every entry `no-op`/`human-owned`) skips the row-by-row walk
entirely: no state file is written, and Step 6 prints the single existing line
`update: repo already matches the refreshed plan — nothing to reconcile (no-op)`
verbatim, never a per-entry narration of the no-ops.

## State-file schema

One JSON object per run, keyed by the plan's deterministic `<slug>` (`SPEC.md` §2.2),
at `.milestone-bootstrapper/update-state-<slug>.json` — a sibling scratch file next to
`plan-<slug>.md` under the same gitignored, tool-namespaced directory (`SPEC.md` §2.1;
the repo's root `.gitignore` already carries the blanket `.milestone-bootstrapper/`
pattern — no new entry needed). Each worklist entry is keyed by its **`Target`** field
exactly as `SPEC.md` §4.2 defines it — a doc path, a config key (`driver.json#domainSkills`),
a bare label name (`needs design`), a branch Target (`branch: develop`), a protection
Target (`protection: main`), or the CI workflow path (`.github/workflows/ci.yml`) — no
new identifier scheme:

```json
{
  "slug": "<slug>",
  "entries": {
    "conventions.md": "pending",
    "driver.json#domainSkills": "done",
    "needs design": "done",
    "branch: develop": "pending"
  }
}
```

Status is one of `pending` \| `done`. The file is **never** read in place of the
refreshed plan — it tracks progress through the worklist only, never *what* to
reconcile (the plan file stays the sole input).

## Read, validate, and initialize

```bash
SLUG="<slug>"                                              # Step 2's resolved slug
STATE_DIR=".milestone-bootstrapper"
STATE_FILE="${STATE_DIR}/update-state-${SLUG}.json"
# WORKLIST: newline-separated Targets, add/patch class, in walk order (Step 3).

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required but not found on PATH." >&2; exit 2; }

DONE_TARGETS=""
if [ -f "$STATE_FILE" ]; then
  if jq -e '.entries | type == "object"' "$STATE_FILE" >/dev/null 2>&1; then
    DONE_TARGETS="$(jq -r '.entries | to_entries[] | select(.value == "done") | .key' "$STATE_FILE")"
  else
    # Unreadable/invalid — never partially trusted: flag it, discard it, and
    # recompute the full add/patch worklist from scratch (a safe, conservative
    # resume — never a silent partial-resume guess, never a rollback).
    echo "🔴 update: ${STATE_FILE} is unreadable or not valid JSON — discarding it and recomputing the full worklist from scratch." >&2
    rm -f "$STATE_FILE"
  fi
fi

is_done() {  # is_done <target> — 0 (true) if already marked done this run
  printf '%s\n' "$DONE_TARGETS" | grep -Fxq -- "$1"
}

# (Re)initialize when missing/discarded, for a non-empty worklist. A target
# already present (valid resume) keeps its status — new targets since the last
# run are added `pending`; nothing already `done` is reset.
if [ -n "$WORKLIST" ]; then
  mkdir -p "$STATE_DIR"
  existing='{}'
  [ -f "$STATE_FILE" ] && existing="$(jq -c '.entries' "$STATE_FILE" 2>/dev/null || echo '{}')"
  merged="$(printf '%s\n' "$WORKLIST" | jq -Rn --argjson existing "$existing" \
    '($existing // {}) as $e | reduce (inputs | select(length > 0)) as $t ($e; if has($t) then . else .[$t] = "pending" end)')"
  jq -n --arg slug "$SLUG" --argjson entries "$merged" '{slug: $slug, entries: $entries}' > "$STATE_FILE"
fi
```

```powershell
$Slug = "<slug>"
$StateDir = ".milestone-bootstrapper"
$StateFile = Join-Path $StateDir "update-state-$Slug.json"
# $Worklist: string[] of Targets, add/patch class, in walk order (Step 3).

$doneTargets = @()
if (Test-Path -LiteralPath $StateFile) {
    try {
        $state = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if ($state.entries -isnot [System.Collections.IDictionary]) { throw "entries is not an object" }
        $doneTargets = $state.entries.Keys | Where-Object { $state.entries[$_] -eq 'done' }
    } catch {
        # Unreadable/invalid — flag, discard, recompute the full worklist (never
        # a partial-resume guess, never a rollback).
        [Console]::Error.WriteLine("🔴 update: $StateFile is unreadable or not valid JSON — discarding it and recomputing the full worklist from scratch.")
        Remove-Item -LiteralPath $StateFile -Force -ErrorAction SilentlyContinue
        $state = $null
    }
}

function Test-EntryDone([string]$Target) { $doneTargets -contains $Target }

if ($Worklist.Count -gt 0) {
    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
    $entries = if ($state -and $state.entries) { $state.entries } else { @{} }
    foreach ($t in $Worklist) { if (-not $entries.ContainsKey($t)) { $entries[$t] = 'pending' } }
    $obj = [ordered]@{ slug = $Slug; entries = $entries }
    $tmp = Join-Path $StateDir ('.update-state.' + [System.IO.Path]::GetRandomFileName())
    Set-Content -LiteralPath $tmp -Value ($obj | ConvertTo-Json -Depth 10) -Encoding utf8NoBOM -NoNewline
    Move-Item -LiteralPath $tmp -Destination $StateFile -Force
}
```

## Mark an entry done — atomic write, mirrors the config-writer temp-file pattern

```bash
mark_done() {  # mark_done <target> — persist Target's status as done (atomic)
  local target="$1" tmp
  tmp="$(mktemp "${STATE_DIR}/.update-state.XXXXXX")" || return 1
  jq --arg t "$target" '.entries[$t] = "done"' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}
```

```powershell
function Set-EntryDone([string]$Target) {
    $state = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json -AsHashtable
    $state.entries[$Target] = 'done'
    $tmp = Join-Path $StateDir ('.update-state.' + [System.IO.Path]::GetRandomFileName())
    Set-Content -LiteralPath $tmp -Value ($state | ConvertTo-Json -Depth 10) -Encoding utf8NoBOM -NoNewline
    Move-Item -LiteralPath $tmp -Destination $StateFile -Force
}
```

**Which sub-steps call `mark_done`/`Set-EntryDone` directly vs. via live-recheck:**
Docs (4(1), one `write-project-docs` call per anchor) and Configs (4(2), one union-write
call covering every config-key Target this run) are each a **single, per-entry (or
per-run-batch) invocation** — its own exit code tells `update` the Target(s) succeeded,
so it marks them done immediately after that call. Protection (4(6)) and CI (4(5)) are
likewise single-target invocations (one protected branch, one workflow path) — their
exit code (0 = written/no-op) marks that one Target done. **Labels (4(3)) and the
branch model (4(4)) are the exception**: `provision-labels.*` / `provision-branches.*`
take no per-target flags — they upsert/create everything in one bulk call with one exit
code covering N independent labels or branches. A single exit code cannot tell `update`
*which* of those N Targets actually landed, so per-entry status there is derived
independently, below.

## Live-recheck after the bulk label/branch scripts

```bash
./scripts/provision-labels.sh
# LABEL_WORKLIST: newline-separated bare label names (Step 3's Labels sub-table
# add-class rows). No per-target flag exists, so re-list live labels and derive
# each Target's done status from presence (create-if-missing => present = done).
live_labels="$(gh label list --limit 100 --json name --jq '.[].name')"
printf '%s\n' "$LABEL_WORKLIST" | while IFS= read -r target; do
  [ -z "$target" ] && continue
  is_done "$target" && continue
  if printf '%s\n' "$live_labels" | grep -Fxq -- "$target"; then
    mark_done "$target"
  fi
done

./scripts/provision-branches.sh --repo "<repo>"
# BRANCH_WORKLIST: newline-separated "branch: <name>" Targets (Step 3's Branch
# model sub-table add-class rows). Re-derive existence per branch the same way
# provision-branches.sh's own branch_exists() does (scripts/provision-branches.sh).
SLUG_REPO="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
printf '%s\n' "$BRANCH_WORKLIST" | while IFS= read -r target; do
  [ -z "$target" ] && continue
  is_done "$target" && continue
  name="${target#branch: }"
  if gh api "repos/${SLUG_REPO}/branches/${name}" >/dev/null 2>&1; then
    mark_done "$target"
  fi
done
```

```powershell
./scripts/provision-labels.ps1
$liveLabels = gh label list --limit 100 --json name --jq '.[].name'
foreach ($target in $LabelWorklist) {
    if ((Test-EntryDone $target)) { continue }
    if ($liveLabels -contains $target) { Set-EntryDone $target }
}

./scripts/provision-branches.ps1 -Repo "<repo>"
$slugRepo = gh repo view --json nameWithOwner --jq '.nameWithOwner'
foreach ($target in $BranchWorklist) {
    if ((Test-EntryDone $target)) { continue }
    $name = $target -replace '^branch: ', ''
    gh api "repos/$slugRepo/branches/$name" *> $null
    if ($LASTEXITCODE -eq 0) { Set-EntryDone $target }
}
```

## Resume and completion

A re-run walks the worklist in the same order Step 3 recorded it, calling `is_done`
(`Test-EntryDone`) first and skipping — no re-diff, no re-narration, no re-write — for
every Target already `done`; the walk resumes at the first not-done entry. A Target
left `pending` only because Step 0's `gh` precondition blocked its (remote) reconcile —
not because the run was interrupted — is correctly left `pending`: a later run, once the
precondition clears, resumes and attempts it like any other not-yet-done entry, never
silently marked `done` because the run "got to it."

When every worklist entry reaches `done`, delete the state file before Step 6's report —
it is ephemeral resume-scratch for surviving an interruption, not a persistent ledger
(mirrors `apply`'s no-apply-side-state-ledger stance, `skills/apply/SKILL.md` Step 4):

```bash
rm -f "$STATE_FILE"
```

```powershell
Remove-Item -LiteralPath $StateFile -Force -ErrorAction SilentlyContinue
```

A subsequent clean run finds no state file present — identical to a first-ever run.
