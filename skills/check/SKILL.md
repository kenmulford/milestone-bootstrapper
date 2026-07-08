---
name: check
description: This skill should be used when the user invokes "/milestone-bootstrapper:check", or asks to "check the project docs for drift", "has the project docs gone stale", "did my project docs go stale", "review .project/ against the live repo", "audit the project docs before I trust them", "is the bootstrap still accurate", "check the driver config for drift", or "has domainSkills drifted". Thin, read-only orchestration layer that invokes the component scripts `scripts/check-project-docs.{sh,ps1}` (introduced by #129) and `scripts/check-driver-config.{sh,ps1}` (introduced by #139) and surfaces any detected drift — between the repo's `.project/` docs and the live stack, and between `.milestone-config/driver.json`'s `domainSkills` and the live stack — as an advisory review prompt — the human decides what to do with it. Read-only: it writes nothing, proposes nothing, and never invokes `update`. No flags. Authors no code; opens no PRs.
---

# check — read-only drift audit against `.project/` docs and driver config

Invoke the two component scripts — `scripts/check-project-docs.{sh,ps1}` (#129) and `scripts/check-driver-config.{sh,ps1}` (#139) — and report exactly what each finds. `check-project-docs`'s scope today is exactly one doc+anchor — `.project/library-manifest.md#Runtime & frameworks` (the whole of #129); it does not diff `conventions.md` or any other `.project/` doc. `check-driver-config`'s scope is exactly one field of one file — `.milestone-config/driver.json`'s `domainSkills` array (the whole of #139); it touches nothing else in `driver.json` and nothing in `.project/`. `check`'s scope is therefore exactly the union of what these two scripts check — it never audits more than the two scripts do, and it widens automatically if either script's scope ever widens. This is a fourth verb alongside `plan`/`apply`/`update`, not an extension of `update`: `update` writes and reconciles state, `check` writes nothing and only reports — serving the suite's auditability goal (`.project/design-philosophy.md#What we optimize for`). `check` **composes** the two scripts; it performs none of their diagnostic logic itself (`.project/design-philosophy.md#Layering & boundaries` — "skills orchestrate ordering and reporting only... each step is a thin invocation of the component script that owns its slice — skills never duplicate component logic").

## Announce first

Say this to the user before doing any work:

> Standing by while I check whether your `.project/` docs and `.milestone-config/driver.json` domainSkills still match the live repo. This is read-only — I invoke the two drift-check scripts and relay exactly what each reports; I write nothing, propose no fix, and never call `update` on your behalf. If drift turns up, you decide what to do about it.

## Procedure

### Step 0 — Confirm the repo shows evidence of a prior `apply`

There is nothing to check until a prior `apply` has run. Read-only, for **either** `.project/` **or** `.milestone-config/` (mirrors `update`'s Step 1 bootstrapped-repo check, `skills/update/SKILL.md:43-62`, adapted from its ERROR-AND-STOP to this verb's advisory stance — `check` never hard-stops the session, it just has nothing to invoke the scripts against yet):

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
| **Neither present** | Report: "Nothing to check yet — this repo shows no evidence of a prior apply. Run `/milestone-bootstrapper:apply` first, then `check` will have something to compare against." Advisory, not an error — stop here; do not invoke either script. |
| **At least one present** | Proceed to Step 1. A partial bootstrap is never a reason to skip the check — each script itself resolves what it can compare. |

`have_cfg` / `$haveCfg` here is a **directory-level** presence test only (`.milestone-config/` non-empty, satisfied by any file in it — e.g. `feeder.json` or a notice marker). It is not reused as the `check-driver-config` precondition test in Step 1b below, which is a distinct, file-specific test.

### Step 1 — Invoke the drift-check scripts (default mode — never `--check`/`-Check`)

#### Step 1a — `check-project-docs` (unchanged)

Run from the repo root, with no flags:

```bash
./scripts/check-project-docs.sh
```

```powershell
./scripts/check-project-docs.ps1
```

**Never pass `--check`/`-Check`.** That flag turns drift into a nonzero (CI-gating) exit — it is the CI-only path the script's own header reserves for automated gating, not this human-facing verb (issue Design → Scope boundary). Capture stdout, stderr, and the real exit code.

#### Step 1b — `check-driver-config` (precondition-gated)

Before invoking `check-driver-config`, perform a **new, driver.json-file-specific existence test** — this is **not** a reuse of Step 0's `have_cfg`, which tests only that `.milestone-config/` is non-empty and is satisfied by any file in it, not specifically `driver.json`. Conflating the two would wrongly invoke `check-driver-config` when `.milestone-config/` holds other files (e.g. `feeder.json`, a notice marker) but not yet `driver.json`, reproducing the script's own hard exit-1 error from a bootstrapping-order gap.

```bash
[ -f ".milestone-config/driver.json" ]
```

```powershell
Test-Path -LiteralPath ".milestone-config/driver.json" -PathType Leaf
```

| Test result | Action |
|---|---|
| **False** (file absent — including the `.project/`-present-but-`.milestone-config/`-absent case) | **Skip the invocation entirely.** Do not run `check-driver-config`. Record the advisory line `check-driver-config: not yet configured — run milestone-driver:setup first.` for Step 2/3. |
| **True** (file present) | Run from the repo root, with no flags: |

```bash
./scripts/check-driver-config.sh
```

```powershell
./scripts/check-driver-config.ps1
```

**Never pass `--check`/`-Check`** — same CI-only reservation as `check-project-docs` (Step 1a). Capture stdout, stderr, and the real exit code.

`check-project-docs`'s own invocation (Step 1a) carries no equivalent gate — it is unchanged from the prior milestone's shipped behavior. Neither script's invocation (or gated skip) is affected by the other's outcome — an error, drift, or skip on one never skips or alters the other's independent invocation.

### Step 2 — Branch on each script's exit contract, then aggregate

Each invoked script resolves its own three-class exit contract independently — branch on exit code first, then on stdout within the exit-0 case (`scripts/check-project-docs.sh` / `scripts/check-driver-config.sh` headers, "Exit codes"):

| Exit code | Meaning | What `check` does |
|---|---|---|
| **1** | Usage / read error (bad `--repo`, missing `.project/library-manifest.md`, missing/malformed `driver.json` domainSkills, a `detect-stack` invocation failure, unparseable output) — **always nonzero**, fires in this default invocation too, not only under `--check`. | **Error path for that script.** Relay its stderr message verbatim, attributed to that script by name — no fallback "no drift" report for that script. Never swallow the failure (`.project/design-philosophy.md#Error & failure philosophy` — "flag, don't guess"). This does not stop or alter the other script's own invocation or outcome — see the aggregation rule below. |
| **0**, stdout carries no `DRIFT — ` line | Clean run for that script — no drift, OR a legitimate non-drift sentinel (e.g. "no application stack detected — nothing to compare", an anchor still `[TBD]` and skipped, or `check-driver-config`'s own "nothing to compare — no non-exempt application stack detected"). | **Happy path for that script.** Relay its stdout **verbatim**, attributed to that script by name — do not substitute a canned string. |
| **0**, stdout carries one or more `DRIFT — ` lines | Drift found for that script — it names each drifted item plus its summary count and the "informational only" trailer. | **Drift path for that script.** Relay its stdout verbatim, attributed by name, then list the drifted item(s) as an advisory review prompt. State explicitly that the human decides. Do **not** invoke `update`, propose an automatic fix, or rewrite any `.project/` prose or `.milestone-config/driver.json` (mirrors the PROPOSE-not-PATCH posture `skills/update/SKILL.md` uses for human-owned state, Step 4(1) — `check` goes one step further and never writes at all, but reuses the same "show it, human decides" reporting shape). |

`check-driver-config`'s Step 1b precondition-gate skip is a **fourth, script-specific outcome** — not an exit code — and surfaces as its own attributed advisory line (`check-driver-config: not yet configured — run milestone-driver:setup first.`), distinct from the exit-1 error path above and never triggering it (the invocation that would raise that error never runs).

**Aggregation rule.** Each script's outcome — clean, drift, error, or (for `check-driver-config` only) precondition-skipped-advisory — surfaces as its **own attributed line/row** in the combined report, never merged or summarized together. An error or skip on one script is never swallowed by the other script's clean result, and drift on one never masks or is masked by the other's independent outcome — even when the other script is itself clean.

`--check`'s exit `2` never occurs here — Step 1 never passes that flag to either script. Discriminate the happy path from the drift path by the presence of a `DRIFT — ` line in stdout, not by matching any single canned message — this keeps `check` correct even if either script's exact non-drift wording changes, without re-implementing its diff logic.

Drift is never treated as a failure through this skill: every exit-0 outcome — clean, drifted, or precondition-skipped-advisory — concludes informationally, matching each script's own "informational only" framing.

### Step 3 — Report

One combined, aggregated report per run: nothing-to-check-yet (Step 0, applies once, before either script would run), or — for each script that was invoked or gated — its own attributed outcome: the error path, the happy path, the drift path (Step 2), or (`check-driver-config` only) the precondition-skipped advisory (Step 1b). Nothing is written anywhere in any branch.

## Output style

Be concise — report each script's outcome flatly, no wall-of-text. Relay each script's own stdout/stderr verbatim rather than paraphrasing it, attributed by script name. Present a multi-item drift list as a table, not inline prose. Mark a drift outcome with 🔴 — it needs a human to look, even though nothing failed. Mark an error outcome with 🔴 too — that one is a real failure (exit 1) the human needs to see. The `check-driver-config` precondition-skipped advisory is not an error — mark it plainly, no 🔴. (Mirrors the suite's shared output style — `skills/plan/SKILL.md` Output style, `skills/update/SKILL.md` Output style.)

## Non-negotiables

- **Strictly read-only — writes nothing, ever.** No `.project/` edit, no `.milestone-config/` edit, no proposal file, no GitHub state of any kind. `check` invokes the two component scripts and reports; every other verb in the suite (`plan`, `apply`, `update`) is the one that writes.
- **Never invokes `update` and never proposes an automatic fix.** Drift is surfaced as information for the human to act on — `check` does not decide, patch, or reconcile anything on its own (issue AC4; `.project/design-philosophy.md#One-way doors`).
- **Relay, don't restate.** Each script's own stdout is the message — both scripts' outputs (each attributed by name) reach the user verbatim, never replaced by a fixed canned string (issue AC1; thin-orchestration convention, `.project/design-philosophy.md#Layering & boundaries`). The one exception is the `check-driver-config` precondition-skip advisory (Step 1b), which is a `check`-authored line describing why the script was not invoked — there is no script stdout to relay in that branch because the script never ran.
- **Exit code first, then stdout.** Applies independently to each invoked script. Exit `1` is always that script's error/failure path regardless of the drift check's outcome; exit `0` branches on stdout between clean and drift. `check` never passes `--check`/`-Check` to either script, so the CI-only exit `2` never occurs here.
- **No duplicated diagnostic logic.** All stack-detection and drift-diffing logic lives in `scripts/check-project-docs.{sh,ps1}` (#129) and `scripts/check-driver-config.{sh,ps1}` (#139); `check` is invocation + reporting only for both — it never re-implements either script's presence check, anchor/set comparison, or sentinel-row exclusion. The Step 1b precondition test is a narrow file-existence gate, not diagnostic logic — it decides *whether* to invoke `check-driver-config`, never *what* it would find.
- **No flags.** Matches the sibling verbs' stated convention (`skills/plan/SKILL.md:3`, `skills/update/SKILL.md:225`) — `check` takes no arguments.
- **Authors no code, opens no PRs, never touches branches.** Reads repo state to ground its report; never edits a source file, creates a branch, or opens a PR.
