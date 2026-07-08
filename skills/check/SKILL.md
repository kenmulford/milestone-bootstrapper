---
name: check
description: This skill should be used when the user invokes "/milestone-bootstrapper:check", or asks to "check the project docs for drift", "has the project docs gone stale", "did my project docs go stale", "review .project/ against the live repo", "audit the project docs before I trust them", or "is the bootstrap still accurate". Thin, read-only orchestration layer that invokes the component script `scripts/check-project-docs.{sh,ps1}` (introduced by #129) and surfaces any detected drift between the repo's `.project/` docs and the live stack as an advisory review prompt — the human decides what to do with it. Read-only: it writes nothing, proposes nothing, and never invokes `update`. No flags. Authors no code; opens no PRs.
---

# check — read-only drift audit against `.project/` docs

Invoke the component script `scripts/check-project-docs.{sh,ps1}` (#129) and report exactly what it finds. The script's scope today is exactly one doc+anchor — `.project/library-manifest.md#Runtime & frameworks` (the whole of #129); it does not diff `conventions.md`, `domainSkills`, or any other `.project/` doc. `check`'s scope is therefore exactly whatever that script checks — it never audits more of `.project/` than the script does, and it widens automatically if the script's scope ever widens. This is a fourth verb alongside `plan`/`apply`/`update`, not an extension of `update`: `update` writes and reconciles state, `check` writes nothing and only reports — serving the suite's auditability goal (`.project/design-philosophy.md#What we optimize for`). `check` **composes** the script; it performs none of its diagnostic logic itself (`.project/design-philosophy.md#Layering & boundaries` — "skills orchestrate ordering and reporting only... each step is a thin invocation of the component script that owns its slice — skills never duplicate component logic").

## Announce first

Say this to the user before doing any work:

> Standing by while I check whether your `.project/` docs still match the live repo. This is read-only — I invoke the drift-check script and relay exactly what it reports; I write nothing, propose no fix, and never call `update` on your behalf. If drift turns up, you decide what to do about it.

## Procedure

### Step 0 — Confirm the repo shows evidence of a prior `apply`

There is nothing to check until a prior `apply` has run. Read-only, for **either** `.project/` **or** `.milestone-config/` (mirrors `update`'s Step 1 bootstrapped-repo check, `skills/update/SKILL.md:43-62`, adapted from its ERROR-AND-STOP to this verb's advisory stance — `check` never hard-stops the session, it just has nothing to invoke the script against yet):

```bash
docs=".project"; cfg=".milestone-config"
[ -d "$docs" ] && [ -n "$(ls -A "$docs" 2>/dev/null)" ] && have_docs=1 || have_docs=0
[ -d "$cfg" ]  && [ -n "$(ls -A "$cfg"  2>/dev/null)" ] && have_cfg=1  || have_cfg=0
```

```powershell
$docs = ".project"; $cfg = ".milestone-config"
$haveDocs = (Test-Path -LiteralPath $docs) -and ((Get-ChildItem -LiteralPath $docs -Force -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)
$haveCfg  = (Test-Path -LiteralPath $cfg)  -and ((Get-ChildItem -LiteralPath $cfg  -Force -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)
```

| Evidence | Action |
|---|---|
| **Neither present** | Report: "Nothing to check yet — this repo shows no evidence of a prior apply. Run `/milestone-bootstrapper:apply` first, then `check` will have something to compare against." Advisory, not an error — stop here; do not invoke the script. |
| **At least one present** | Proceed to Step 1. A partial bootstrap is never a reason to skip the check — the script itself resolves what it can compare. |

### Step 1 — Invoke the drift-check script (default mode — never `--check`/`-Check`)

Run from the repo root, with no flags:

```bash
./scripts/check-project-docs.sh
```

```powershell
./scripts/check-project-docs.ps1
```

**Never pass `--check`/`-Check`.** That flag turns drift into a nonzero (CI-gating) exit — it is the CI-only path the script's own header reserves for automated gating, not this human-facing verb (issue Design → Scope boundary). Capture stdout, stderr, and the real exit code.

### Step 2 — Branch on the script's three-class exit contract

Branch on **exit code first**, then on stdout within the exit-0 case — the script's own documented contract (`scripts/check-project-docs.sh` header, "Exit codes"):

| Exit code | Meaning | What `check` does |
|---|---|---|
| **1** | Usage / read error (bad `--repo`, missing `.project/library-manifest.md`, a `detect-stack` failure, unparseable output) — **always nonzero**, fires in this default invocation too, not only under `--check`. | **Error path.** Relay the script's stderr message verbatim. Stop — no further action, no fallback "no drift" report. Never swallow the failure (`.project/design-philosophy.md#Error & failure philosophy` — "flag, don't guess"). |
| **0**, stdout carries no `DRIFT — ` line | Clean run — no drift, OR the sentinel "no application stack detected — nothing to compare", OR the anchor is still `[TBD]` and skipped. All three are legitimate non-drift outcomes the script reports in its own words. | **Happy path.** Relay the script's stdout **verbatim** — do not substitute a canned string. Report the outcome as clean. Perform no further action. |
| **0**, stdout carries one or more `DRIFT — ` lines | Drift found — the script names each detected stack the manifest doesn't mention, plus its summary count and the "informational only" trailer. | **Drift path.** Relay the script's stdout verbatim, then list the drifted doc/anchor(s) as an advisory review prompt. State explicitly that the human decides. Do **not** invoke `update`, propose an automatic fix, or rewrite any `.project/` prose (mirrors the PROPOSE-not-PATCH posture `skills/update/SKILL.md` uses for human-owned docs, Step 4(1) — `check` goes one step further and never writes at all, but reuses the same "show it, human decides" reporting shape). |

`--check`'s exit `2` never occurs here — Step 1 never passes that flag. Discriminate the happy path from the drift path by the presence of a `DRIFT — ` line in stdout, not by matching any single canned message — this keeps `check` correct even if the script's exact non-drift wording changes, without re-implementing its diff logic.

Drift is never treated as a failure through this skill: every exit-0 outcome — clean or drifted — concludes informationally, matching the script's own "informational only" framing.

### Step 3 — Report

One outcome per run: nothing-to-check-yet (Step 0), the error path (Step 2, exit 1), the happy path (Step 2, exit 0/no drift), or the drift path (Step 2, exit 0/drift found). Nothing is written anywhere in any branch.

## Output style

Be concise — report the outcome flatly, no wall-of-text. Relay the script's own stdout/stderr verbatim rather than paraphrasing it. Present a multi-item drift list as a table, not inline prose. Mark the drift outcome with 🔴 — it needs a human to look, even though nothing failed. Mark an error outcome with 🔴 too — that one is a real failure (exit 1) the human needs to see. (Mirrors the suite's shared output style — `skills/plan/SKILL.md` Output style, `skills/update/SKILL.md` Output style.)

## Non-negotiables

- **Strictly read-only — writes nothing, ever.** No `.project/` edit, no `.milestone-config/` edit, no proposal file, no GitHub state of any kind. `check` invokes one script and reports; every other verb in the suite (`plan`, `apply`, `update`) is the one that writes.
- **Never invokes `update` and never proposes an automatic fix.** Drift is surfaced as information for the human to act on — `check` does not decide, patch, or reconcile anything on its own (issue AC4; `.project/design-philosophy.md#One-way doors`).
- **Relay, don't restate.** The script's own stdout is the message — both the "no drift" summary and the sentinel "no application stack detected" line reach the user verbatim, never replaced by a fixed canned string (issue AC1; thin-orchestration convention, `.project/design-philosophy.md#Layering & boundaries`).
- **Exit code first, then stdout.** Exit `1` is always the error/failure path regardless of the drift check's outcome; exit `0` branches on stdout between clean and drift. `check` never passes `--check`/`-Check`, so the CI-only exit `2` never occurs here.
- **No duplicated diagnostic logic.** All stack-detection and drift-diffing logic lives in `scripts/check-project-docs.{sh,ps1}` (#129); `check` is invocation + reporting only — it never re-implements the presence check, the anchor walk, or the sentinel-row exclusion.
- **No flags.** Matches the sibling verbs' stated convention (`skills/plan/SKILL.md:3`, `skills/update/SKILL.md:225`) — `check` takes no arguments.
- **Authors no code, opens no PRs, never touches branches.** Reads repo state to ground its report; never edits a source file, creates a branch, or opens a PR.
